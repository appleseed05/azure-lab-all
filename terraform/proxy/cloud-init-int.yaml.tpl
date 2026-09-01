#cloud-config
package_update: false

write_files:
  - path: /etc/apt/apt.conf.d/00-lab-proxy
    owner: root:root
    permissions: '0644'
    content: |
      // Managed by cloud-init (cloud-init-int.yaml.tpl).
      // Sends all apt traffic through the Tinyproxy instance on the external VM.
      Acquire::http::Proxy "http://${proxy_ip}:${proxy_port}";
      Acquire::https::Proxy "http://${proxy_ip}:${proxy_port}";

  # --- NTP client: use the lab NTP server on the external VM -------------------
  - path: /etc/chrony/conf.d/10-lab-ntp-client.conf
    owner: root:root
    permissions: '0644'
    content: |
      # Managed by cloud-init. chrony.conf already does "confdir /etc/chrony/conf.d".
      server ${ntp_ip} iburst

  # --- DNS: staged here, installed at the very END of runcmd -------------------
  # NOT written straight to /etc/netplan: the lab resolver only knows the root
  # hints and f5demo.lan, so switching DNS before the package installs finish
  # would break name resolution mid-provisioning. Azure DHCP DNS stays in use
  # for the whole of cloud-init and is swapped out last.
  #
  # use-dns:false is required. Azure DHCP installs 168.63.129.16 as a *link*
  # resolver on eth0, and systemd-resolved prefers link servers over anything
  # global, so a resolved.conf drop-in alone would be silently ignored.
  # route-metric is repeated from 50-cloud-init.yaml so the merge cannot drop it.
  - path: /root/99-lab-dns.yaml
    owner: root:root
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4-overrides:
              route-metric: 100
              use-dns: false
            nameservers:
              addresses: [${dns_ip}]
              search: [${dns_zone}]

  - path: /root/nginx-default-site.conf
    owner: root:root
    permissions: '0644'
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name _;

          add_header X-Origin-Server   $server_addr always;
          add_header X-Seen-Client-IP  $remote_addr always;

          location / {
              default_type text/plain;
              return 200 "===== NGINX origin (internal VM) =====\nOrigin server IP      : $server_addr:$server_port\nRequest received from : $remote_addr:$remote_port   \nOriginal client (XFF) : $http_x_forwarded_for\nHost header           : $host\nURI                   : $request_uri\nDate                  : $time_iso8601\n";
          }
      }

runcmd:
  # Wait until apt works. apt now goes through the Tinyproxy on the external VM
  # (see /etc/apt/apt.conf.d/00-lab-proxy above), so this loop transparently
  # waits for BOTH the VyOS egress AND tinyproxy to be up.
  - |
    for i in $(seq 1 60); do
      if apt-get update -y -o APT::Update::Error-Mode=any; then
        echo "apt-get update OK on attempt $i"
        break
      fi
      echo "apt-get update failed (attempt $i), retrying in 20s..."
      sleep 20
    done
  - DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  - cp /root/nginx-default-site.conf /etc/nginx/sites-available/default
  - ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  # nginx is already running (started by the package postinst) with the stock
  # config, so `enable --now` would be a no-op: restart to load the new site.
  - systemctl enable nginx
  - nginx -t && systemctl restart nginx
  # Proxy for interactive shells (curl, wget, ...). Appended, never overwritten:
  # /etc/environment already holds PATH and clobbering it breaks login sessions.
  # 169.254.169.254 MUST bypass the proxy or the Azure IMDS / waagent breaks.
  - |
    cat >> /etc/environment <<'ENVEOF'
    http_proxy="http://${proxy_ip}:${proxy_port}"
    https_proxy="http://${proxy_ip}:${proxy_port}"
    HTTP_PROXY="http://${proxy_ip}:${proxy_port}"
    HTTPS_PROXY="http://${proxy_ip}:${proxy_port}"
    no_proxy="localhost,127.0.0.1,::1,169.254.169.254,${vnet_cidr},.internal.cloudapp.net"
    NO_PROXY="localhost,127.0.0.1,::1,169.254.169.254,${vnet_cidr},.internal.cloudapp.net"
    ENVEOF
  # --- Point this VM at the lab NTP server ------------------------------------
  # The Azure image syncs chrony to the host clock via "refclock PHC
  # /dev/ptp_hyperv", which is stratum 0 and would always beat a stratum-1
  # network server - so the lab NTP server would be configured but never
  # actually selected. Comment the refclock out so this VM really uses it.
  # To go back to Azure host time: un-comment that line and restart chrony.
  - sed -i 's|^refclock PHC|#refclock PHC|' /etc/chrony/chrony.conf
  - systemctl restart chrony
  # --- Switch DNS to the lab resolver (LAST: see the staging note above) -------
  - install -o root -g root -m 0600 /root/99-lab-dns.yaml /etc/netplan/99-lab-dns.yaml
  # netplan generate validates without applying - the closest thing to a
  # named-checkconf for netplan. Bad YAML fails here instead of cutting the link.
  - netplan generate
  - netplan apply
  - |
    sleep 3
    echo "resolver now: $(resolvectl status 2>/dev/null | grep -m1 'Current DNS Server')"
    echo "ntp source:   $(chronyc -n sources 2>/dev/null | tail -1)"
