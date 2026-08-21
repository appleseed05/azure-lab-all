# Azure Lab – Documentation

This folder documents the `azure-lab-all` Terraform project, which reproduces a small
**on-premises network inside Azure**, so it can be used for hands-on practice and
customer demos of F5 Distributed Cloud (F5XC) Multi-Cloud Network Connect.

Components deployed:
- **VyOS 1.5 router** — internet edge: source NAT (outbound) + destination NAT (inbound) + eBGP peering
- **Two F5XC Customer Edge (CE) nodes** — each its own Secure Mesh Site v2, grouped into one Virtual Site
- **Internal Ubuntu VM** — runs NGINX, simulates an on-prem application server
- **External Ubuntu VM** — simulates a server directly reachable in the "external"/perimeter zone
- **Ubuntu Jumphost** — desktop (XFCE + xrdp) used as the operator's admin workstation
- **Azure Standard Internal Load Balancer** — HA-ports load balancer in front of both CEs' SLO interfaces (Azure-specific workaround, not needed on real on-prem hardware — see [10-architecture.md](./10-architecture.md#why-the-azure-internal-load-balancer-ilb-is-required))

## Contents

| # | Document | Description |
|---|---|---|
| 1 | [10-architecture.md](./10-architecture.md) | Network diagram, IP addressing, routing, NAT and BGP design |
| 2 | [20-prerequisites.md](./20-prerequisites.md) | Everything to prepare (Azure, F5XC, tfvars) before running `terraform apply` |
| 3 | [30-troubleshooting.md](./30-troubleshooting.md) | Commands to inspect traffic/state on the router, CEs, and internal VMs |

> 📌 **Naming convention**: files are numbered in steps of 10 (`10-`, `20-`, `30-`...)
> so a new document can be inserted later (e.g. `15-deployment-notes.md`) without
> renaming existing files.

## Quick Start

1. Review [20-prerequisites.md](./20-prerequisites.md) and complete the checklist
2. `cd terraform && terraform init && terraform apply`
3. `terraform output` → note `Azure_Public_IP_Router_VM`
4. Open the generated `<prefix>-vm-jmp.rdp` file, or SSH via the same public IP on port 22 (both are DNAT'd to the Jumphost, see [10-architecture.md](./10-architecture.md))
5. From the Jumphost, reach every other VM (all in the same VNet)
6. Test the demo app: `http://<Azure_Public_IP_Router_VM>/` — the NGINX page echoes the request path so you can show the traffic flow live
7. Something not working? → [30-troubleshooting.md](./30-troubleshooting.md)
