###############################################################################
# RDP file for the Jumphost VM
###############################################################################

# Generates a ready-to-use .rdp file pointing at the VyOS router public IP:
# the Jumphost has no public IP of its own and is reached through the DNAT
# rule on the router (see router_dnat-rules).
# Open it with any RDP client; you will be prompted for the password
# (var.azure_adminpassword) for user var.azure_admin_username.

resource "local_file" "tf_jumphost_rdp" {
  filename        = "${path.module}/${azurerm_linux_virtual_machine.tf_azure_vm_jmp.name}.rdp"
  file_permission = "0644"

  content = <<-EOT
    full address:s:${azurerm_public_ip.tf_azure_pip_rtr.ip_address}:3389
    username:s:${var.azure_admin_username}
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
