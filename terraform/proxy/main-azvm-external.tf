###############################################################################
# VM External
###############################################################################

# Server Ubuntu - external
resource "azurerm_linux_virtual_machine" "tf_azure_vm_ext" {
  name                = "${var.prefix}-vm-ext"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_linux

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_ext.id
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

  custom_data = base64encode(local.cloud_init_ext)

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr,                   # egress provider
    azurerm_subnet_route_table_association.tf_azure_route_assoc_ext, # default route to the router
  ]
}

# NIC External
resource "azurerm_network_interface" "tf_azure_nic_ext" {
  name                = "${var.prefix}-nic-ext"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-ext-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_ext_ip_addr
  }
}

# --- Cloud-init ---

locals {
  # A records published in the internal DNS zone. Built from the very same
  # variables that assign the NIC private IPs, so the zone can never drift from
  # what is actually deployed. Add a VM here when you add one to the lab.
  dns_zone_records = {
    "${var.prefix}-vm-jmp"               = var.azure_nic_jmp_ip_addr
    "${var.prefix}-vm-ext"               = var.azure_nic_ext_ip_addr
    "${var.prefix}-vm-int"               = var.azure_nic_int_ip_addr
    "${var.prefix}-vm-rtr-ext"           = var.azure_nic_rtr_ext_ip_addr
    "${var.prefix}-vm-rtr-dmz"           = var.azure_nic_rtr_dmz_ip_addr
    "${var.prefix}-${var.azure_vm_ce01}" = var.azure_nic_xc_ce01_slo_ip_addr
    "${var.prefix}-${var.azure_vm_ce02}" = var.azure_nic_xc_ce02_slo_ip_addr
    "${var.prefix}-lbce"                 = var.azure_lbce_ip
    "mylb"                               = var.f5xc_lb_nginx_vip
  }

  cloud_init_ext = templatefile("${path.module}/cloud-init-ext.yaml.tpl", {
    proxy_port    = var.tinyproxy_port
    allowed_cidr  = var.azure_cidr_vnet
    dns_zone      = var.dns_internal_zone
    dns_listen_ip = var.azure_nic_ext_ip_addr # named must bind explicitly, see template
    dns_records   = local.dns_zone_records
  })
}
