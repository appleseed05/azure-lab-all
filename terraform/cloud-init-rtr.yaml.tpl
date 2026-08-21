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
        # All traffic from VNet (10.1.0.0/16) is masqueraded out eth0
        # -------------------------------------------------------------
        set nat source rule 100 outbound-interface name 'eth0'
        set nat source rule 100 source address '10.1.0.0/16'
        set nat source rule 100 translation address 'masquerade'

        # -------------------------------------------------------------
        # 2. BGP Configuration (VyOS 1.5 Syntax)
        # -------------------------------------------------------------
        set protocols bgp system-as ${bgp_asn}
        set protocols bgp parameters router-id '10.1.10.254'

        %{ for n in bgp_neighbors ~}
        set protocols bgp neighbor ${n.ip} remote-as ${n.remote_asn}
        set protocols bgp neighbor ${n.ip} address-family ipv4-unicast
        set protocols bgp neighbor ${n.ip} description 'F5-XC-CE'
        %{ endfor ~}

        # ECMP: both CEs share ASN 65100, so FRR needs multipath-relax
        set protocols bgp parameters bestpath as-path 'multipath-relax'
        
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

        commit
        save

        touch $MARKER
        exit
      fi
