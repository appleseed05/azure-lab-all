###############################################################################
# Azure Load Balancer
###############################################################################

resource "azurerm_lb" "tf_azure_lbce" {
  name                = "${var.prefix}-lbce"
  location            = azurerm_resource_group.tf_azure_rg.location
  resource_group_name = azurerm_resource_group.tf_azure_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "${var.prefix}-lbce-ip"
    subnet_id                     = azurerm_subnet.tf_azure_sub_ext.id
    private_ip_address            = var.azure_lbce_ip
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_lb_backend_address_pool" "tf_azure_lbce_pool" {
  name            = "${var.prefix}-lbce-pool"
  loadbalancer_id = azurerm_lb.tf_azure_lbce.id
}

resource "azurerm_network_interface_backend_address_pool_association" "tf_azure_lbce1" {
  network_interface_id    = azurerm_network_interface.tf_azure_nic_xc_ce01_slo.id
  ip_configuration_name   = azurerm_network_interface.tf_azure_nic_xc_ce01_slo.ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.tf_azure_lbce_pool.id
}

resource "azurerm_network_interface_backend_address_pool_association" "tf_azure_lbce2" {
  network_interface_id    = azurerm_network_interface.tf_azure_nic_xc_ce02_slo.id
  ip_configuration_name   = azurerm_network_interface.tf_azure_nic_xc_ce02_slo.ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.tf_azure_lbce_pool.id
}

resource "azurerm_lb_probe" "tf_azure_lbce_probe" {
  name                = "${var.prefix}-lbce-prob"
  loadbalancer_id     = azurerm_lb.tf_azure_lbce.id
  protocol            = "Tcp"
  port                = 65500
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "tf_azure_lbce_rule" {
  name                           = "${var.prefix}-lbce-rule"
  loadbalancer_id                = azurerm_lb.tf_azure_lbce.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = azurerm_lb.tf_azure_lbce.frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.tf_azure_lbce_pool.id]
  probe_id                       = azurerm_lb_probe.tf_azure_lbce_probe.id
  floating_ip_enabled            = false
  load_distribution              = "Default"
  idle_timeout_in_minutes        = 30
}
