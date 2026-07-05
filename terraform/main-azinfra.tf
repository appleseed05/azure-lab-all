# ----------------------
# --- Resource Group ---
# ----------------------

resource "azurerm_resource_group" "tf_azure_rg" {
  location = var.azure_region
  name     = var.azure_rg

  tags = {
    environment = var.azure_tag-env
    owner = var.azure_tag-owner
    resource_type = "Resource Group"
  }
}

# ----------------------
# --- VNET & Subnets ---
# ----------------------

resource "azurerm_virtual_network" "tf_azure_vnet" {
  name                = var.azure_vnet
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  address_space       = [var.azure_cidr-vnet]

  tags = {
    environment = var.azure_tag-env
    owner = var.azure_tag-owner
    resource_type = "Virtual Network"
  }
}

resource "azurerm_subnet" "tf_azure_sub-ext" {
  name                 = var.azure_sub-ext
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr-sub-ext]
}

resource "azurerm_subnet" "tf_azure_sub-int" {
  name                 = var.azure_sub-int
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr-sub-int]
}

resource "azurerm_subnet" "tf_azure_sub-adm" {
  name                 = var.azure_sub-adm
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr-sub-adm]
}

resource "azurerm_subnet" "tf_azure_sub-jmp" {
  name                 = var.azure_sub-jmp
  resource_group_name  = azurerm_resource_group.tf_azure_rg.name
  virtual_network_name = azurerm_virtual_network.tf_azure_vnet.name
  address_prefixes     = [var.azure_cidr-sub-jmp]
}

/*
# -------------------
# --- Route table ---
# -------------------

resource "azurerm_route_table" "tf_azure_route" {
  name                = var.azure_route
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  route {
    name           = var.azure_rt-sub-ext
    address_prefix = var.azure_cidr-sub-ext
    next_hop_type  = "None"
  }

  route {
    name           = var.azure_rt-sub-int
    address_prefix = var.azure_cidr-sub-int
    next_hop_type  = "None"
  }

  route {
    name           = var.azure_rt-sub-adm
    address_prefix = var.azure_cidr-sub-adm
    next_hop_type  = "None"
  }

  tags = {
    environment = var.azure_tag-env
    owner = var.azure_tag-owner
    resource_type = "Route"
  }
}
*/

# --------------------------------
# --- Public IPs & NAT Gateway ---
# --------------------------------

# NAT Gateway
resource "azurerm_nat_gateway" "tf_azure_natgw" {
  name                = var.azure_natgw
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  sku_name            = "Standard"
}

# NAT Gateway association to External Subnet
resource "azurerm_subnet_nat_gateway_association" "tf_azure_natgw-sub-assoc" {
  subnet_id       = azurerm_subnet.tf_azure_sub-ext.id
  nat_gateway_id  = azurerm_nat_gateway.tf_azure_natgw.id
}

# Public IP for NAT Gateway
resource "azurerm_public_ip" "tf_azure_pip-nat" {
  name                = var.azure_pip-nat
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public IP for Jumphost interface
resource "azurerm_public_ip" "tf_azure_pip-jmp" {
  name                = var.azure_pip-jmp
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public IP association for NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "tf_azure_pip-nat-assoc" {
  nat_gateway_id       = azurerm_nat_gateway.tf_azure_natgw.id
  public_ip_address_id = azurerm_public_ip.tf_azure_pip-nat.id
}


# --------------------------
# --- Network Interfaces ---
# --------------------------

# NIC External
resource "azurerm_network_interface" "tf_azure_nic-ext" {
  name                = var.azure_nic-ext
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = var.azure_nic-ext-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-ext-ip-addr
  }
}

# NIC Internal
resource "azurerm_network_interface" "tf_azure_nic-int" {
  name                = var.azure_nic-int
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = var.azure_nic-int-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-int-ip-addr
  }
}

# NIC Jumphost
resource "azurerm_network_interface" "tf_azure_nic-jmp" {
  name                = var.azure_nic-jmp
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name

  ip_configuration {
    name                          = var.azure_nic-jmp-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-jmp.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-jmp-ip-addr
    public_ip_address_id          = azurerm_public_ip.tf_azure_pip-jmp.id
  }
}

# NIC XC CE01 SLO
resource "azurerm_network_interface" "tf_azure_nic-xc-ce01-slo" {
  name                = var.azure_nic-xc-ce01-slo
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = var.azure_nic-xc-ce01-slo-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-xc-ce01-slo-ip-addr
  }
}

# NIC XC CE01 SLI
resource "azurerm_network_interface" "tf_azure_nic-xc-ce01-sli" {
  name                = var.azure_nic-xc-ce01-sli
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = var.azure_nic-xc-ce01-sli-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-xc-ce01-sli-ip-addr
  }
}

# NIC XC CE02 SLO
resource "azurerm_network_interface" "tf_azure_nic-xc-ce02-slo" {
  name                = var.azure_nic-xc-ce02-slo
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = var.azure_nic-xc-ce02-slo-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-ext.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-xc-ce02-slo-ip-addr
  }
}

# NIC XC CE02 SLI
resource "azurerm_network_interface" "tf_azure_nic-xc-ce02-sli" {
  name                = var.azure_nic-xc-ce02-sli
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = var.azure_nic-xc-ce02-sli-ip
    subnet_id                     = azurerm_subnet.tf_azure_sub-int.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nic-xc-ce02-sli-ip-addr
  }
}
