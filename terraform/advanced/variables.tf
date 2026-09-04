###############################################################################
# General
###############################################################################
variable "prefix" {
  type        = string
  description = "Project prefix - used for every object name"
}

###############################################################################
# Azure subscription / service principal
###############################################################################
variable "azure_sub_id" {
  type        = string
  description = "Azure provider subscription ID"
  sensitive   = true
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure provider tenant ID"
  sensitive   = true
}

variable "azure_client_id" {
  type        = string
  description = "Azure provider client ID"
  sensitive   = true
}

variable "azure_client_secret" {
  type        = string
  description = "Azure provider client secret"
  sensitive   = true
}

###############################################################################
# Azure region and tags
###############################################################################
variable "azure_region" {
  type        = string
  description = "Azure resources type region"
  default     = "France Central"
}

variable "azure_tag_owner" {
  type        = string
  description = "Azure tag owner name"
}

variable "azure_tag_env" {
  type        = string
  description = "Azure tag environment name"
}

###############################################################################
# Azure network CIDR
###############################################################################
# VNet
variable "azure_cidr_vnet" {
  type        = string
  description = "Azure resources type VNET CIDR - vnet"
}

# Subnet External
variable "azure_cidr_sub_ext" {
  type        = string
  description = "Azure resources type subnet CIDR - external"
}

# Subnet Internal
variable "azure_cidr_sub_int" {
  type        = string
  description = "Azure resources type subnet CIDR - internal"
}

# Subnet Admin
variable "azure_cidr_sub_adm" {
  type        = string
  description = "Azure resources type subnet CIDR - admin"
}

# Subnet DMZ
variable "azure_cidr_sub_dmz" {
  type        = string
  description = "Azure resources type subnet CIDR - dmz"
}


###############################################################################
# Azure Resource Credentials
###############################################################################

variable "azure_ssh_username" {
  type        = string
  description = "Azure resources type username for VM ssh account"
}

variable "azure_admin_username" {
  type        = string
  description = "Azure resources type username for VM admin account"
}

variable "azure_adminpassword" {
  type        = string
  description = "Azure resources type password for admin account"
  sensitive   = true
}

variable "allowed_pips" {
  type        = list(string)
  description = "Allowed Public IP in Azure NSG rules"
}


###############################################################################
# Azure Load Balancer
###############################################################################
variable "azure_lbce_ip" {
  type        = string
  description = "Azure Load Balancer IP address"
}


###############################################################################
# Azure VM & Network
###############################################################################

# F5 XC CE VM name
variable "azure_vm_ce01" {
  type        = string
  description = "Azure VM name for XC CE01"
}

variable "azure_vm_ce02" {
  type        = string
  description = "Azure VM name for XC CE01"
}

# Services VM network address
variable "azure_nic_svc_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for Services nic VM"
}

# Application VM network address
variable "azure_nic_app_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for Application nic VM"
}

# Jumphost VM network address
variable "azure_nic_jmp_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for Jumphost nic VM"
}

# Observability VM network address
variable "azure_nic_obs_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for Observability nic VM"
}

# Router VM network address
variable "azure_nic_rtr_dmz_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for router dmz nic VM"
}

variable "azure_nic_rtr_ext_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for router external nic VM"
}

# XC CE01 VM network address
variable "azure_nic_xc_ce01_slo_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for XC CE01 SLO nic VM"
}

variable "azure_nic_xc_ce01_sli_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for XC CE01 SLI nic VM"
}

# XC CE02 VM network address
variable "azure_nic_xc_ce02_slo_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for XC CE02 SLO nic VM"
}

variable "azure_nic_xc_ce02_sli_ip_addr" {
  type        = string
  description = "Azure resources type Private IP static address for XC CE02 SLI nic VM"
}


###############################################################################
# Azure VM size
###############################################################################
variable "azure_vm_size_linux" {
  type        = string
  description = "Azure resources type VM size for regular Linux"
}

variable "azure_vm_size_srv" {
  type        = string
  description = "Azure resources type VM size for server"
}

variable "azure_vm_size_jmp" {
  type        = string
  description = "Azure resources type VM size for Jumphost"
}

variable "azure_vm_size_rtr" {
  type        = string
  description = "Azure resources type VM size for router"
}

variable "azure_vm_size_xc_ce" {
  type        = string
  description = "Azure resources type VM size for F5XC CE"
}


###############################################################################
# Azure marketplace images
###############################################################################
# VyOS
variable "image_publisher_vyos" {
  type        = string
  description = "Azure Marketplace image publisher for VyOS"
}

variable "image_offer_vyos" {
  type        = string
  description = "Azure Marketplace image offer for VyOS"
}

variable "image_sku_vyos" {
  type        = string
  description = "Azure Marketplace image SKU for VyOS"
}

variable "image_version_vyos" {
  type        = string
  description = "Azure Marketplace imageOS version for VyOS"
}

# XC CE
variable "image_publisher_xcce" {
  type        = string
  description = "Azure Marketplace image publisher for XC CE"
}

variable "image_offer_xcce" {
  type        = string
  description = "Azure Marketplace image offer for XC CE"
}

variable "image_sku_xcce" {
  type        = string
  description = "Azure Marketplace image SKU for XC CE"
}

variable "image_version_xcce" {
  type        = string
  description = "Azure Marketplace imageOS version for XC CE"
}

# Ubuntu
variable "image_publisher_ubuntu" {
  type        = string
  description = "Azure Marketplace image publisher for Ubuntu"
}

variable "image_offer_ubuntu" {
  type        = string
  description = "Azure Marketplace image offer for Ubuntu"
}

variable "image_sku_ubuntu" {
  type        = string
  description = "Azure Marketplace image SKU for Ubuntu"
}

variable "image_version_ubuntu" {
  type        = string
  description = "Azure Marketplace imageOS version for Ubuntu"
}

###############################################################################
# Router BGP & NAT
###############################################################################
variable "router_bgp_asn" {
  description = "Router local AS number"
  type        = number
}

variable "router_bgp_maximum_paths_ebgp" {
  description = "Number of Equal Cost Multi Path (ECMP) for a given /32 vip prefix on the router announced by CE. Use a value above the number of current CE to avoid changing it when adding CE."
  type        = number
}


###############################################################################
# Internal DNS (Services VM)
###############################################################################
variable "dns_internal_zone" {
  type        = string
  description = "Authoritative internal DNS zone served by BIND on the Services VM"
  default     = "f5demo.lan"
}


###############################################################################
# Tinyproxy (Services VM)
###############################################################################
variable "tinyproxy_port" {
  type        = number
  description = "Listening port for the Tinyproxy HTTP proxy running on the Services VM"
}


###############################################################################
# Observability (Loki / Grafana / Alloy)
###############################################################################
variable "loki_retention_period" {
  type        = string
  description = "How long Loki keeps logs, as a Go duration (168h = 7 days)"
  default     = "168h"
}


###############################################################################
# F5 XC settings
###############################################################################
variable "f5xc_tenant_name" {
  type        = string
  description = "F5XC tenant name"
}

variable "f5xc_api_p12_file" {
  type        = string
  description = "F5XC tenant api key"
}

variable "f5xc_api_url" {
  type        = string
  description = "F5XC tenant url"
}

variable "f5xc_namespace_name" {
  type        = string
  description = "F5XC Namespace name"
}

variable "f5xc_bgp_asn" {
  type        = number
  description = "ASN number for BGP configuration"
}

variable "f5xc_vip_cidr" {
  type        = string
  description = "IP range for XC CE VIP"
}

variable "f5xc_lb_nginx_fqdn" {
  type        = list(string)
  description = "XC http Load Balancer FQDNs for the NGINX server on the Application VM (external + internal names)"
}

variable "f5xc_lb_nginx_vip" {
  type        = string
  description = "XC http Load Balancer VIP for NGINX server on Application VM"
}

