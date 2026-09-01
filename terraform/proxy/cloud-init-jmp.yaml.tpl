#cloud-config
# The jumphost has no public IP and no NAT gateway: its only way out is the
# default route to the VyOS router, which only carries traffic once the router
# has booted AND committed its source-NAT masquerade rule. Cloud-init here can
# easily start before that.
#
# So the built-in `packages:` / `package_update:` module is deliberately NOT
# used: it runs early in the boot and has no retry, so one failed apt-get
# update leaves xrdp uninstalled and the jumphost unreachable on 3389 forever.
# Everything is done from runcmd behind a retry loop instead, the same way
# cloud-init-int.yaml.tpl does it.
package_update: false

write_files:
  - path: /etc/apt/apt.conf.d/00-lab-proxy
    owner: root:root
    permissions: '0644'
    content: |
      // Managed by cloud-init (cloud-init-jmp.yaml.tpl).
      // Sends all apt traffic through the Tinyproxy instance on the external VM.
      Acquire::http::Proxy "http://${proxy_ip}:${proxy_port}";
      Acquire::https::Proxy "http://${proxy_ip}:${proxy_port}";

  # --- SSH private key, so the jumphost can reach the other lab VMs -----------
  # Staged in /root and NOT written straight to /home/${admin_username}/.ssh:
  # cloud-init runs the write_files module BEFORE users_groups (see the module
  # order in /etc/cloud/cloud.cfg), so the "${admin_username}" user does not
  # exist yet at this point and "owner: ${admin_username}" would fail outright.
  # runcmd runs in the final stage, by which time the user is there.
  #
  # encoding b64 keeps the multi-line OpenSSH key on ONE yaml line, so the PEM
  # body needs no indentation juggling inside this block scalar.
  - path: /root/lab-id-ed25519
    owner: root:root
    permissions: '0600'
    encoding: b64
    content: ${base64encode(ssh_private_key)}

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

  # Firefox on Ubuntu 24.04 is the Mozilla *snap*, so the usual
  # /usr/lib/firefox/distribution/policies.json does nothing. The snap declares a
  # system-files plug named "etc-firefox" (auto-connected via Mozilla's snap
  # declaration) which lets the confined browser read /etc/firefox - that is the
  # only policy path that works here. Keys below are from the browser omni.ja
  # schema at modules/policies/ProxyPolicies.sys.mjs.
  #
  # NOTE: policies.json must be STRICT JSON - Firefox parses it with JSON.parse,
  # so a // comment inside the braces below makes it reject the whole file.
  #
  # "Locked": false means Firefox still applies the proxy (Policies.sys.mjs
  # passes PoliciesUtils.setDefaultPref, which writes the pref DEFAULT branch),
  # but it skips both disallowFeature("changeProxySettings") and lockPref(), so
  # the settings stay editable. A manual change lands on the user branch, which
  # overrides the default and survives restarts. Flip to true to grey it out.
  - path: /etc/firefox/policies/policies.json
    owner: root:root
    permissions: '0644'
    content: |
      {
        "policies": {
          "Proxy": {
            "Mode": "manual",
            "HTTPProxy": "${proxy_ip}:${proxy_port}",
            "SSLProxy": "${proxy_ip}:${proxy_port}",
            "UseHTTPProxyForAllProtocols": true,
            "Passthrough": "localhost, 127.0.0.1, ${vnet_cidr}",
            "Locked": false
          }
        }
      }

runcmd:
  # Wait until apt works. apt now goes through the Tinyproxy on the external VM
  # (see /etc/apt/apt.conf.d/00-lab-proxy above), so this loop transparently waits
  # for BOTH the VyOS egress AND tinyproxy to be up (up to 60 x 20s = 20 min).
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
  - DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  # snapd does NOT read /etc/environment, so point it at the proxy explicitly.
  # This MUST happen BEFORE the firefox install below. The firefox deb is a
  # transitional package whose postinst pulls the snap, and the VyOS egress
  # firewall now drops direct Internet access from this VM - so without the
  # proxy set first, the snap fetch fails and the install dies.
  # Verified working: tinyproxy logs CONNECT to api.snapcraft.io.
  - snap set system proxy.http="http://${proxy_ip}:${proxy_port}" || true
  - snap set system proxy.https="http://${proxy_ip}:${proxy_port}" || true
  - systemctl restart snapd || true
  - DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies xrdp firefox mousepad thunar-archive-plugin gnome-keyring ntpdate
  # Defensive: the etc-firefox plug is auto-connected by Mozilla's snap
  # declaration, but connect it explicitly in case that ever changes.
  - snap connect firefox:etc-firefox || true
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
  # --- Install the SSH key for ${admin_username} ------------------------------
  # This is the same keypair Terraform put in every VM's admin_ssh_key, so from
  # here "ssh lab@10.1.20.5" (or any f5demo.lan name) needs no password.
  - install -d -o ${admin_username} -g ${admin_username} -m 0700 /home/${admin_username}/.ssh
  - install -o ${admin_username} -g ${admin_username} -m 0600 /root/lab-id-ed25519 /home/${admin_username}/.ssh/id_ed25519
  - shred -u /root/lab-id-ed25519 2>/dev/null || rm -f /root/lab-id-ed25519
  # Lab-only convenience: these VMs are rebuilt constantly, so their host keys
  # change every deploy. Without this, every hop stops on a host-key prompt or
  # a REMOTE HOST IDENTIFICATION HAS CHANGED error. Scoped to lab addresses and
  # f5demo.lan only - delete this block to get normal host-key checking back.
  - |
    cat > /home/${admin_username}/.ssh/config <<'SSHCFG'
    Host 10.1.* *.${dns_zone}
        IdentityFile ~/.ssh/id_ed25519
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        LogLevel ERROR
    SSHCFG
  - chown ${admin_username}:${admin_username} /home/${admin_username}/.ssh/config
  - chmod 0600 /home/${admin_username}/.ssh/config
  # Configure XFCE as default session for XRDP
  - echo "xfce4-session" > /home/${admin_username}/.xsession
  - chown ${admin_username}:${admin_username} /home/${admin_username}/.xsession
  # Add xrdp to group ssl-cert (certificates access)
  - usermod -aG ssl-cert xrdp
  # Enable xrdp when vm start then reboot to apply updates
  - systemctl enable xrdp
  - reboot
