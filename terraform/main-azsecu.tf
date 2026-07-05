# ---------------
# --- SSH Key ---
# ---------------

# --- SSH key generation (Terraform TLS provider) ---
# NOTE: The private key will also be stored in Terraform state (sensitive).
resource "tls_private_key" "tf_tls_ssh-key" {
  algorithm = "ED25519"
}

# Write the private key to disk so you can use it with ssh -i ...
resource "local_sensitive_file" "tf_local_ssh-private-key" {
  filename        = var.tls_ssh-key-path-private
  content         = tls_private_key.tf_tls_ssh-key.private_key_openssh
  file_permission = "0600"
}

# Write the public key to disk (optional convenience)
resource "local_file" "tf_local_ssh-public-key" {
  filename = var.tls_ssh-key-path-public
  content  = tls_private_key.tf_tls_ssh-key.public_key_openssh
}

# Optional: also create an Azure SSH public key resource
resource "azurerm_ssh_public_key" "tf_azure_ssh-key" {
  name                = var.azure_ssh-key
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  public_key          = tls_private_key.tf_tls_ssh-key.public_key_openssh
}


# Network Security Group for Jumphost
resource "azurerm_network_security_group" "tf_azure_nsg-jmp" {
  name                = var.azure_nsg-jmp
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
}

# NSG adm rule to allow inbound RDP
resource "azurerm_network_security_rule" "tf_azure_nsg-allow-rdp" {
  name                        = var.azure_nsg-allow-rdp
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefixes     = var.allowed-pips  # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg-jmp.name
}

# NSG adm rule to allow inbound SSH
resource "azurerm_network_security_rule" "tf_azure_nsg-allow-ssh" {
  name                        = var.azure_nsg-allow-ssh
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.allowed-pips  # e.g. "203.0.113.10/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf_azure_rg.name
  network_security_group_name = azurerm_network_security_group.tf_azure_nsg-jmp.name
}

# NSG association to Jumphost interface
resource "azurerm_network_interface_security_group_association" "tf_azure_nsg-assoc" {
  network_interface_id      = azurerm_network_interface.tf_azure_nic-jmp.id
  network_security_group_id = azurerm_network_security_group.tf_azure_nsg-jmp.id
}
