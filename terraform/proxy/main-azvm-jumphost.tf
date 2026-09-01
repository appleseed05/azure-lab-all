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

  # user_data, not custom_data: custom_data is ForceNew, so every cloud-init
  # edit destroyed and recreated this VM. user_data updates in place. cloud-init
  # reads it from IMDS (compute.userData) ONLY when customData is empty
  # (DataSourceAzure.py: `if not userdata_raw`), so custom_data must stay unset.
  # A cloud-init change still needs a re-run to take effect on a live VM:
  #   terraform apply && ssh <jmp> sudo cloud-init clean --logs --reboot
  user_data = base64encode(local.cloud_init_jmp)

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Virtual Machine"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr,                   # egress provider
    azurerm_linux_virtual_machine.tf_azure_vm_ext,                   # proxy provider (tinyproxy)
    azurerm_subnet_route_table_association.tf_azure_route_assoc_adm, # default route to the router
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
    proxy_ip       = var.azure_nic_ext_ip_addr # Tinyproxy runs on the external VM
    proxy_port     = var.tinyproxy_port
    vnet_cidr      = var.azure_cidr_vnet
    dns_ip         = var.azure_nic_ext_ip_addr # BIND also runs on the external VM
    ntp_ip         = var.azure_nic_ext_ip_addr # ... and so does chrony
    dns_zone       = var.dns_internal_zone
    # Same keypair Terraform installs as admin_ssh_key on every VM, so the
    # jumphost can hop to them without a password.
    ssh_private_key = tls_private_key.tf_tls_ssh_key.private_key_openssh
  })
}
