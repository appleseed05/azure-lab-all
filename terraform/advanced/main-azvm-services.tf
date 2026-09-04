###############################################################################
# VM Services
###############################################################################

# Renamed from "ext" to "svc": this VM is the lab's shared-services host
# (Tinyproxy + BIND9 + chrony), not merely "the VM in the external subnet".
# The Azure *subnet* keeps its "ext" name - only the VM was renamed.
#
# These moved blocks tell Terraform the resources were renamed rather than
# replaced wholesale. The Azure object names still change (`name` is ForceNew),
# so the VM and NIC ARE recreated - but as an ordered replace, not as an
# independent create+destroy that would try to claim the same static IP twice.
# Safe to delete once the rename has been applied.
moved {
  from = azurerm_linux_virtual_machine.tf_azure_vm_ext
  to   = azurerm_linux_virtual_machine.tf_azure_vm_svc
}

moved {
  from = azurerm_network_interface.tf_azure_nic_ext
  to   = azurerm_network_interface.tf_azure_nic_svc
}


# Server Ubuntu - services (Tinyproxy + BIND9 + chrony)
resource "azurerm_linux_virtual_machine" "tf_azure_vm_svc" {
  name                = "${var.prefix}-vm-svc"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_linux

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_svc.id
  ]

  admin_ssh_key {
    username   = var.azure_admin_username
    public_key = tls_private_key.tf_tls_ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.image_publisher_ubuntu
    offer     = var.image_offer_ubuntu
    sku       = var.image_sku_ubuntu
    version   = var.image_version_ubuntu
  }

  custom_data = base64encode(local.cloud_init_svc)

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr,                   # egress provider
    azurerm_subnet_route_table_association.tf_azure_route_assoc_ext, # default route to the router
  ]
}

# NIC Services
resource "azurerm_network_interface" "tf_azure_nic_svc" {
  name                = "${var.prefix}-nic-svc"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-svc-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_svc_ip_addr
  }
}

# --- Cloud-init ---

locals {
  # A records published in the internal DNS zone. Built from the very same
  # variables that assign the NIC private IPs, so the zone can never drift from
  # what is actually deployed. Add a VM here when you add one to the lab.
  # The FQDN from var.f5xc_lb_nginx_fqdn that belongs to the internal zone.
  # Matched by suffix rather than by list position, so reordering the tfvars
  # list cannot silently point the record at the public name. one() also errors
  # loudly if two internal names are ever added, instead of picking one.
  internal_lb_fqdn = try(one([for f in var.f5xc_lb_nginx_fqdn : f if endswith(f, ".${var.dns_internal_zone}")]), null)

  dns_zone_records = merge({
    "${var.prefix}-vm-jmp"               = var.azure_nic_jmp_ip_addr
    "${var.prefix}-vm-svc"               = var.azure_nic_svc_ip_addr
    "${var.prefix}-vm-obs"               = var.azure_nic_obs_ip_addr
    "${var.prefix}-vm-app"               = var.azure_nic_app_ip_addr
    "${var.prefix}-vm-rtr-ext"           = var.azure_nic_rtr_ext_ip_addr
    "${var.prefix}-vm-rtr-dmz"           = var.azure_nic_rtr_dmz_ip_addr
    "${var.prefix}-${var.azure_vm_ce01}" = var.azure_nic_xc_ce01_slo_ip_addr
    "${var.prefix}-${var.azure_vm_ce02}" = var.azure_nic_xc_ce02_slo_ip_addr
    "${var.prefix}-lbce"                 = var.azure_lbce_ip
    },
    # A record for the XC HTTP LB's internal name, pointing at the VIP.
    # The zone file needs the name RELATIVE to the zone: an entry of
    # "mylab.f5demo.lan" would be read by BIND as mylab.f5demo.lan.f5demo.lan
    # and would load without error while never matching a query - hence the
    # trimsuffix. Skipped entirely if no internal FQDN is configured.
    local.internal_lb_fqdn == null ? {} : {
      "${trimsuffix(local.internal_lb_fqdn, ".${var.dns_internal_zone}")}" = var.f5xc_lb_nginx_vip
    }
  )

  cloud_init_svc = templatefile("${path.module}/cloud-init-svc.yaml.tpl", {
    proxy_port    = var.tinyproxy_port
    allowed_cidr  = var.azure_cidr_vnet
    dns_zone      = var.dns_internal_zone
    dns_listen_ip = var.azure_nic_svc_ip_addr # named must bind explicitly, see template
    dns_records   = local.dns_zone_records
    syslog_host   = var.azure_nic_obs_ip_addr
  })
}
