output "Azure_Resource_Group_name" {
  value = azurerm_resource_group.tf_azure_rg.name
}

output "Azure_Public_IP_Jumphost_VM" {
  value = azurerm_public_ip.tf_azure_pip-jmp.ip_address
}

output "Jumphost_RDP_file" {
  value = local_file.tf_jumphost_rdp.filename
}

output "Azure_Public_IP_NAT_Gateway" {
  value = azurerm_public_ip.tf_azure_pip-nat.ip_address
}

output "XC_SMSv2_name" {
  value = volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name.name
}

output "XC_VirtualSite_name" {
  value = volterra_virtual_site.tf_f5xc_vsite.name
}

output "XC_VirtualSite_label" {
  value = "${var.f5xc_vsite-label-key} = ${var.f5xc_vsite-name}"
}
