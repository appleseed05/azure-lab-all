###############################################################################
# F5 XC Customer Edge 01
###############################################################################

resource "azurerm_linux_virtual_machine" "tf_azure_vm_xc_ce01" {
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  name                  = "${var.prefix}-${var.azure_vm_ce01}"
  location              = azurerm_resource_group.tf_azure_rg.location
  size                  = var.azure_vm_size_xc_ce
  network_interface_ids = [azurerm_network_interface.tf_azure_nic_xc_ce01_slo.id, azurerm_network_interface.tf_azure_nic_xc_ce01_sli.id]

  # is this user name mandatory?
  admin_username                  = "cloud-user"
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword


  boot_diagnostics {

  }

  admin_ssh_key {
    username   = "cloud-user"
    public_key = tls_private_key.tf_tls_ssh_key.public_key_openssh
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
    publisher = var.image_publisher_xcce
    offer     = var.image_offer_xcce
    sku       = var.image_sku_xcce
    version   = var.image_version_xcce
  }

  custom_data = base64encode(data.cloudinit_config.tf_f5xc_config_ce01.rendered)
  depends_on  = [azurerm_resource_group.tf_azure_rg]

}


# NIC XC CE01 SLO
resource "azurerm_network_interface" "tf_azure_nic_xc_ce01_slo" {
  name                  = "${var.prefix}-nic-xc-ce01-slo"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-xc-ce01-slo-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_xc_ce01_slo_ip_addr
  }
}

# NIC XC CE01 SLI
resource "azurerm_network_interface" "tf_azure_nic_xc_ce01_sli" {
  name                  = "${var.prefix}-nic-xc-ce01-sli"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-xc-ce01-sli-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_xc_ce01_sli_ip_addr
  }
}

###############################################################################
# F5 XC SMSv2 site token for CE01
###############################################################################

resource "volterra_token" "tf_f5xc_site_token01" {
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_site_01]
  name       = "${var.prefix}-site-token01"
  namespace  = "system"
  type       = 1
  site_name  = volterra_securemesh_site_v2.tf_f5xc_site_01.name
}

###############################################################################
# F5 XC CE Cloud Init for CE01
###############################################################################

data "cloudinit_config" "tf_f5xc_config_ce01" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      write_files = [
        {
          path        = "/etc/vpm/user_data"
          permissions = "0644"
          owner       = "root"
          content     = <<-EOT
            token: "${trimprefix(volterra_token.tf_f5xc_site_token01.id, "id=")}"
          EOT
        }
      ]
    })
  }
}


###############################################################################
# F5 XC Customer Edge 02
###############################################################################

resource "azurerm_linux_virtual_machine" "tf_azure_vm_xc_ce02" {
  name                  = "${var.prefix}-${var.azure_vm_ce02}"
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  location              = azurerm_resource_group.tf_azure_rg.location
  size                  = var.azure_vm_size_xc_ce
  network_interface_ids = [azurerm_network_interface.tf_azure_nic_xc_ce02_slo.id, azurerm_network_interface.tf_azure_nic_xc_ce02_sli.id]

  # is this user name mandatory?
  admin_username                  = "cloud-user"
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword


  boot_diagnostics {

  }

  admin_ssh_key {
    username   = "cloud-user"
    public_key = tls_private_key.tf_tls_ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  plan {
    name      = var.image_sku_xcce
    publisher = var.image_publisher_xcce
    product   = var.image_offer_xcce
  }

  source_image_reference {
    publisher = var.image_publisher_xcce
    offer     = var.image_offer_xcce
    sku       = var.image_sku_xcce
    version   = var.image_version_xcce
  }

  custom_data = base64encode(data.cloudinit_config.tf_f5xc_config_ce02.rendered)
  depends_on  = [azurerm_resource_group.tf_azure_rg]

}


# NIC XC CE02 SLO
resource "azurerm_network_interface" "tf_azure_nic_xc_ce02_slo" {
  name                  = "${var.prefix}-nic-xc-ce02-slo"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-xc-ce02-slo-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_xc_ce02_slo_ip_addr
  }
}

# NIC XC CE02 SLI
resource "azurerm_network_interface" "tf_azure_nic_xc_ce02_sli" {
  name                  = "${var.prefix}-nic-xc-ce02-sli"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-xc-ce02-sli-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_xc_ce02_sli_ip_addr
  }
}

###############################################################################
# F5 XC SMSv2 site token for CE02
###############################################################################

resource "volterra_token" "tf_f5xc_site_token02" {
  name       = "${var.prefix}-site-token02"
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_site_02]
  namespace  = "system"
  type       = 1
  site_name  = volterra_securemesh_site_v2.tf_f5xc_site_02.name
}

###############################################################################
# F5 XC CE Cloud Init for CE02
###############################################################################

data "cloudinit_config" "tf_f5xc_config_ce02" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      write_files = [
        {
          path        = "/etc/vpm/user_data"
          permissions = "0644"
          owner       = "root"
          content     = <<-EOT
            token: "${trimprefix(volterra_token.tf_f5xc_site_token02.id, "id=")}"
          EOT
        }
      ]
    })
  }
}
