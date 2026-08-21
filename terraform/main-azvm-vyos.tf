###############################################################################
# VM Jumphost
###############################################################################

resource "azurerm_linux_virtual_machine" "tf_azure_vm_jmp" {
  name                = "${var.prefix}-vm-jmp"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_jmp

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_jmp.id
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

  custom_data = base64encode(local.cloud_init_jmp)

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Virtual Machine"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key
  ]
}

# NIC Jumphost
resource "azurerm_network_interface" "tf_azure_nic_jmp" {
  name                = "${var.prefix}-nic-jmp"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-jmp-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_adm.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_jmp_ip_addr
  }
}

# --- Cloud-init ---

locals {
  cloud_init_jmp = templatefile("${path.module}/cloud-init-jmp.yaml.tpl", {
    admin_username = var.azure_admin_username
  })
}
