#cloud-config

write_files:
  - path: /opt/vyatta/etc/config/scripts/vyos-postconfig-bootup.script
    owner: root:vyattacfg
    permissions: '0775'
    content: |
      #!/bin/vbash
      source /opt/vyatta/etc/functions/script-template

      # MARKER to bootstrapper BGP/NAT only one time
      # (this script is executed on each reboot)
      MARKER=/config/.bootstrapped

      if [ ! -f $MARKER ]; then
        configure

        # System Hostname
        set system host-name '${hostname}'

        # -------------------------------------------------------------
        # 0. Intra-VNet routing via the External interface (eth1)
        # Without this, subnets that are not directly connected (adm, int)
        # are reached through the default route on eth0, so a DNAT'd session
        # leaves on eth0 while the reply comes back on eth1. Conntrack copes,
        # but the asymmetry breaks as soon as source-validation is enabled.
        # -------------------------------------------------------------
        set protocols static route '${vnet_cidr}' next-hop '${ext_gateway}'

        # -------------------------------------------------------------
        # 1. Source NAT (Outbound Internet via DMZ interface eth0)
        # All traffic from VNet (${vnet_cidr}) is masqueraded out eth0
        # -------------------------------------------------------------
        set nat source rule 100 outbound-interface name 'eth0'
        set nat source rule 100 source address '${vnet_cidr}'
        set nat source rule 100 translation address 'masquerade'

        # -------------------------------------------------------------
        # 2. BGP Configuration (VyOS 1.5 Syntax)
        # -------------------------------------------------------------
        set protocols bgp system-as ${bgp_asn}
        set protocols bgp parameters router-id '${router_id}'

        %{ for n in bgp_neighbors ~}
        set protocols bgp neighbor ${n.ip} remote-as ${n.remote_asn}
        set protocols bgp neighbor ${n.ip} address-family ipv4-unicast
        set protocols bgp neighbor ${n.ip} description 'F5-XC-CE'
        %{ endfor ~}

        # ECMP: both CEs share ASN 65100, so FRR needs multipath-relax
        set protocols bgp parameters bestpath as-path 'multipath-relax'

        # Log BGP adjacency up/down. Without this FRR never generates the
        # %ADJCHANGE messages at all. Note it is only half the job - see the
        # FRR log-level block at the end of this script.
        set protocols bgp parameters log-neighbor-changes
        
        # Accept only the XC VIP range from the CEs; advertise nothing back
        set policy prefix-list XC-VIPS rule 10 action 'permit'
        set policy prefix-list XC-VIPS rule 10 prefix '${vip_cidr}'
        set policy prefix-list XC-VIPS rule 10 le '32'
        set policy route-map FROM-XC rule 10 action 'permit'
        set policy route-map FROM-XC rule 10 match ip address prefix-list 'XC-VIPS'
        set policy route-map TO-XC rule 10 action 'deny'
        %{ for n in bgp_neighbors ~}
        set protocols bgp neighbor ${n.ip} address-family ipv4-unicast soft-reconfiguration inbound
        set protocols bgp neighbor ${n.ip} address-family ipv4-unicast route-map import 'FROM-XC'
        set protocols bgp neighbor ${n.ip} address-family ipv4-unicast route-map export 'TO-XC'
        %{ endfor ~}

        # ECMP Load Balancing across both F5 XC Customer Edges
        set protocols bgp address-family ipv4-unicast maximum-paths ebgp ${bgp_maximum_paths_ebgp}

        # -------------------------------------------------------------
        # 3. Destination NAT (Port Forwarding to VIP / Internal Servers)
        # -------------------------------------------------------------
        %{ for i, rule in dnat_rules ~}
        set nat destination rule ${100 + i} inbound-interface name 'eth0'
        set nat destination rule ${100 + i} destination port '${rule.public_port}'
        set nat destination rule ${100 + i} protocol '${rule.protocol}'
        set nat destination rule ${100 + i} translation address '${rule.private_ip}'
        set nat destination rule ${100 + i} translation port '${rule.private_port}'
        %{ endfor ~}

        # -------------------------------------------------------------
        # 4. Egress firewall - only the proxy may reach the Internet directly
        # Everything else in the VNet must go through Tinyproxy on the services VM.
        # This filters the FORWARD chain only, so the router's own traffic and
        # anything staying inside the VNet are untouched (intra-VNet traffic
        # never reaches this router: the Azure VNet system route is more
        # specific than the 0.0.0.0/0 UDR pointing here).
        # -------------------------------------------------------------
        set firewall ipv4 forward filter default-action 'accept'

        # Rule 10 MUST come before the drop. Inbound DNAT'd sessions (RDP/SSH
        # to the jumphost, 80/443 to the XC VIP) send their REPLIES out eth0
        # with a VNet source address, which would otherwise match rule 90 and
        # be dropped. Matching established/related first keeps them working.
        set firewall ipv4 forward filter rule 10 action 'accept'
        set firewall ipv4 forward filter rule 10 state 'established'
        set firewall ipv4 forward filter rule 10 state 'related'
        # set firewall ipv4 forward filter rule 10 log
        set firewall ipv4 forward filter rule 10 description 'Return traffic for existing sessions'
        # Deliberately NOT logged: this rule matches every packet of every
        # established session (millions), so logging it would bury the signal
        # and fill the disk. Rules 20 and 90 log NEW connections only.

        # Sources allowed to open NEW connections to the Internet.
        %{ for i, src in egress_allowed ~}
        set firewall ipv4 forward filter rule ${20 + i} action 'accept'
        set firewall ipv4 forward filter rule ${20 + i} outbound-interface name 'eth0'
        set firewall ipv4 forward filter rule ${20 + i} source address '${src}'
        set firewall ipv4 forward filter rule ${20 + i} description 'Direct egress permitted'
        set firewall ipv4 forward filter rule ${20 + i} log
        %{ endfor ~}

        # Everything else from the VNet: drop and log. `log` writes to syslog,
        # which is the hook for a SIEM later - point it at a collector with
        # `set system syslog remote <ip> facility all level info` (see section 5).
        set firewall ipv4 forward filter rule 90 action 'drop'
        set firewall ipv4 forward filter rule 90 outbound-interface name 'eth0'
        set firewall ipv4 forward filter rule 90 source address '${vnet_cidr}'
        set firewall ipv4 forward filter rule 90 log
        set firewall ipv4 forward filter rule 90 description 'DROP direct egress - use the proxy'

        # -------------------------------------------------------------
        # 5. Remote syslog to the observability VM
        # NOTE: the node is 'remote', NOT 'host' - VyOS 1.4 renamed it, and the
        # old form fails. Sends both the FRR/BGP messages and the kernel
        # firewall drops (rule 90 / rule 20 'log') to Alloy on the obs VM.
        # -------------------------------------------------------------
        set system syslog remote '${syslog_host}' facility all level 'info'
        set system syslog remote '${syslog_host}' protocol 'udp'
        set system syslog remote '${syslog_host}' port '514'

        commit
        save

        touch $MARKER
        sync

        # Reboot once, immediately after bootstrapping.
        #
        # The config session this script runs in leaves the VyOS config
        # subsystem unable to accept further changes until the next boot: every
        # subsequent `set` fails with "Set failed", including unrelated ones
        # like `set system time-zone`. A reboot clears it. Without this you
        # cannot toggle e.g. `rule 90 disable` or rule 10 logging by hand until
        # you have rebooted the router manually.
        #
        # Safe to do here because MARKER is written ABOVE: on the way back up
        # this whole block is skipped, the saved config.boot is loaded normally,
        # and the router returns fully configured and immediately editable.
        # Never move the touch below this line - the script would re-run every
        # boot and the router would reboot-loop.
        #
        # /sbin/reboot, not the op-mode `reboot`, which prompts for confirmation
        # and would hang a non-interactive boot script.
        /sbin/reboot
        exit
      fi

      # -----------------------------------------------------------------
      # Runs on EVERY boot, deliberately OUTSIDE the MARKER guard above.
      #
      # FRR logs %ADJCHANGE (BGP neighbour up/down) at *informational*, but
      # VyOS renders `log syslog notifications` by default, so those messages
      # are dropped and BGP looks silent in Loki even though the syslog path
      # works. There is no CLI knob for this: vyos/frrender.py switches on the
      # presence of a file -
      #     if os.path.exists(frr_debug_enable):  -> log syslog informational
      # with frr_debug_enable = '/tmp/vyos.frr.debug' (vyos/defaults.py).
      #
      # /tmp is wiped on reboot, hence every boot. The touch makes any future
      # `commit` re-render keep informational; the vtysh call applies it now
      # without waiting for a re-render. Side effect: this is VyOS's FRR debug
      # switch, so it also enables `log unique-id` (the [EC nnnn] prefixes).
      # Remove both lines to go back to notifications-only.
      # -----------------------------------------------------------------
      touch /tmp/vyos.frr.debug
      /usr/bin/vtysh -c 'configure terminal' -c 'log syslog informational' -c 'end' >/dev/null 2>&1 || true
