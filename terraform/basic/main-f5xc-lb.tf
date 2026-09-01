###############################################################################
# F5 XC Origin Pool NGINX
###############################################################################

resource "volterra_origin_pool" "tf_f5xc_pool_ext_nginx" {
  name                   = "${var.prefix}-pool-nginx"
  namespace              = var.f5xc_namespace_name
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "ROUND_ROBIN"

  origin_servers {
    private_ip {
      ip             = azurerm_network_interface.tf_azure_nic_int.private_ip_address
      inside_network = true
      site_locator {
        virtual_site {
          name      = volterra_virtual_site.tf_f5xc_vsite.name
          namespace = volterra_virtual_site.tf_f5xc_vsite.namespace
        }
      }
    }
  }
  port = "80"

  no_tls = true
}

###############################################################################
# F5 XC http LB NGINX
###############################################################################
resource "volterra_http_loadbalancer" "tf_f5xc_lb_nginx" {
  name      = "${var.prefix}-lb-nginx"
  namespace = var.f5xc_namespace_name

  domains = [var.f5xc_lb_nginx_fqdn]

  http {
    dns_volterra_managed = false
    port                 = 80
  }

  default_route_pools {
    pool {
      name      = volterra_origin_pool.tf_f5xc_pool_ext_nginx.name
      namespace = volterra_origin_pool.tf_f5xc_pool_ext_nginx.namespace
    }
    weight = 1
  }

  advertise_custom {
    advertise_where {
      virtual_site_with_vip {
        network = "SITE_NETWORK_SPECIFIED_VIP_OUTSIDE"
        virtual_site {
          name      = volterra_virtual_site.tf_f5xc_vsite.name
          namespace = volterra_virtual_site.tf_f5xc_vsite.namespace
        }
        ip = var.f5xc_lb_nginx_vip
      }
      use_default_port = true
    }
  }
}
