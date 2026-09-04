#cloud-config
# The services VM sits in the ext subnet, whose route table sends 0.0.0.0/0 to
# the VyOS router. Like the application VM and the jumphost it has no public IP and
# no direct egress, so apt only works once the router has booted AND committed
# its source-NAT masquerade rule. The built-in `packages:` module runs early in
# the boot and never retries, so everything is done from runcmd behind the same
# egress wait loop used by cloud-init-app.yaml.tpl and cloud-init-jmp.yaml.tpl.
package_update: false

write_files:
  - path: /root/tinyproxy.conf
    owner: root:root
    permissions: '0644'
    content: |
      # Managed by cloud-init (cloud-init-svc.yaml.tpl) - local edits are lost
      # on redeploy. Based on the tinyproxy 1.11.1 packaged defaults.
      User tinyproxy
      Group tinyproxy
      Port ${proxy_port}
      Timeout 600
      DefaultErrorFile "/usr/share/tinyproxy/default.html"
      StatFile "/usr/share/tinyproxy/stats.html"
      # Syslog instead of LogFile so the lines reach the central log server.
      # These two directives are mutually exclusive in tinyproxy - setting both
      # is a config error, so LogFile is deliberately absent.
      Syslog On
      LogLevel Info
      PidFile "/run/tinyproxy/tinyproxy.pid"
      MaxClients 100
      ViaProxyName "tinyproxy"

      # No `Listen` directive on purpose: tinyproxy then binds every interface,
      # so the proxy is reachable from the other lab subnets and not only from
      # the services VM itself.

      # Who is allowed to use the proxy. Lab-wide: the whole VNet.
      Allow 127.0.0.1
      Allow ::1
      Allow ${allowed_cidr}

      # With no ConnectPort directive at all, tinyproxy allows CONNECT (HTTPS)
      # to ANY port. Uncomment these to restrict it to the usual ports once you
      # start enforcing proxy usage.
      #ConnectPort 443
      #ConnectPort 563

  # ---------------------------------------------------------------------------
  # Chrony - NTP server for the lab.
  # chrony is ALREADY installed on the Azure Ubuntu image and already synced to
  # the Azure host clock via "refclock PHC /dev/ptp_hyperv" in chrony.conf, so
  # there is nothing to install and nothing upstream to add. chrony.conf already
  # does "confdir /etc/chrony/conf.d", so this drop-in is picked up as-is and the
  # packaged chrony.conf stays untouched.
  # ---------------------------------------------------------------------------
  - path: /etc/chrony/conf.d/10-lab-ntp-server.conf
    owner: root:root
    permissions: '0644'
    content: |
      # Managed by cloud-init (cloud-init-svc.yaml.tpl).
      # Serve time to the whole lab VNet.
      allow ${allowed_cidr}
      # Keep answering even if the PTP refclock ever goes away, so lab clients
      # never hang waiting for an NTP source. Stratum 10 = clearly low quality.
      local stratum 10

  # ---------------------------------------------------------------------------
  # BIND9 - staged in /root and copied into /etc/bind AFTER the package install.
  # Writing straight to /etc/bind here would put files in place before dpkg
  # unpacks the package, and named.conf.options / named.conf.local are dpkg
  # CONFFILES: pre-existing content turns the install into a conffile conflict.
  # Same staging pattern the application VM uses for its nginx site.
  # ---------------------------------------------------------------------------
  - path: /root/named.conf.options
    owner: root:root
    permissions: '0644'
    content: |
      // Managed by cloud-init (cloud-init-svc.yaml.tpl).
      acl "lab" {
          ${allowed_cidr};
          localhost;
      };

      options {
          directory "/var/cache/bind";

          // Do NOT use "any": systemd-resolved already owns 127.0.0.53:53 on
          // this host, and named would fail to bind it. Bind only the lab
          // address and loopback, leaving resolved's stub listener alone.
          listen-on { 127.0.0.1; ${dns_listen_ip}; };
          listen-on-v6 { none; };

          // Full recursion for Internet FQDNs, using the root hints that ship
          // in /etc/bind/named.conf.default-zones. No forwarders on purpose.
          recursion yes;
          allow-query { lab; };
          allow-recursion { lab; };
          allow-transfer { none; };

          dnssec-validation auto;
      };

  - path: /root/named.conf.local
    owner: root:root
    permissions: '0644'
    content: |
      // Managed by cloud-init (cloud-init-svc.yaml.tpl).
      zone "${dns_zone}" {
          type master;
          file "/etc/bind/db.${dns_zone}";
          allow-update { none; };
      };

      // Azure-internal names (<vm>.<guid>.internal.cloudapp.net) live ONLY in
      // Azure's own resolver: a root-hints recursion returns NXDOMAIN for them.
      // The jumphost and application VM use this server as their only resolver
      // (netplan use-dns:false), so without this they lose Azure name
      // resolution completely. 168.63.129.16 is Azure's fixed platform
      // resolver - same address in every region, so it is not a lab variable.
      //
      // Safe under DNSSEC: cloudapp.net has NO DS record in .net, so the
      // delegation is insecure and the validator never tries to verify these
      // forwarded answers. No validate-except is needed.
      //
      // Scoped to internal.cloudapp.net on purpose - the PUBLIC cloudapp.net
      // zone keeps resolving normally through recursion.
      // Send named's own messages to syslog (daemon facility) so rsyslog can
      // forward them to the observability VM along with everything else.
      logging {
          channel lab_syslog {
              syslog daemon;
              severity info;
              print-category yes;
              print-severity yes;
          };
          category default { lab_syslog; };
          category queries { lab_syslog; };
      };

      zone "internal.cloudapp.net" {
          type forward;
          forward only;
          forwarders { 168.63.129.16; };
      };

  # Zone data is generated from local.dns_zone_records in
  # main-azvm-services.tf, which is built from the same variables that assign
  # the NIC addresses - so the zone cannot drift from the actual VM IPs.
  - path: /root/db.${dns_zone}
    owner: root:root
    permissions: '0644'
    content: |
      $TTL 300
      @       IN  SOA ns.${dns_zone}. hostmaster.${dns_zone}. (
                          1          ; serial (no secondaries, never needs bumping)
                          3600       ; refresh
                          600        ; retry
                          604800     ; expire
                          300 )      ; negative cache TTL

      @       IN  NS  ns.${dns_zone}.
      ns      IN  A   ${dns_listen_ip}

%{ for host, ip in dns_records ~}
      ${format("%-26s IN  A   %s", host, ip)}
%{ endfor ~}

  # Forward everything this host logs (tinyproxy, named, chronyd, sshd...) to
  # Alloy on the observability VM. The single @ means UDP; @@ would be TCP.
  - path: /etc/rsyslog.d/60-lab-forward.conf
    owner: root:root
    permissions: '0644'
    content: |
      *.* @${syslog_host}:514

runcmd:
  # Wait until egress via VyOS actually works (up to 60 x 20s = 20 min).
  # NOTE: plain `apt-get update` exits 0 even when every mirror is unreachable
  # (it only prints "W: Failed to fetch ..."), which would make this loop break
  # on the first attempt. APT::Update::Error-Mode=any promotes those warnings
  # to errors so the command actually exits non-zero and the loop retries.
  - |
    for i in $(seq 1 60); do
      if apt-get update -y -o APT::Update::Error-Mode=any; then
        echo "apt-get update OK on attempt $i"
        break
      fi
      echo "apt-get update failed (attempt $i), egress via VyOS not up yet, retrying in 20s..."
      sleep 20
    done
  - DEBIAN_FRONTEND=noninteractive apt-get install -y tinyproxy
  - cp /root/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
  - systemctl enable tinyproxy
  - systemctl restart tinyproxy
  # tinyproxy has no config-check flag (only -d/-c/-h/-v), so there is no
  # `nginx -t` equivalent to run before restarting: assert afterwards instead
  # and dump the journal into cloud-init-output.log if it did not come up.
  - |
    if systemctl is-active --quiet tinyproxy; then
      echo "tinyproxy is running and listening on port ${proxy_port}"
    else
      echo "ERROR: tinyproxy failed to start"
      journalctl -u tinyproxy -n 30 --no-pager
    fi

  # --- NTP (chrony) -----------------------------------------------------------
  # Nothing to install; just pick up the drop-in written above.
  - systemctl enable chrony
  - systemctl restart chrony

  # --- DNS (bind9) ------------------------------------------------------------
  - DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9-utils bind9-dnsutils
  - install -o root -g bind -m 0644 /root/named.conf.options /etc/bind/named.conf.options
  - install -o root -g bind -m 0644 /root/named.conf.local   /etc/bind/named.conf.local
  - install -o root -g bind -m 0644 /root/db.${dns_zone}     /etc/bind/db.${dns_zone}
  # Force named to IPv4-only. This VM has no IPv6 address and no v6 default
  # route, but BIND still follows AAAA glue for every authoritative server it
  # walks. Every one of those fails with "network unreachable" and burns the
  # query budget, so DNSSEC chain-building gives up and returns SERVFAIL on
  # signed zones - and the failure is then CACHED, so names stay broken until
  # an rndc flush. Symptom: dig @<svc-vm> www.iana.org -> SERVFAIL while
  # dig +cd -> NOERROR. There is no named.conf option for this; -4 is the
  # documented switch, and /etc/default/named only exists after the install.
  - sed -i 's|^OPTIONS=.*|OPTIONS="-u bind -4"|' /etc/default/named
  - grep -q '^OPTIONS=.*-4' /etc/default/named || echo 'OPTIONS="-u bind -4"' >> /etc/default/named
  # bind9 ships real validators (unlike tinyproxy), so check BEFORE restarting.
  # A bad config or zone aborts here with a readable error in cloud-init-output.log.
  - named-checkconf
  - named-checkzone ${dns_zone} /etc/bind/db.${dns_zone}
  - systemctl enable named
  - systemctl restart named
  - systemctl restart rsyslog
  - |
    if systemctl is-active --quiet named; then
      echo "named is running: recursive resolver + authoritative for ${dns_zone}"
    else
      echo "ERROR: named failed to start"
      journalctl -u named -n 30 --no-pager
    fi
