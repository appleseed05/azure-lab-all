# Prerequisites

Complete this checklist **before** running `terraform apply`. Most deployment
failures in this lab come from skipping one of these steps.

## 1. Local Machine / Software

| Requirement | Notes |
|---|---|
| **Git** | To clone the repo |
| **Terraform** | Providers used: `azurerm ~>4.0`, `tls >=4.0.0`, `local >=2.5.0`, `volterra ~>0.11.46`, `cloudinit >=2.3.7` — run `terraform init` to download them |
| **Azure CLI** *(optional but recommended)* | Only required if you plan to authenticate via `az login` instead of a Service Principal |
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
  6 VMs (VyOS router, 2× F5XC CE, internal VM, external VM, Jumphost) in the
  sizes defined by `azure_vm_size_rtr`, `azure_vm_size_xc_ce`,
  `azure_vm_size_linux`, `azure_vm_size_jmp`.
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
- **Label key uniqueness**: the Virtual Site grouping the two CE sites uses a
  Known Label (`f5xc_label_key` / `f5xc_label_value`). **Check that this label
  key does not already exist** in your tenant before deploying — if it does,
  the `volterra_known_label_key` resource may conflict with existing tenant
  configuration.
- **Naming constraint (important)**: `prefix`, `f5xc_namespace_name`,
  `f5xc_label_key`, `f5xc_label_value` — and by extension every Azure/XC
  object name derived from `prefix` — **must only use lower-case alphanumeric
  characters and dashes, and must start with an alphanumeric character**.
  Violating this can make the deployment silently partially fail: Terraform
  `apply` may report success, but CE registration will fail with an error only
  visible locally on the CE (not in the F5XC Console).

## 4. `terraform.tfvars` — Required Edits

1. Copy the example file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
2. **These variables have no default and must be set** (per `README.md`):

   | Variable | Description |
   |---|---|
   | `prefix` | Prefixes every object name — lower-case/numbers/dash only |
   | `azure_sub_id` | Azure subscription ID |
   | `azure_tenant_id` | Azure tenant ID |
   | `azure_client_id` | Service Principal client ID |
   | `azure_client_secret` | Service Principal client secret |
   | `azure_adminpassword` | Admin password for all Azure VMs — recommended to set via environment variable rather than hardcoding in the file |
   | `allowed_pips` | List of your public IP(s), e.g. `["203.0.113.10/32"]` |
   | `f5xc_api_p12_file` | Filename of the P12 certificate (see above) |
   | `f5xc_namespace_name` | Your existing F5XC namespace |
   | `f5xc_label_key` / `f5xc_label_value` | Virtual Site grouping label |

3. **Other variables already have defaults in the example file but review them
   before deploying**, notably:
   - `f5xc_bgp_asn` (`65100`), `router_bgp_asn` (`65001`), `f5xc_vip_cidr`
     (`192.168.200.0/24`), `router_bgp_maximum_paths_ebgp` (`4`)
   - `f5xc_lb_nginx_fqdn`, `f5xc_lb_nginx_vip` (`192.168.200.5`)
   - `azure_cidr_vnet` and the four subnet CIDRs (`azure_cidr_sub_dmz/ext/int/adm`)
   - All static IPs (`azure_nic_*_ip_addr`)
   - `azure_admin_username` / `azure_ssh_username` — **must be identical**
     (Azure VM requirement noted in the README's Warning section)
   - VM sizes (`azure_vm_size_rtr`, `azure_vm_size_xc_ce`, `azure_vm_size_linux`,
     `azure_vm_size_jmp`)
   - Marketplace image publisher/offer/sku/version for Ubuntu, VyOS and F5XC CE
     — **do not change offer/SKU for VyOS**, per the example file's comment:
     *"Please DON'T change the offer and SKU, you will still deploy versions 1.5.x."*

## 5. Timing Expectations

Plan for this rough timeline once you run `terraform apply`:

| Step | Approximate duration |
|---|---|
| Terraform deployment itself | ~3 minutes |
| Jumphost fully ready/reachable after Terraform completes | 10–15 minutes (be patient before troubleshooting RDP/SSH issues) |
| F5XC CE installation + registration (both sites) | ~1 hour, up to 1.5 hours |

If a CE hasn't registered after 1.5 hours, the most common cause is a naming
violation (capital letters or special characters somewhere in `prefix` or
label values) — see the naming constraint above.

## 6. Pre-Flight Checklist

- [ ] Git, Terraform installed
- [ ] Azure subscription ID + tenant ID at hand
- [ ] Service Principal created (or ready to `az login`)
- [ ] Marketplace terms accepted for F5XC CE image (if needed)
- [ ] F5XC tenant + existing namespace confirmed
- [ ] F5XC API P12 certificate generated, placed in `terraform/`, password set as `VES_P12_PASSWORD`
- [ ] F5XC label key confirmed not already used in tenant
- [ ] `terraform.tfvars` created from the example and all required variables edited
- [ ] `prefix`, namespace, and label values use only lower-case alphanumeric + dash
- [ ] Your public IP correctly set in `allowed_pips`
- [ ] `terraform init` run successfully

Once all boxes are checked, proceed to `terraform plan` then `terraform apply`
as described in the main [README.md](../README.md).

---

## Related Documentation

- [⬅ Back to Documentation Index](./README.md)
- [Architecture](./10-architecture.md) — network diagram and IP addressing
- [Troubleshooting](./30-troubleshooting.md) — once your lab is deployed
