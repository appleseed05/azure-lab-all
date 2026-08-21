# Troubleshooting Guide

Commands to inspect traffic and validate configuration on each of the three main
categories of components: the **VyOS router**, the **F5XC Customer Edges**, and the
**internal Ubuntu VMs** (`vm-int`, `vm-ext`, `vm-jmp`).

## Methodology

Work outward from the failing point:
1. **NAT on VyOS** — is the DNAT/SNAT rule actually matching and translating?
2. **Azure UDR / ILB** — is the `192.168.200.0/24` route pointing at a **healthy**
   backend behind the `lbce` ILB (probe TCP/65500)?
3. **BGP** VyOS ⇄ CE — is the session `Established`? Is the `/32` VIP actually
   received (import filter `FROM-XC`)?
4. **F5XC site/tunnel health** — is each CE `Online` in the console?
5. **Origin/application** — is NGINX on `vm-int` actually responding?

---

## 1. VyOS Router (`<prefix>-vm-rtr`)

SSH via the Jumphost, or directly if your IP is in `allowed_pips` and port 22 is
DNAT'd (`ssh vyos@<pip-rtr>`, since rule 103 forwards 22 → Jumphost — **note**:
port 22 on the public IP goes to the Jumphost, not the router itself; to reach
the router's own SSH you'd need a different port or use the Jumphost as a
stepping stone).

### Interfaces

```
show interfaces
show interfaces ethernet eth0    # dmz/WAN, holds pip-rtr
show interfaces ethernet eth1    # ext/LAN, 10.1.10.254, BGP peering interface
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

### BGP

```
show ip bgp summary
show ip bgp neighbors 10.1.10.215        # CE01 SLO
show ip bgp neighbors 10.1.10.216        # CE02 SLO
show ip bgp neighbors 10.1.10.215 received-routes
show ip bgp                              # should show 192.168.200.5/32 (or similar) via one or both CEs
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

Reset a session after a config change:
```
clear ip bgp 10.1.10.215
```

### Live traffic capture (`monitor traffic`)

```
monitor traffic interface eth1 filter "port 179"                  # BGP handshake to CEs
monitor traffic interface eth1 filter "host 10.1.10.215 or host 10.1.10.216"
monitor traffic interface eth0 filter "port 80 or port 443"       # inbound app traffic pre-DNAT
monitor traffic interface eth1 filter "host 10.1.10.250"          # traffic toward the ILB
monitor traffic interface eth0 detail
```

Save to a file for Wireshark analysis:
```
monitor traffic interface eth0 filter "port 3389" save /tmp/rdp-capture.pcap
```
Then: `scp vyos@<pip-rtr>:/tmp/rdp-capture.pcap .`

### Logs

```
show log
show log tail 100
```

---

## 2. F5XC Customer Edges (CE01 `<prefix>-vm-ce01`, CE02 `<prefix>-vm-ce02`)

### A. F5 Distributed Cloud Console (check first)

Official guide: https://docs.cloud.f5.com/docs-v2/multi-cloud-network-connect/troubleshooting/troubleshoot-ce-site

Check, **for each site** (`<prefix>-site-01` and `<prefix>-site-02`, namespace
`system`):
- **Site health / status** — both should show `Online`
- **Tunnel status** to the Regional Edge — SSL site-to-site tunnel (`tunnel_type
  = SITE_TO_SITE_TUNNEL_SSL`) should be up
- **BGP peer status** on each site — should show the peer `10.1.10.254` (AS `65001`)
  as `Established`, with the `192.168.200.5/32` route advertised
- **Virtual Site** (`<prefix>-vsite`, namespace `shared`) — confirm both sites are
  members (label selector `<prefix>-vsite-label-key` = `<prefix>-vsite-label-value`)
- **HTTP Load Balancer** (`<prefix>-lb-nginx`) — check origin pool health for
  `10.1.20.5:80`

### B. CLI on the CE

```
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
```

### C. Packet capture on the CE

From the debug shell — `slo` = outside (in `sub-ext`), `sli` = inside (in `sub-int`):
```
tcpdump -i slo -nn port 179                  # BGP to VyOS
tcpdump -i slo -nn host 10.1.10.254           # all traffic to/from the router
tcpdump -i sli -nn host 10.1.20.5             # traffic to the NGINX origin
tcpdump -i slo -nn port 65500                 # confirm the Azure ILB health probe is landing (must respond for the CE to be "healthy")
tcpdump -i slo -w /tmp/slo-capture.pcap
```

> **Azure ILB probe check**: if a CE is being marked unhealthy by the `lbce`
> load balancer (and thus removed from the `192.168.200.0/24` next-hop), verify
> something on the CE is actually listening/responding on TCP `65500` — this is
> the exact probe port configured in `azurerm_lb_probe.tf_azure_lbce_probe`.

### D. Connectivity checks

```
ping 10.1.10.254          # slo <-> VyOS
ping 10.1.20.5             # sli <-> vm-int
curl -v http://10.1.20.5/  # confirm origin reachability from the CE directly
```

---

## 3. Internal Ubuntu VMs (`vm-int`, `vm-ext`, `vm-jmp`)

Access via Jumphost (`vm-jmp` has network access to all others).

### Interfaces & Routing

```
ip a
ip route
ip route get 8.8.8.8
```
Default route should point to `10.1.10.254` (via `route-int`/`route-ext`/`route-adm`
depending on which VM).

### Connectivity

```
ping 10.1.10.254                 # reachability to VyOS
curl -v https://ifconfig.me       # confirms outbound SNAT works, shows pip-rtr as seen externally
traceroute 8.8.8.8
```

### On `vm-int` specifically — validate the demo app origin

```
sudo systemctl status nginx
curl -v http://localhost/
sudo tail -f /var/log/nginx/access.log
```
Expected response body includes `$server_addr` (`10.1.20.5`), `$remote_addr`
(should be a CE SLI IP: `10.1.20.215` or `.216`, since the CE proxies the request),
and `X-Forwarded-For` (the real original client IP) — great for demonstrating the
full path live to a customer: **client public IP → CE's own IP as seen by NGINX →
`X-Forwarded-For` preserving the real client**.

### Packet capture

```
sudo tcpdump -i eth0 -nn port 80
sudo tcpdump -i eth0 -nn host 10.1.10.215 or host 10.1.10.216   # traffic from either CE
sudo tcpdump -i eth0 -w /tmp/vm-int-capture.pcap
```

### End-to-end validation sequence (recommended demo script)

1. On VyOS: `show nat destination translations` — confirm a live translation
   when you hit the public IP
2. On VyOS: `show ip bgp` — confirm `192.168.200.5/32` learned from CE01/CE02
3. In F5XC console: confirm both sites `Online`, tunnel up, BGP peer `Established`
4. On the active CE: `tcpdump -i sli host 10.1.20.5` while sending a request
5. On `vm-int`: `tail -f /var/log/nginx/access.log` while sending a request,
   and show the returned page's `X-Forwarded-For` matching the real client IP

---

## Related Documentation

- [⬅ Back to Documentation Index](./README.md)
- [Architecture](./10-architecture.md) — reference for IPs, ASNs, and traffic flows used throughout this guide
- [Prerequisites](./20-prerequisites.md) — if something is wrong from the start (auth, tfvars, quotas)
