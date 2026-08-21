###############################################################################
# VM Router (VyOS)
###############################################################################

# Accept the Marketplace licence terms (once per subscription).
resource "azurerm_marketplace_agreement" "tf_azure_agreement_vyos" {
  publisher = var.image_publisher_vyos
  offer     = var.image_offer_vyos
  plan      = var.image_sku_vyos
}

# Public IP for router interface
resource "azurerm_public_ip" "tf_azure_pip_rtr" {
  name                = "${var.prefix}-pip-rtr"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# VM
resource "azurerm_linux_virtual_machine" "tf_azure_vm_rtr" {
  name                = "${var.prefix}-vm-rtr"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  size                = var.azure_vm_size_rtr

  admin_username                  = var.azure_admin_username
  disable_password_authentication = false
  admin_password                  = var.azure_adminpassword

  network_interface_ids = [
    azurerm_network_interface.tf_azure_nic_rtr_dmz.id, # eth0 (DMZ / WAN)
    azurerm_network_interface.tf_azure_nic_rtr_ext.id  # eth1 (External / LAN)
  ]

  source_image_reference {
    publisher = var.image_publisher_vyos
    offer     = var.image_offer_vyos
    sku       = var.image_sku_vyos
    version   = var.image_version_vyos
  }

  plan {
    name      = var.image_sku_vyos
    product   = var.image_offer_vyos
    publisher = var.image_publisher_vyos
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(local.cloud_init_rtr)

  depends_on = [azurerm_marketplace_agreement.tf_azure_agreement_vyos]
}

# --- Interfaces ---
# NIC External
resource "azurerm_network_interface" "tf_azure_nic_rtr_ext" {
  name                  = "${var.prefix}-nic-rtr-ext"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-rtr-ext-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_rtr_ext_ip_addr
  }
}

# NIC DMZ
resource "azurerm_network_interface" "tf_azure_nic_rtr_dmz" {
  name                  = "${var.prefix}-nic-rtr-dmz"
  location              = azurerm_resource_group.tf_azure_rg.location
  resource_group_name   = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "${var.prefix}-nic-rtr-dmz-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_dmz.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.azure_nic_rtr_dmz_ip_addr
    public_ip_address_id          = azurerm_public_ip.tf_azure_pip_rtr.id
  }
}

# --- Cloud-init ---

locals {
  # Dynamically construct the DNAT rules, injecting our source variable IPs
  router_dnat_rules = [
    {
      name         = "app-vip-http"
      protocol     = "tcp"
      public_port  = "80"
      private_ip   = var.f5xc_lb_nginx_vip  # Dynamically references "192.168.200.5"
      private_port = "80"
    },
    {
      name         = "app-vip-https"
      protocol     = "tcp"
      public_port  = "443"
      private_ip   = var.f5xc_lb_nginx_vip  # Dynamically references "192.168.200.5"
      private_port = "443"
    },
    {
      name         = "jumphost-rdp"
      protocol     = "tcp"
      public_port  = "3389"
      private_ip   = var.azure_nic_jmp_ip_addr  # Dynamically references "10.1.1.5"
      private_port = "3389"
    },
    {
      name         = "jumphost-ssh"
      protocol     = "tcp"
      public_port  = "22"
      private_ip   = var.azure_nic_jmp_ip_addr  # Dynamically references "10.1.1.5"
      private_port = "22"
    }
  ]

  router_bgp_neighbors = [
  {
    ip         = var.azure_nic_xc_ce01_slo_ip_addr # CE01 SLO
    remote_asn = var.f5xc_bgp_asn
  },
  {
    ip         = var.azure_nic_xc_ce02_slo_ip_addr # CE02 SLO
    remote_asn = var.f5xc_bgp_asn
  },
]

  cloud_init_rtr = templatefile("${path.module}/cloud-init-rtr.yaml.tpl", {
    hostname               = "${var.prefix}-vyos-rtr"
    bgp_asn                = var.router_bgp_asn
    bgp_neighbors          = local.router_bgp_neighbors
    bgp_maximum_paths_ebgp = var.router_bgp_maximum_paths_ebgp
    dnat_rules             = local.router_dnat_rules
    vip_cidr               = var.f5xc_vip_cidr
    vnet_cidr              = var.azure_cidr_vnet
    ext_gateway            = cidrhost(var.azure_cidr_sub_ext, 1) # 10.1.10.1, Azure ext subnet
  })
}
