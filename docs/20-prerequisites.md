# Prerequisites

Complete this checklist **before** running `terraform apply`. Most deployment
failures in this lab come from skipping one of these steps.

## 1. Local Machine / Software

| Requirement | Notes |
|---|---|
| **Git** | To clone the repo |
| **Terraform** | Providers used: `azurerm ~>4.0`, `tls >=4.0.0`, `local >=2.5.0`, `volterra ~>0.12.2`, `cloudinit >=2.3.7` — run `terraform init` to download them |
| **Azure CLI** *(optional but recommended)* | Only required if you plan to authenticate via `az login` instead of a Service Principal |
| **An RDP client** | To reach the Jumphost desktop; a `.rdp` file is generated for you |
| OS | Tested on Ubuntu Linux and Windows 11; should also work on macOS |

## 2. Azure Requirements

- **An Azure subscription**, with its `subscription ID` and `tenant ID` at hand.
- **Authentication** — two options:
  1. **Service Principal** (recommended): create one with `Contributor` role
     (or narrower, if you prefer) on the target subscription, and note its
     `client_id` / `client_secret`. These four values map directly to
     `azure_sub_id`, `azure_tenant_id`, `azure_client_id`, `azure_client_secret`
     in `terraform.tfvars`.
  2. **Interactive login**: run `az login` on the machine that will run
     Terraform (requires Azure CLI installed). In this case you can leave
     `azure_client_id`/`azure_client_secret` unset, but the variables must
     still exist in `terraform.tfvars` (even as empty/placeholder values,
     depending on how your provider block is configured).
- **Your own public IP address** (or your office/VPN egress IP) — needed for
  the `allowed_pips` variable, which restricts inbound NSG rules (SSH/RDP/HTTP/
  HTTPS) to your source IP only. Without this correctly set, you will not be
  able to reach the Jumphost or the demo app at all.
- **VM quota**: confirm your subscription/region has enough vCPU quota for
  **7 VMs**:

  | VM | Variable | Example size | vCPU |
  |---|---|---|---|
  | VyOS router | `azure_vm_size_rtr` | `Standard_D8s_v3` | 8 |
  | F5XC CE01 | `azure_vm_size_xc_ce` | `Standard_D8_v4` | 8 |
  | F5XC CE02 | `azure_vm_size_xc_ce` | `Standard_D8_v4` | 8 |
  | Jumphost | `azure_vm_size_jmp` | `Standard_D2s_v3` | 2 |
  | Services (proxy/DNS/NTP) | `azure_vm_size_linux` | `Standard_B2s` | 2 |
  | Application (NGINX) | `azure_vm_size_linux` | `Standard_B2s` | 2 |
  | **Observability (Loki/Grafana/Alloy)** | `azure_vm_size_linux` | `Standard_B2s` | 2 |

  That is roughly **32 vCPU** with the example sizes — the default quota on a
  fresh subscription is often lower, so check before deploying.

  > `azure_vm_size_srv` also exists in `variables.tf` and must be set, but no
  > VM currently uses it. Leave it at the example value.

- **Marketplace terms**: this project deploys two Marketplace images —
  VyOS (`azurerm_marketplace_agreement` handles this automatically for VyOS)
  and the F5XC CE image (`f5xccebyol`, a BYOL plan). If `terraform apply` fails
  with a "terms not accepted" error on the CE image, accept it manually once
  per subscription, e.g.:
  ```bash
  az vm image terms accept --publisher f5-networks --offer f5xc_customer_edge --plan f5xccebyol
  ```
  *(This step is not automated in the Terraform code for the CE image — only
  for VyOS — so keep it in mind if `apply` fails on the CE VM resource.)*

- **Outbound Internet from the VNet**: the lab has no NAT Gateway. All egress is
  source-NATed by the VyOS router behind its single Public IP, and the router's
  firewall permits direct egress from **one** address only. This matters if your
  subscription has policies that block Public IPs or require forced tunnelling —
  the lab will not provision at all in that case.

## 3. F5 Distributed Cloud (F5XC) Requirements

- **An F5XC tenant** you have admin/API access to.
- **An existing Namespace** in that tenant — the Terraform code *reads* an
  existing namespace (`data "volterra_namespace"`), it does **not** create one.
  Create the namespace in the F5XC Console first, and set its name in
  `f5xc_namespace_name`.
- **API Certificate (P12 file)** — required for CE registration (API tokens
  are not sufficient for this):
  1. Generate the API certificate from the F5XC Console
     (`Administration > Personal Management > Credentials > Add Credentials`,
     type "API Certificate").
  2. Download the `.p12` file and place it **in the `terraform` folder**,
     alongside the `.tf` files (the provider resolves the path as
     `${path.module}/${var.f5xc_api_p12_file}`).
  3. Set `f5xc_api_p12_file` in `terraform.tfvars` to that filename.
  4. Set the **`VES_P12_PASSWORD`** environment variable on the machine
     running Terraform, to the password you chose when generating the
     certificate:
     ```bash
     export VES_P12_PASSWORD="your-p12-password"
     ```
     (On Windows: `$env:VES_P12_PASSWORD = "your-p12-password"` in PowerShell.)
  5. **Do not commit this file** — it's already excluded via `.gitignore`
     (`*.p12`), but double-check before pushing to a public repo.
- **`f5xc_api_url`** — set to `https://<your-tenant-name>.console.ves.volterra.io/api`.
- **`f5xc_tenant_name`** — your tenant's short name.
- **Known Label** — the Virtual Site grouping the two CE sites uses a Known Label
  that **Terraform creates for you** in the `shared` namespace:
  `<prefix>-vsite-label-key` = `<prefix>-vsite-label-value`. There are no
  `f5xc_label_key` / `f5xc_label_value` variables any more; both are derived from
  `prefix`. Make sure a key of that name does not already exist in your tenant,
  or `volterra_known_label_key` will conflict with it — changing `prefix` is the
  simplest fix.
- **Naming constraint (important)**: `prefix` and `f5xc_namespace_name` — and by
  extension every Azure/XC object name derived from `prefix` — **must only use
  lower-case alphanumeric characters and dashes, and must start with an
  alphanumeric character**. Violating this can make the deployment silently
  partially fail: Terraform `apply` may report success, but CE registration will
  fail with an error only visible locally on the CE (not in the F5XC Console).
- **CE registration goes through the lab's own proxy.** Both Secure Mesh Sites
  are configured with `custom_proxy` pointing at Tinyproxy on `vm-svc`, and with
  `custom_dns` / `custom_ntp` pointing at the same VM. Nothing extra to prepare —
  but it does mean a CE cannot register until `vm-svc` has finished provisioning.
  See [40-shared-services.md](./40-shared-services.md).

## 4. `terraform.tfvars` — Required Edits

1. Copy the example file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
2. **These variables have no default and must be set**:

   | Variable | Description |
   |---|---|
   | `prefix` | Prefixes every object name — lower-case/numbers/dash only |
   | `azure_sub_id` | Azure subscription ID |
   | `azure_tenant_id` | Azure tenant ID |
   | `azure_client_id` | Service Principal client ID |
   | `azure_client_secret` | Service Principal client secret |
   | `azure_adminpassword` | Admin password for all Azure VMs — recommended to set via environment variable rather than hardcoding in the file |
   | `allowed_pips` | List of your public IP(s), e.g. `["203.0.113.10/32"]` |
   | `azure_tag_owner` / `azure_tag_env` | Azure tags applied to the resources |
   | `f5xc_api_p12_file` | Filename of the P12 certificate (see above) |
   | `f5xc_api_url` | `https://<tenant>.console.ves.volterra.io/api` |
   | `f5xc_tenant_name` | Your F5XC tenant short name |
   | `f5xc_namespace_name` | Your existing F5XC namespace |

3. **Other variables already have defaults in the example file but review them
   before deploying.**

   **Network and BGP**
   - `azure_cidr_vnet` and the four subnet CIDRs (`azure_cidr_sub_dmz/ext/int/adm`)
   - All static IPs (`azure_nic_*_ip_addr`), including `azure_nic_obs_ip_addr`
     for the observability VM
   - `azure_lbce_ip` (`10.1.10.250`) — the Azure ILB frontend
   - `f5xc_bgp_asn` (`65100`), `router_bgp_asn` (`65001`), `f5xc_vip_cidr`
     (`192.168.200.0/24`), `router_bgp_maximum_paths_ebgp` (`4`)

   **Application**
   - `f5xc_lb_nginx_vip` (`192.168.200.5`)
   - `f5xc_lb_nginx_fqdn` — a **list** of domains for the HTTP LB. Give it one
     external name and one name inside your internal zone, e.g.
     `["mylab.mydomain.com", "mylab.f5demo.lan"]`. Whichever entry ends in
     `.<dns_internal_zone>` automatically gets a BIND A record pointing at the
     VIP. Exactly **zero or one** entry may end in that zone — two will make
     `terraform plan` fail on the `one()` call in `main-azvm-services.tf`.

   **Shared services** (see [40-shared-services.md](./40-shared-services.md))
   - `tinyproxy_port` (`8888`) — the lab-wide HTTP proxy port
   - `dns_internal_zone` (`f5demo.lan`) — the authoritative internal zone

   **Observability** (see [50-observability.md](./50-observability.md))
   - `loki_retention_period` (`168h`) — Go duration, how long logs are kept

   **Credentials and images**
   - `azure_admin_username` / `azure_ssh_username` — **must be identical**
     (Azure VM requirement noted in the README's Warning section)
   - VM sizes (`azure_vm_size_rtr`, `azure_vm_size_xc_ce`, `azure_vm_size_linux`,
     `azure_vm_size_jmp`, `azure_vm_size_srv`)
   - Marketplace image publisher/offer/sku/version for Ubuntu, VyOS and F5XC CE
     — **do not change offer/SKU for VyOS**, per the example file's comment:
     *"Please DON'T change the offer and SKU, you will still deploy versions 1.5.x."*

### Values that are not variables

Every address and CIDR in the deployment is now derived from `terraform.tfvars` —
including the UDR for the XC VIP range, the router's BGP router-id and its SNAT
source, which used to be written literally. Changing a CIDR or an IP in the tfvars
propagates everywhere it is used.

One literal remains, correctly:

| Value | Where | Why it is not a variable |
|---|---|---|
| `168.63.129.16` | `cloud-init-svc.yaml.tpl` — forwarder for `internal.cloudapp.net` | Azure's platform resolver, the same address in every region |

> **Changing router settings after deployment**: the VyOS router bootstraps
> **once**, guarded by `/config/.bootstrapped`. Editing a variable that feeds
> `cloud-init-rtr.yaml.tpl` changes `custom_data`, which is ForceNew — so
> `terraform apply` will propose **recreating the router VM**. That is the
> intended way to apply the change; just be aware it is a replacement, not an
> in-place update.

## 5. Timing Expectations

Plan for this rough timeline once you run `terraform apply`:

| Step | Approximate duration |
|---|---|
| Terraform deployment itself | ~3–5 minutes |
| `vm-svc` ready (Tinyproxy + BIND + chrony) | ~5 minutes after its VM boots — **everything else waits on this** |
| Jumphost fully ready/reachable | 10–15 minutes (be patient before troubleshooting RDP/SSH issues) |
| Observability VM ready (Grafana reachable on :3000) | 10–15 minutes — it installs Grafana, Loki and Alloy through the proxy |
| F5XC CE installation + registration (both sites) | ~1 hour, up to 1.5 hours |

The Linux VMs provision behind a retry loop that waits **up to 20 minutes** for
egress through the router and the proxy, so "slow" is normal and self-healing;
"failed" is not. To watch progress on any of them:

```bash
sudo tail -f /var/log/cloud-init-output.log
cloud-init status --long
```

If a CE hasn't registered after 1.5 hours, the two most common causes are a
naming violation (capital letters or special characters somewhere in `prefix`)
and a broken proxy/DNS/NTP on `vm-svc` — the CEs depend on all three.

## 6. Pre-Flight Checklist

- [ ] Git, Terraform installed
- [ ] Azure subscription ID + tenant ID at hand
- [ ] Service Principal created (or ready to `az login`)
- [ ] vCPU quota sufficient for 7 VMs (~32 vCPU with the example sizes)
- [ ] Marketplace terms accepted for F5XC CE image (if needed)
- [ ] F5XC tenant + existing namespace confirmed
- [ ] F5XC API P12 certificate generated, placed in `terraform/`, password set as `VES_P12_PASSWORD`
- [ ] No existing Known Label key named `<prefix>-vsite-label-key` in the tenant
- [ ] `terraform.tfvars` created from the example and all required variables edited
- [ ] `prefix` and namespace use only lower-case alphanumeric + dash
- [ ] At most one entry of `f5xc_lb_nginx_fqdn` ends in `dns_internal_zone`
- [ ] Your public IP correctly set in `allowed_pips`
- [ ] `terraform init` run successfully

Once all boxes are checked, proceed to `terraform plan` then `terraform apply`
as described in the main [README.md](../README.md).

---

## Related Documentation

- [⬅ Back to Documentation Index](./README.md)
- [Architecture](./10-architecture.md) — network diagram and IP addressing
- [Shared services](./40-shared-services.md) — proxy, DNS, NTP and egress policy
- [Observability](./50-observability.md) — Loki, Grafana, Alloy
- [Troubleshooting](./30-troubleshooting.md) — once your lab is deployed
