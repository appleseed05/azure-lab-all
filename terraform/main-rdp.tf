#####################################
### RDP file for the Jumphost VM   ###
#####################################

# Generates a ready-to-use .rdp file pointing at the Jumphost public IP.
# The file is (re)written on apply once the public IP has been allocated.
# Open it with any RDP client; you will be prompted for the password
# (var.azure_adminpassword) for user var.azure_admin-username.

resource "local_file" "tf_jumphost_rdp" {
  filename        = "${path.module}/${var.azure_vm-jmp}.rdp"
  file_permission = "0644"

  content = <<-EOT
    full address:s:${azurerm_public_ip.tf_azure_pip-jmp.ip_address}:3389
    username:s:${var.azure_admin-username}
    prompt for credentials:i:1
    administrative session:i:0
    screen mode id:i:1
    desktopwidth:i:1920
    desktopheight:i:1080
    session bpp:i:32
    authentication level:i:2
    redirectclipboard:i:1
  EOT
}
