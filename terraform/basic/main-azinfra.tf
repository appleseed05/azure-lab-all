###############################################################################
# Resource Group
###############################################################################

resource "azurerm_resource_group" "tf_azure_rg" {
  location = var.azure_region
  name     = "${var.prefix}-rg"

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Resource Group"
  }
}

###############################################################################
# VNET & Subnets
###############################################################################

resource "azurerm_virtual_network" "tf_azure_vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  address_space       = [var.azure_cidr_vnet]

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Virtual Network"
  }
}

resource "azurerm_subnet" "tf_azure_sub_ext" {
  name                 = "${var.prefix}-sub-ext"
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr_sub_ext]
}

resource "azurerm_subnet" "tf_azure_sub_int" {
  name                 = "${var.prefix}-sub-int"
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr_sub_int]
}

resource "azurerm_subnet" "tf_azure_sub_adm" {
  name                 = "${var.prefix}-sub-adm"
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr_sub_adm]
}

resource "azurerm_subnet" "tf_azure_sub_dmz" {
  name                 = "${var.prefix}-sub-dmz"
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr_sub_dmz]
}

###############################################################################
# Route table
###############################################################################

resource "azurerm_route_table" "tf_azure_route_ext" {
  name                = "${var.prefix}-route-ext"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  route {
    name                   = "default-to-vyos"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.azure_nic_rtr_ext_ip_addr # 10.1.10.254
  }

  route {
    name                   = "xc-vip-lb"
    address_prefix         = "192.168.200.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.1.10.250"
  }

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Route"
  }
}

resource "azurerm_route_table" "tf_azure_route_int" {
  name                = "${var.prefix}-route-int"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  route {
    name                   = "default-to-vyos"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.azure_nic_rtr_ext_ip_addr # 10.1.10.254
  }

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Route"
  }
}

resource "azurerm_route_table" "tf_azure_route_adm" {
  name                = "${var.prefix}-route-adm"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  route {
    name                   = "default-to-vyos"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.azure_nic_rtr_ext_ip_addr # 10.1.10.254
  }

  tags = {
    environment   = var.azure_tag_env
    owner         = var.azure_tag_owner
    resource_type = "Route"
  }
}

# Associate Route Table to External Subnet
resource "azurerm_subnet_route_table_association" "tf_azure_route_assoc_ext" {
  subnet_id      = azurerm_subnet.tf_azure_sub_ext.id
  route_table_id = azurerm_route_table.tf_azure_route_ext.id
}

# Associate Route Table to Internal Subnet
resource "azurerm_subnet_route_table_association" "tf_azure_route_assoc_int" {
  subnet_id      = azurerm_subnet.tf_azure_sub_int.id
  route_table_id = azurerm_route_table.tf_azure_route_int.id
}

# Associate Route Table to Admin Subnet
resource "azurerm_subnet_route_table_association" "tf_azure_route_assoc_adm" {
  subnet_id      = azurerm_subnet.tf_azure_sub_adm.id
  route_table_id = azurerm_route_table.tf_azure_route_adm.id
}
