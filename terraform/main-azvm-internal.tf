###############################################################################
# VM Internal
###############################################################################

# Server Ubuntu - internal
resource "azurerm_linux_virtual_machine" "tf_azure_vm_int" {
  name                = "${var.prefix}-vm-int"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_linux

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_int.id
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

  custom_data = base64encode(local.cloud_init_int)

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr, # egress provider
    azurerm_subnet_route_table_association.tf_azure_route_assoc_int,
  ]
}

# NIC Internal
resource "azurerm_network_interface" "tf_azure_nic_int" {
  name                = "${var.prefix}-nic-int"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-int-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_int_ip_addr
  }
}

# --- Cloud-init ---

locals {
  cloud_init_int = templatefile("${path.module}/cloud-init-int.yaml.tpl", {})
}
