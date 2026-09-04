###############################################################################
# VM Application
###############################################################################

# Renamed from "int" to "app": this VM is the lab's application server (NGINX
# origin behind the F5XC HTTP LB), not merely "the VM in the internal subnet".
# The Azure *subnet* and its route table keep their "int" names.
# Safe to delete these moved blocks once the rename has been applied.
moved {
  from = azurerm_linux_virtual_machine.tf_azure_vm_int
  to   = azurerm_linux_virtual_machine.tf_azure_vm_app
}

moved {
  from = azurerm_network_interface.tf_azure_nic_int
  to   = azurerm_network_interface.tf_azure_nic_app
}


# Server Ubuntu - application (NGINX origin)
resource "azurerm_linux_virtual_machine" "tf_azure_vm_app" {
  name                = "${var.prefix}-vm-app"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_linux

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_app.id
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

  custom_data = base64encode(local.cloud_init_app)

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr, # egress provider
    azurerm_linux_virtual_machine.tf_azure_vm_svc, # proxy provider (tinyproxy)
    azurerm_subnet_route_table_association.tf_azure_route_assoc_int,
  ]
}

# NIC Application
resource "azurerm_network_interface" "tf_azure_nic_app" {
  name                = "${var.prefix}-nic-app"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-app-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_app_ip_addr
  }
}

# --- Cloud-init ---

locals {
  cloud_init_app = templatefile("${path.module}/cloud-init-app.yaml.tpl", {
    proxy_ip    = var.azure_nic_svc_ip_addr # Tinyproxy runs on the services VM
    proxy_port  = var.tinyproxy_port
    vnet_cidr   = var.azure_cidr_vnet
    dns_ip      = var.azure_nic_svc_ip_addr # BIND also runs on the services VM
    ntp_ip      = var.azure_nic_svc_ip_addr # ... and so does chrony
    dns_zone    = var.dns_internal_zone
    syslog_host = var.azure_nic_obs_ip_addr
    vip_cidr    = var.f5xc_vip_cidr
  })
}
