# -----------
# --- VMs ---
# -----------

# Server Ubuntu - external
resource "azurerm_linux_virtual_machine" "tf_azure_vm-ext" {
  name                = var.azure_vm-ext
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm-size-linux

  admin_username                  = var.azure_admin-username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic-ext.id
  ]

  admin_ssh_key {
    username   = var.azure_admin-username
    public_key = tls_private_key.tf_tls_ssh-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh-private-key,
    azurerm_ssh_public_key.tf_azure_ssh-key
  ]
}

# Server Ubuntu - internal
resource "azurerm_linux_virtual_machine" "tf_azure_vm-int" {
  name                = var.azure_vm-int
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm-size-linux

  admin_username                  = var.azure_admin-username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic-int.id
  ]

  admin_ssh_key {
    username   = var.azure_admin-username
    public_key = tls_private_key.tf_tls_ssh-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh-private-key,
    azurerm_ssh_public_key.tf_azure_ssh-key
  ]
}

# Jumphost Ubuntu - jmp
resource "azurerm_linux_virtual_machine" "tf_azure_vm-jmp" {
  name                = var.azure_vm-jmp
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm-size-jmp

  admin_username                  = var.azure_admin-username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic-jmp.id
  ]

  admin_ssh_key {
    username   = var.azure_admin-username
    public_key = tls_private_key.tf_tls_ssh-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-jmp.yaml", {
    admin_username = var.azure_admin-username
  }))

  tags = {
    environment   = var.azure_tag-env
    owner         = var.azure_tag-owner
    resource_type = "Virtual Machine"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh-private-key,
    azurerm_ssh_public_key.tf_azure_ssh-key
  ]
}
