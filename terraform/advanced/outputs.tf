###############################################################################
# Outputs
###############################################################################

output "Azure_Resource_Group_name" {
  value = azurerm_resource_group.tf_azure_rg.name
}

output "Jumphost_RDP_file" {
  value = local_file.tf_jumphost_rdp.filename
}

output "Azure_Public_IP_Router_VM" {
  value = azurerm_public_ip.tf_azure_pip_rtr.ip_address
}

output "XC_site_name_01" {
  value = volterra_securemesh_site_v2.tf_f5xc_site_01.name
}

output "XC_site_name_02" {
  value = volterra_securemesh_site_v2.tf_f5xc_site_02.name
}

output "XC_VirtualSite_name" {
  value = volterra_virtual_site.tf_f5xc_vsite.name
}

output "last_applied_at" {
  description = "Timestamp of the last terraform apply (UTC)"
  value       = timestamp()
}
