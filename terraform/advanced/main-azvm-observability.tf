###############################################################################
# VM Observability - Loki + Grafana + Alloy
###############################################################################
# Central log server for the lab. Lives in the external subnet next to the
# proxy, but is NOT exempted from the VyOS egress firewall - it reaches the
# Internet only through Tinyproxy, like every other VM except the proxy itself.

resource "azurerm_linux_virtual_machine" "tf_azure_vm_obs" {
  name                = "${var.prefix}-vm-obs"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_linux

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_obs.id
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

  custom_data = base64encode(local.cloud_init_obs)

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Virtual Machine"
  }

  depends_on = [
    local_sensitive_file.tf_local_ssh_private_key,
    azurerm_ssh_public_key.tf_azure_ssh_key,
    azurerm_linux_virtual_machine.tf_azure_vm_rtr,                   # egress provider
    azurerm_linux_virtual_machine.tf_azure_vm_svc,                   # proxy + DNS + NTP provider
    azurerm_subnet_route_table_association.tf_azure_route_assoc_ext, # default route to the router
  ]
}

# NIC Observability
resource "azurerm_network_interface" "tf_azure_nic_obs" {
  name                = "${var.prefix}-nic-obs"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = "${var.prefix}-nic-obs-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_obs_ip_addr
  }
}

# --- Cloud-init ---

locals {
  cloud_init_obs = templatefile("${path.module}/cloud-init-obs.yaml.tpl", {
    proxy_ip       = var.azure_nic_svc_ip_addr # Tinyproxy runs on the services VM
    proxy_port     = var.tinyproxy_port
    dns_ip         = var.azure_nic_svc_ip_addr # BIND also runs on the services VM
    ntp_ip         = var.azure_nic_svc_ip_addr # ... and so does chrony
    dns_zone       = var.dns_internal_zone
    loki_retention = var.loki_retention_period
    vnet_cidr      = var.azure_cidr_vnet
  })
}
