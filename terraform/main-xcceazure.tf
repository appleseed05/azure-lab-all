resource "azurerm_linux_virtual_machine" "tf_f5xc_vm-xc-ce01" {
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  name                  = var.azure_vm-xc-ce01
  location              = azurerm_resource_group.tf_azure_rg.location
  size                  = var.azure_vm-size-xc-ce
  network_interface_ids = [azurerm_network_interface.tf_azure_nic-xc-ce01-slo.id, azurerm_network_interface.tf_azure_nic-xc-ce01-sli.id]

# is this user name mandatory?
  admin_username                  = "cloud-user"
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword


  boot_diagnostics {

  }

  admin_ssh_key {
    username   = "cloud-user"
    public_key = tls_private_key.tf_tls_ssh-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  plan {
    name      = "f5xccebyol"
    publisher = "f5-networks"
    product   = "f5xc_customer_edge"
  }

  source_image_reference {
    publisher = "f5-networks"
    offer     = "f5xc_customer_edge"
    sku       = "f5xccebyol"
    version   = "2024.44.1"
  }

  custom_data = base64encode(data.cloudinit_config.tf_f5xc_ce-config.rendered)
  depends_on  = [azurerm_resource_group.tf_azure_rg]

}


resource "azurerm_linux_virtual_machine" "tf_f5xc_vm-xc-ce02" {
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  name                  = var.azure_vm-xc-ce02
  location              = azurerm_resource_group.tf_azure_rg.location
  size                  = var.azure_vm-size-xc-ce
  network_interface_ids = [azurerm_network_interface.tf_azure_nic-xc-ce02-slo.id, azurerm_network_interface.tf_azure_nic-xc-ce02-sli.id]

# is this user name mandatory?
  admin_username                  = "cloud-user"
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword


  boot_diagnostics {

  }

  admin_ssh_key {
    username   = "cloud-user"
    public_key = tls_private_key.tf_tls_ssh-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  plan {
    name      = "f5xccebyol"
    publisher = "f5-networks"
    product   = "f5xc_customer_edge"
  }

  source_image_reference {
    publisher = "f5-networks"
    offer     = "f5xc_customer_edge"
    sku       = "f5xccebyol"
    version   = "2024.44.1"
  }

  custom_data = base64encode(data.cloudinit_config.tf_f5xc_ce-config.rendered)
  depends_on  = [azurerm_resource_group.tf_azure_rg]

}
