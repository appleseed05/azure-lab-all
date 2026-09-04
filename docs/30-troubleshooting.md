# Troubleshooting Guide

Commands to inspect traffic and validate configuration on each category of
component: the **VyOS router**, the **F5XC Customer Edges**, the **Linux VMs**,
the **shared services** (proxy / DNS / NTP on `vm-svc`) and the **observability
stack** (`vm-obs`).

## Methodology

Work outward from the failing point:

1. **Cloud-init** — did the VM even finish provisioning?
   `cloud-init status --long`, `sudo tail -100 /var/log/cloud-init-output.log`
2. **Shared services** — Tinyproxy, BIND and chrony on `vm-svc` are the
   foundation. Nothing else installs, resolves or registers without them.
3. **Egress firewall on VyOS** — is the traffic being dropped by rule 90 because
   the host is not using the proxy? Look at Grafana's "Firewall drops" panels.
4. **NAT on VyOS** — is the DNAT/SNAT rule actually matching and translating?
5. **Azure UDR / ILB** — is the `192.168.200.0/24` route pointing at a **healthy**
   backend behind the `lbce` ILB (probe TCP/65500)?
6. **BGP** VyOS ⇄ CE — is the session `Established`? Is the `/32` VIP actually
   received (import filter `FROM-XC`)?
7. **F5XC site/tunnel health** — is each CE `Online` in the console?
8. **Origin/application** — is NGINX on `vm-app` actually responding?

> **Start in Grafana.** `http://10.1.10.31:3000` (admin/admin) from the Jumphost
> shows the router's firewall drops, NGINX access logs, Tinyproxy CONNECTs, BIND
> queries and BGP adjacency changes in one place. It will often tell you which of
> the steps above is broken before you SSH anywhere.

---

## 0. Quick triage from the Jumphost

```bash
# Are the services that everything depends on alive?
nc -vz 10.1.10.5 8888              # Tinyproxy
dig @10.1.10.5 mylab-vm-app.f5demo.lan +short
chronyc -n sources                 # 10.1.10.5 should be the selected source (^*)
curl -sS -o /dev/null -w '%{http_code}\n' https://ifconfig.me   # via proxy from /etc/environment

# Is the observability stack up?
curl -sS -o /dev/null -w '%{http_code}\n' http://10.1.10.31:3000/login

# Is the app reachable, by VIP and by name?
curl -sS http://192.168.200.5/
curl -sS http://mylab.f5demo.lan/
```

---

## 1. VyOS Router (`<prefix>-vm-rtr`)

Reach it from the Jumphost: `ssh lab@10.1.10.254` (the Terraform-generated key is
already installed there). Note that port 22 on the **public** IP is DNAT'd to the
Jumphost, not to the router — the router has no public SSH of its own.

### Interfaces and routing

```
show interfaces
show interfaces ethernet eth0    # dmz/WAN, holds pip-rtr
show interfaces ethernet eth1    # ext/LAN, 10.1.10.254, BGP peering interface
show ip route
show ip route 192.168.200.5      # should be BGP, via .215 and/or .216
show protocols static route      # the 10.1.0.0/16 -> 10.1.10.1 intra-VNet route
```

### NAT

```
show nat source rules
show nat source statistics
show nat destination rules
show nat destination translations
```

If inbound HTTP/HTTPS to the demo app fails, confirm rule 100/101 exists and
`translation address` = `192.168.200.5`. If RDP/SSH to the Jumphost fails, check
rules 102/103 → `10.1.1.5`.

### Egress firewall

This is the newest source of "it used to work" confusion: a VM that is not
configured to use the proxy will simply have its traffic dropped here.

```
show firewall ipv4 forward filter
show firewall ipv4 forward filter rule 20      # the allow-list rule(s)
show firewall ipv4 forward filter rule 90      # the drop rule
show firewall statistics
show log firewall
monitor log
```

Expected: rule 10 (established/related, no log), rule 20 (accept, source
`10.1.10.5`, logged), rule 90 (drop, source `10.1.0.0/16` out `eth0`, logged).

Dropped packets are logged with `FWD-filter-90-D`. To find them centrally, in
Grafana: `{app="kernel"} |= "FWD-filter-90-D"`.

**To temporarily open egress for a host while debugging** (lost on reboot unless
saved — and see the note below about permanent changes):

```
configure
set firewall ipv4 forward filter rule 21 action 'accept'
set firewall ipv4 forward filter rule 21 outbound-interface name 'eth0'
set firewall ipv4 forward filter rule 21 source address '10.1.20.5'
commit
```

or disable the drop entirely for a moment:

```
configure
set firewall ipv4 forward filter rule 90 disable
commit
```

> **Permanent changes belong in Terraform**, in `locals.router_egress_allowed`
> (`main-azvm-vyos.tf`). But note the router bootstraps **once**, guarded by
> `/config/.bootstrapped` — re-running `terraform apply` will not re-run the
> script on an existing router. Recreate the VM (`terraform taint`) or make the
> change by hand.

> **"Set failed" on every command?** That is the known post-bootstrap state — the
> config session used by the bootstrap script leaves the config subsystem unable
> to accept changes until the next boot. The script reboots once, immediately
> after bootstrapping, exactly to clear it. If you land in that state anyway,
> reboot the router.

### BGP

```
show ip bgp summary
show ip bgp neighbors 10.1.10.215        # CE01 SLO
show ip bgp neighbors 10.1.10.216        # CE02 SLO
show ip bgp neighbors 10.1.10.215 received-routes   # pre-filter (soft-reconfiguration inbound)
show ip bgp neighbors 10.1.10.215 routes            # post-filter
show ip bgp                              # should show 192.168.200.5/32 via one or both CEs
show policy route-map
show policy prefix-list XC-VIPS
```

Expected: both neighbors `Established`, remote AS `65100` on both, local AS
`65001`. You should see the `/32` route for `192.168.200.5` learned from one or
both CEs (thanks to `maximum-paths ebgp 4` + `multipath-relax`, both can appear
active simultaneously).

If a neighbor is stuck in `Active`/`Connect`:
- Check the CE is fully registered and its BGP config (`main-f5xc-bgp.tf`) is
  applied — a CE not yet registered won't have BGP up
- Confirm NSG `nsg-dmz`/relevant NSGs allow TCP/179 between `10.1.10.254` and
  `.215`/`.216` (same subnet, so default Azure intra-VNet rules normally allow it
  unless overridden)
- Verify no route-map typo: `show policy route-map`, `show policy prefix-list XC-VIPS`

If routes are received but not installed, the import filter is the suspect:
compare `received-routes` (everything the CE sent) with `routes` (what survived
`FROM-XC`). Anything outside `192.168.200.0/24 le 32` is dropped by design.

Reset a session after a config change:
```
clear ip bgp 10.1.10.215
```

### Syslog / FRR logging

```
show configuration commands | match syslog
ls -l /tmp/vyos.frr.debug                     # must exist for BGP messages to be logged
vtysh -c 'show logging'
monitor log
```

If BGP adjacency changes never appear in Grafana while firewall drops do, the
`/tmp/vyos.frr.debug` file is missing (it is recreated on every boot by the
bootup script — `/tmp` is wiped on reboot). Recreate it:

```bash
sudo touch /tmp/vyos.frr.debug
sudo vtysh -c 'configure terminal' -c 'log syslog informational' -c 'end'
```

Confirm the collector is actually receiving:

```
monitor traffic interface eth1 filter "host 10.1.10.31 and port 514"
```

### Live traffic capture (`monitor traffic`)

```
monitor traffic interface eth1 filter "port 179"                  # BGP handshake to CEs
monitor traffic interface eth1 filter "host 10.1.10.215 or host 10.1.10.216"
monitor traffic interface eth0 filter "port 80 or port 443"       # inbound app traffic pre-DNAT
monitor traffic interface eth1 filter "host 10.1.10.250"          # traffic toward the ILB
monitor traffic interface eth0 filter "host 10.1.10.5"            # the proxy's egress
monitor traffic interface eth0 detail
```

Save to a file for Wireshark analysis:
```
monitor traffic interface eth0 filter "port 3389" save /tmp/rdp-capture.pcap
```
Then: `scp lab@10.1.10.254:/tmp/rdp-capture.pcap .`

### Logs

```
show log
show log tail 100
```

---

## 2. Shared services — `vm-svc` (`10.1.10.5`)

Full reference: [40-shared-services.md](./40-shared-services.md).
**Check these before anything else** — the CEs, the Jumphost, the application VM and
the observability VM all depend on this host.

### Tinyproxy

```bash
systemctl status tinyproxy
ss -lntp | grep 8888
sudo journalctl -u tinyproxy -n 50 --no-pager
grep -vE '^\s*(#|$)' /etc/tinyproxy/tinyproxy.conf
```

Test from another VM:
```bash
curl -x http://10.1.10.5:8888 -sSv https://ifconfig.me 2>&1 | tail -20
curl -x http://10.1.10.5:8888 -sS -o /dev/null -w '%{http_code}\n' http://archive.ubuntu.com/
```

In Grafana: `{app="tinyproxy"}` — every request and CONNECT is logged there
(Tinyproxy uses `Syslog On`, so there is no local log file by design).

Common causes of failure:
- The client is not configured for the proxy at all → its traffic hits VyOS rule
  90 and is dropped. Check `/etc/environment`, `/etc/apt/apt.conf.d/00-lab-proxy`,
  `snap get system proxy`, Firefox policy.
- The destination is inside the VNet or the VIP range → it must be in `no_proxy`;
  Tinyproxy cannot reach those.
- `Allow` list: only `10.1.0.0/16` and loopback are permitted.

### BIND9 (DNS)

```bash
systemctl status named
sudo journalctl -u named -n 50 --no-pager
named-checkconf
named-checkzone f5demo.lan /etc/bind/db.f5demo.lan
sudo rndc status
```

Query tests (from anywhere in the VNet):
```bash
dig @10.1.10.5 mylab-vm-app.f5demo.lan +short      # internal record
dig @10.1.10.5 mylab.f5demo.lan +short             # -> the XC VIP, if configured
dig @10.1.10.5 www.iana.org +short                 # recursion + DNSSEC
dig @10.1.10.5 www.iana.org +dnssec | grep -i flags
dig @10.1.10.5 somehost.internal.cloudapp.net      # forwarded to 168.63.129.16
```

**SERVFAIL on public signed zones?** Check the IPv4-only switch:
```bash
grep OPTIONS /etc/default/named        # expect: OPTIONS="-u bind -4"
```
If `dig @10.1.10.5 www.iana.org` returns SERVFAIL but `dig +cd` returns NOERROR,
that is exactly this bug (BIND following unreachable AAAA glue until the DNSSEC
chain build gives up). Fix `/etc/default/named`, restart, then clear the cached
failure:
```bash
sudo rndc flush
```

**A record missing for a VM?** The zone is generated from
`local.dns_zone_records` in `main-azvm-services.tf` — add the VM there rather
than editing `/etc/bind/db.f5demo.lan` by hand (a redeploy overwrites it).

On the client side, if names do not resolve:
```bash
resolvectl status                       # Current DNS Server should be 10.1.10.5
cat /etc/netplan/99-lab-dns.yaml
sudo netplan get
```

### chrony (NTP)

On the server (`vm-svc`):
```bash
chronyc tracking
chronyc clients            # lab VMs and CEs should appear here
systemctl status chrony
```

On a client:
```bash
chronyc -n sources         # 10.1.10.5 should be selected, shown as ^*
chronyc sourcestats
grep -n 'refclock PHC' /etc/chrony/chrony.conf     # must be COMMENTED OUT
```

If the lab NTP server is configured but never selected, the Azure PTP refclock is
still active — it is stratum 0 and always wins. Comment it out and restart chrony.

---

## 3. Observability stack — `vm-obs` (`10.1.10.31`)

Full reference: [50-observability.md](./50-observability.md).

### Is everything running?

```bash
systemctl status loki alloy grafana-server
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3100/ready     # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/health
ss -ulnp | grep 514        # Alloy must be bound on udp/514
ss -lntp | grep -E '3000|3100|12345'
```

The cloud-init assertions already check all of the above — read them first:
```bash
sudo grep -E '^(OK|ERROR)' /var/log/cloud-init-output.log
```

### No logs arriving at all

```bash
# Is anything reaching the port?
sudo tcpdump -i eth0 -nn udp port 514
# What does the collector think?
sudo journalctl -u alloy -n 50 --no-pager
alloy validate /etc/alloy/config.alloy
```
Then open the Alloy UI at `http://10.1.10.31:12345` — the component graph shows
`loki.source.syslog` health and live data flow.

If nothing is arriving, check the *sender*:
- VyOS: `show configuration commands | match syslog`
- `vm-svc` / `vm-app`: `cat /etc/rsyslog.d/60-lab-forward.conf`, then
  `systemctl status rsyslog` and `logger -p local0.info "test from $(hostname)"`
- `vm-jmp` and `vm-obs` do **not** forward syslog — that is by design, not a bug

### Loki not starting

```bash
sudo journalctl -u loki -n 50 --no-pager
loki -verify-config -config.file=/etc/loki/config.yml
ls -ld /var/lib/loki /var/lib/loki/chunks
```
`mkdir /var/lib/loki: permission denied` in a crash loop means the state
directories are not owned by the `loki` user — the package creates that user with
primary group `nogroup`, so the fix is `chown -R loki: /var/lib/loki` (trailing
colon), not `chown loki:loki`.

### Grafana: no Loki in the datasource picker

```bash
ls /var/lib/grafana/plugins
sudo journalctl -u grafana-server -n 50 --no-pager | grep -i -E 'plugin|provision'
curl -s -u admin:admin http://127.0.0.1:3000/api/frontend/settings | grep -o '"type":"loki"'
```
`"Could not find plugin definition for data source" datasource_type=loki` means
the Loki plugin never installed — Grafana 13 unbundled it. Check that the proxy
variables really are in `/etc/default/grafana-server`, since Grafana fetches
plugins from grafana.com at startup and this VM has no direct egress.

### Grafana restarting in a loop / `/api/health` returns 000

Almost always the same root cause: no working proxy in Grafana's environment, so
every plugin preinstall attempt blocks ~10 s and the HTTP server never comes up.

```bash
grep -E 'proxy|PREINSTALL' /etc/default/grafana-server
curl -x http://10.1.10.5:8888 -sS -o /dev/null -w '%{http_code}\n' https://grafana.com/
```

### Dashboard missing

```bash
ls -l /var/lib/grafana/dashboards /etc/grafana/provisioning/dashboards
curl -s -u admin:admin 'http://127.0.0.1:3000/api/search?type=dash-db'
```

---

## 4. F5XC Customer Edges (CE01 `<prefix>-vm-ce01`, CE02 `<prefix>-vm-ce02`)

### A. F5 Distributed Cloud Console (check first)

Official guide: https://docs.cloud.f5.com/docs-v2/multi-cloud-network-connect/troubleshooting/troubleshoot-ce-site

Check, **for each site** (`<prefix>-site-01` and `<prefix>-site-02`, namespace
`system`):
- **Site health / status** — both should show `Online`
- **Tunnel status** to the Regional Edge — SSL site-to-site tunnel (`tunnel_type
  = SITE_TO_SITE_TUNNEL_SSL`) should be up. Remember this tunnel runs **through
  Tinyproxy** (`enable_re_tunnel = true`)
- **BGP peer status** on each site — should show the peer `10.1.10.254` (AS `65001`)
  as `Established`, with the `192.168.200.5/32` route advertised
- **Virtual Site** (`<prefix>-vsite`, namespace `shared`) — confirm both sites are
  members (label selector `<prefix>-vsite-label-key` = `<prefix>-vsite-label-value`)
- **HTTP Load Balancer** (`<prefix>-lb-nginx`) — check origin pool health for
  `10.1.20.5:80`

> Note: `logs_streaming_disabled = true` on both sites, so CE logs are **not**
> shipped into the lab's Loki. Use the F5XC console for them.

### B. A CE that never comes online

The CEs depend entirely on `vm-svc`. Before touching the CE, verify from the
Jumphost that all three of these work:

```bash
curl -x http://10.1.10.5:8888 -sS -o /dev/null -w '%{http_code}\n' https://console.ves.volterra.io/
dig @10.1.10.5 <your-tenant>.console.ves.volterra.io +short
chronyc -h 10.1.10.5 tracking
```

Then, on `vm-svc`, watch the CE actually going through the proxy — in Grafana
`{app="tinyproxy"}` filtered on the CE addresses, or live:

```bash
sudo journalctl -u tinyproxy -f | grep -E '10\.1\.10\.(215|216)'
```

A CE that is silent in the Tinyproxy log is not using the proxy at all — check
`custom_proxy` on the Secure Mesh Site in the console. A CE that appears there but
fails is hitting a name-resolution or upstream problem.

Registration also needs a valid site token: `volterra_token` objects
`<prefix>-site-token01` / `02` (namespace `system`, `type = 1`), injected into
`/etc/vpm/user_data` by cloud-init.

### C. CLI on the CE

```bash
ssh cloud-user@<ce-private-ip>     # via Jumphost, e.g. ssh cloud-user@10.1.10.215
```

```
show system status
show interface
show bgp neighbor
show bgp neighbor 10.1.10.254 advertised-routes    # should show 192.168.200.5/32
```

Generate a support bundle:
```
request support
```

Debug shell (drops to the underlying host — use carefully):
```
request debug shell
kubectl get pods -A
kubectl get pods -A -o wide | grep vpm
kubectl logs -n <namespace> <vpm-pod-name>
cat /etc/vpm/user_data          # the site token
```

### D. Packet capture on the CE

From the debug shell — `slo` = outside (in `sub-ext`), `sli` = inside (in `sub-int`):
```bash
tcpdump -i slo -nn port 179                   # BGP to VyOS
tcpdump -i slo -nn host 10.1.10.254           # all traffic to/from the router
tcpdump -i slo -nn host 10.1.10.5             # registration/tunnel via Tinyproxy
tcpdump -i sli -nn host 10.1.20.5             # traffic to the NGINX origin
tcpdump -i slo -nn port 65500                 # confirm the Azure ILB health probe is landing
tcpdump -i slo -w /tmp/slo-capture.pcap
```

> **Azure ILB probe check**: if a CE is being marked unhealthy by the `lbce`
> load balancer (and thus removed from the `192.168.200.0/24` next-hop), verify
> something on the CE is actually listening/responding on TCP `65500` — this is
> the exact probe port configured in `azurerm_lb_probe.tf_azure_lbce_probe`.

### E. Connectivity checks

```bash
ping 10.1.10.254            # slo <-> VyOS
ping 10.1.20.5              # sli <-> vm-app
curl -v http://10.1.20.5/   # confirm origin reachability from the CE directly
```

---

## 5. Linux VMs (`vm-app`, `vm-svc`, `vm-jmp`, `vm-obs`)

Access via the Jumphost, which has the Terraform-generated SSH key and an
`~/.ssh/config` entry covering `10.1.*` and `*.f5demo.lan`, so
`ssh lab@10.1.20.5` or `ssh lab@mylab-vm-obs.f5demo.lan` works with no password
and no host-key prompt.

### Provisioning

```bash
cloud-init status --long
sudo tail -100 /var/log/cloud-init-output.log
sudo grep -E '^(OK|ERROR)' /var/log/cloud-init-output.log
```

The `apt-get update` retry loop prints one line per attempt — up to 60 attempts,
20 s apart. Seeing several failures then `apt-get update OK on attempt N` is
normal, and means the router or proxy simply took a while.

> **Changing cloud-init on a live VM**: `custom_data` is ForceNew in Azure, so a
> template edit recreates the VM — except on the Jumphost, which deliberately
> uses `user_data` (updates in place). Either way the VM must re-run cloud-init
> to apply it:
> ```bash
> terraform apply && ssh <vm> sudo cloud-init clean --logs --reboot
> ```

### Interfaces, routing, name resolution

```bash
ip a
ip route
ip route get 8.8.8.8
resolvectl status | head -20
```
Default route should point to `10.1.10.254` (via `route-int`/`route-ext`/`route-adm`
depending on which VM). `Current DNS Server` should be `10.1.10.5` on `vm-app`,
`vm-jmp` and `vm-obs`.

### Connectivity and the proxy

```bash
ping 10.1.10.254                  # reachability to VyOS
curl -sS https://ifconfig.me      # via proxy (env vars) -> shows pip-rtr
env | grep -i proxy
cat /etc/environment
```

**The direct-egress test** — on every VM except `vm-svc` this *must* fail, and
must show up as a drop in Grafana within seconds:
```bash
curl --noproxy '*' -m 8 https://ifconfig.me ; echo "exit=$?"
```
If it *succeeds* from a VM other than `vm-svc`, the egress firewall is not doing
its job — check VyOS rule 90.

### On `vm-app` specifically — validate the demo app origin

```bash
sudo systemctl status nginx
sudo nginx -t
curl -v http://localhost/
sudo tail -f /var/log/nginx/access.log
```
Expected response body includes `$server_addr` (`10.1.20.5`), `$remote_addr`
(should be a CE SLI IP: `10.1.20.215` or `.216`, since the CE proxies the request),
and `X-Forwarded-For` (the real original client IP) — great for demonstrating the
full path live to a customer: **client public IP → CE's own IP as seen by NGINX →
`X-Forwarded-For` preserving the real client**.

NGINX also ships its access and error logs straight to Alloy
(`access_log syslog:server=10.1.10.31:514,facility=local7,tag=nginx,...`), so the
same requests appear in Grafana under `{app="nginx"}`. The local file is kept for
on-box work.

### On `vm-jmp` specifically

```bash
systemctl status xrdp
cat /etc/firefox/policies/policies.json
snap get system proxy
ls -l ~/.ssh/id_ed25519 ~/.ssh/config
```
Firefox is the Mozilla **snap** on Ubuntu 24.04, so only `/etc/firefox/policies`
takes effect. If the browser cannot reach the Internet, check that the policy is
present and that `snap connect firefox:etc-firefox` succeeded.

### Packet capture

```bash
sudo tcpdump -i eth0 -nn port 80
sudo tcpdump -i eth0 -nn host 10.1.10.215 or host 10.1.10.216   # traffic from either CE
sudo tcpdump -i eth0 -nn port 8888                              # traffic to/from the proxy
sudo tcpdump -i eth0 -nn udp port 514                           # syslog leaving this VM
sudo tcpdump -i eth0 -w /tmp/vm-app-capture.pcap
```

---

## 6. End-to-end validation sequence (recommended demo script)

1. On the Jumphost, open Grafana (`http://10.1.10.31:3000`) and leave the
   **Lab Logs** dashboard on screen
2. On VyOS: `show nat destination translations` — confirm a live translation
   when you hit the public IP
3. On VyOS: `show ip bgp` — confirm `192.168.200.5/32` learned from CE01/CE02
4. In the F5XC console: confirm both sites `Online`, tunnel up, BGP peer `Established`
5. Hit the app from outside (`curl http://<pip-rtr>/`) and from inside by name
   (`curl http://mylab.f5demo.lan/`) — compare the `X-Forwarded-For` and
   `Request received from` lines in the two responses
6. On the active CE: `tcpdump -i sli host 10.1.20.5` while sending a request
7. Watch the same requests land in Grafana under `{app="nginx"}`
8. Finish with the policy demo: run `curl --noproxy '*' https://ifconfig.me` from
   `vm-app`, watch it hang and fail, and show the drop appearing live in the
   "Firewall drops" panels — then run it again *with* the proxy and show it
   succeed, alongside the matching `{app="tinyproxy"}` line

---

## Related Documentation

- [⬅ Back to Documentation Index](./README.md)
- [Architecture](./10-architecture.md) — reference for IPs, ASNs, and traffic flows used throughout this guide
- [Prerequisites](./20-prerequisites.md) — if something is wrong from the start (auth, tfvars, quotas)
- [Shared services](./40-shared-services.md) — how the proxy, DNS and NTP are meant to behave
- [Observability](./50-observability.md) — label scheme and ready-made LogQL queries
