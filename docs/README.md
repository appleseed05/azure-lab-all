# Azure Lab – Documentation

This folder documents the Terraform project in [`../terraform`](../terraform),
which reproduces a small **on-premises network inside Azure**, so it can be used
for hands-on practice and customer demos of F5 Distributed Cloud (F5XC)
Multi-Cloud Network Connect.

Components deployed:

| Component | Role |
|---|---|
| **VyOS 1.5 router** (`vm-rtr`) | Internet edge: source NAT (outbound) + destination NAT (inbound) + eBGP peering + **egress firewall** + remote syslog |
| **Two F5XC Customer Edge nodes** (`vm-ce01`, `vm-ce02`) | Each its own Secure Mesh Site v2, grouped into one Virtual Site. Register **through the lab's HTTP proxy** and use the lab's DNS/NTP |
| **Services Ubuntu VM** (`vm-svc`) | The lab's shared services: **Tinyproxy** (HTTP proxy), **BIND9** (internal DNS zone), **chrony** (NTP). The only host allowed direct Internet access |
| **Observability Ubuntu VM** (`vm-obs`) | **Loki + Grafana + Alloy** — central syslog collection and a provisioned "Lab Logs" dashboard |
| **Application Ubuntu VM** (`vm-app`) | Runs NGINX, simulates an on-prem application server, ships access logs to Loki |
| **Ubuntu Jumphost** (`vm-jmp`) | Desktop (XFCE + xrdp + Firefox) used as the operator's admin workstation, pre-loaded with the lab SSH key |
| **Azure Standard Internal Load Balancer** (`lbce`) | HA-ports load balancer in front of both CEs' SLO interfaces (Azure-specific workaround, not needed on real on-prem hardware — see [10-architecture.md](./10-architecture.md#why-the-azure-internal-load-balancer-ilb-is-required)) |

Two design choices shape most of what follows:

- **No VM has a public IP and no VM may reach the Internet directly.** Exactly
  one host (`vm-svc`) is exempted on the router's firewall; everything else —
  including the F5XC CEs — must go through the proxy. Attempts to bypass it are
  dropped *and logged*.
- **Everything is logged centrally.** The router's firewall drops and BGP events,
  the proxy's requests, DNS queries and the origin's access logs all land in Loki
  and are visible in one Grafana dashboard.

## Contents

| # | Document | Description |
|---|---|---|
| 1 | [10-architecture.md](./10-architecture.md) | Network diagram, IP addressing, routing, NAT, egress firewall, BGP and F5XC design |
| 2 | [20-prerequisites.md](./20-prerequisites.md) | Everything to prepare (Azure, F5XC, tfvars) before running `terraform apply` |
| 3 | [30-troubleshooting.md](./30-troubleshooting.md) | Commands to inspect traffic/state on every component |
| 4 | [40-shared-services.md](./40-shared-services.md) | Tinyproxy, BIND9, chrony and the egress policy that ties them together |
| 5 | [50-observability.md](./50-observability.md) | Loki, Grafana, Alloy: the log pipeline, label scheme, dashboard and queries |

> 📌 **Naming convention**: files are numbered in steps of 10 (`10-`, `20-`, `30-`...)
> so a new document can be inserted later (e.g. `15-deployment-notes.md`) without
> renaming existing files.

## Quick Start

1. Review [20-prerequisites.md](./20-prerequisites.md) and complete the checklist
2. `cd terraform && terraform init && terraform apply`
3. `terraform output` → note `Azure_Public_IP_Router_VM`
4. Open the generated `<prefix>-vm-jmp.rdp` file, or SSH via the same public IP on port 22 (both are DNAT'd to the Jumphost, see [10-architecture.md](./10-architecture.md))
5. Give the lab 10–15 minutes to finish provisioning — every VM waits on the router, then on the proxy
6. From the Jumphost, reach every other VM (all in the same VNet, by IP or by `<prefix>-vm-*.f5demo.lan` name)
7. Open **Grafana** at `http://10.1.10.31:3000` (`admin` / `admin`) and leave the *Lab Logs* dashboard open
8. Test the demo app: `http://<Azure_Public_IP_Router_VM>/` from outside, and `http://<internal-fqdn>/` from the Jumphost — the NGINX page echoes the request path so you can show the traffic flow live
9. Show the egress policy: `curl --noproxy '*' https://ifconfig.me` from `vm-app` fails and appears instantly in the Grafana "Firewall drops" panels; the same request through the proxy succeeds
10. Something not working? → [30-troubleshooting.md](./30-troubleshooting.md)
