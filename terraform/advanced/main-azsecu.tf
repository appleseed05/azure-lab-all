###############################################################################
# SSH Key
###############################################################################

# SSH key generation (Terraform TLS provider)
# NOTE: The private key will also be stored in Terraform state (sensitive).
resource "tls_private_key" "tf_tls_ssh_key" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "tf_local_ssh_private_key" {
  filename        = "${path.module}/${var.prefix}-key-ed25519"
  content         = tls_private_key.tf_tls_ssh_key.private_key_openssh
  file_permission = "0600"
}

resource "local_file" "tf_local_ssh_public_key" {
  filename        = "${path.module}/${var.prefix}-key-ed25519.pub"
  content         = tls_private_key.tf_tls_ssh_key.public_key_openssh
  file_permission = "0644"
}

resource "azurerm_ssh_public_key" "tf_azure_ssh_key" {
  name                = "${var.prefix}-ssh-key"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  public_key          = tls_private_key.tf_tls_ssh_key.public_key_openssh
}

###############################################################################
# Network Security Group for Jumphost
###############################################################################

resource "azurerm_network_security_group" "tf_azure_nsg_jmp" {
  name                = "${var.prefix}-nsg-jmp"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
}

# NSG Jumphost rule to allow inbound RDP
resource "azurerm_network_security_rule" "tf_azure_nsg_jmp_allow_rdp" {
  name                        = "${var.prefix}-nsg-jmp-allow-rdp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_jmp.name
}

# NSG Jumphost rule to allow inbound SSH
resource "azurerm_network_security_rule" "tf_azure_nsg_jmp_allow_ssh" {
  name                        = "${var.prefix}-nsg-jmp-allow-ssh"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_jmp.name
}

# NSG association to Jumphost interface
resource "azurerm_network_interface_security_group_association" "tf_azure_nsg_jmp_assoc" {
  network_interface_id      = azurerm_network_interface.tf_azure_nic_jmp.id
  network_security_group_id = azurerm_network_security_group.tf_azure_nsg_jmp.id
}

###############################################################################
# Network Security Group for Router DMZ
###############################################################################

resource "azurerm_network_security_group" "tf_azure_nsg_dmz" {
  name                = "${var.prefix}-nsg-dmz"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
}

# NSG dmz rule to allow inbound RDP
resource "azurerm_network_security_rule" "tf_azure_nsg_dmz_allow_rdp" {
  name                        = "${var.prefix}-nsg-dmz-allow-rdp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_dmz.name
}

# NSG dmz rule to allow inbound SSH
resource "azurerm_network_security_rule" "tf_azure_nsg_dmz_allow_ssh" {
  name                        = "${var.prefix}-nsg-dmz-allow-ssh"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_dmz.name
}

# NSG dmz rule to allow inbound http
resource "azurerm_network_security_rule" "tf_azure_nsg_dmz_allow_http" {
  name                        = "${var.prefix}-nsg-dmz-allow-http"
  priority                    = 121
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_dmz.name
}

# NSG dmz rule to allow inbound https
resource "azurerm_network_security_rule" "tf_azure_nsg_dmz_allow_https" {
  name                        = "${var.prefix}-nsg-dmz-allow-https"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefixes     = var.allowed_pips # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg_dmz.name
}

# NSG association to Jumphost interface
resource "azurerm_network_interface_security_group_association" "tf_azure_nsg_dmz_assoc" {
  network_interface_id      = azurerm_network_interface.tf_azure_nic_rtr_dmz.id
  network_security_group_id = azurerm_network_security_group.tf_azure_nsg_dmz.id
}
