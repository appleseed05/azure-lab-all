###############################################################################
# F5 XC BGP config CE 01
###############################################################################
# Peering: CE01 SLO <-> VyOS eth1
# BGP is an infrastructure object: it MUST live in "system" namespace, not in individual namespace.
# One volterra_bgp object per site. To add a 2nd router later, add a 2nd
# "peers" block inside THIS resource - do not create a second resource.

resource "volterra_bgp" "tf_f5xc_bgp01" {
  name        = "${var.prefix}-bgp-ce01"
  namespace   = "system"
  description = "eBGP CE SLO (${var.f5xc_bgp_asn}) <-> VyOS ${var.azure_nic_rtr_ext_ip_addr} (${var.router_bgp_asn}) - advertises LB VIP /32"

  bgp_parameters {
    asn = var.f5xc_bgp_asn # 65100

    # oneof: from_site | ip_address | local_address
    local_address = true

    # bgp_router_id { ipv4 { addr = "..." } }  # optional, omitted on purpose
  }

  where {
    # oneof: site | virtual_site  -> "site" because this object is in "system"
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL" # SLO = subnet "external"

      # oneof: disable_internet_vip | enable_internet_vip  (mandatory)
      disable_internet_vip = true

      ref {
        name      = volterra_securemesh_site_v2.tf_f5xc_site_01.name
        namespace = "system"
      }
    }
  }

  peers {
    metadata {
      name        = "${var.prefix}-bgp-vyos-ext"
      description = "VyOS 1.5 router, eth1 in subnet external"
      disable     = false # <- THIS is the peer admin state
    }

    # oneof: bfd_disabled | bfd_enabled
    bfd_disabled = true

    # oneof: passive_mode_disabled | passive_mode_enabled
    passive_mode_disabled = true

    # oneof: disable | routing_policies
    # "disable" here means "no routing policies on this peer"
    disable = true

    external {
      # oneof (IPv4 peer address): address | default_gateway | disable |
      #   external_connector | from_site | subnet_begin_offset | subnet_end_offset
      address = azurerm_network_interface.tf_azure_nic_rtr_ext.ip_configuration[0].private_ip_address # 10.1.10.254 var.azure_nic_rtr_ext_ip_addr

      # oneof (IPv6 peer address): disable_v6 => no IPv6 peering
      disable_v6 = true

      asn  = var.router_bgp_asn # 65001
      port = 179

      # oneof: md5_auth_key | no_authentication  (optional but explicit)
      no_authentication = true

      # oneof: inside_interfaces | interface | interface_list | outside_interfaces
      # outside_interfaces = true
/*
      family_inet {
        # oneof: disable | enable
        enable = true
      }
      # family_inet_v6 omitted (no IPv6)
*/
      interface {
        namespace = "system"
        name      = "ves-io-securemesh-site-v2-${volterra_securemesh_site_v2.tf_f5xc_site_01.name}-network-${azurerm_linux_virtual_machine.tf_azure_vm_xc_ce01.name}-eth0-0" # "ves-io-securemesh-site-v2-${var.f5xc_site_name01}-network-${var.azure_vm_xc_ce01}-eth0-0"
      }
    }
  }

  # depends_on = [volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name]
}


###############################################################################
# F5 XC BGP config CE 02
###############################################################################
# Peering: CE02 SLO <-> VyOS eth1
# BGP is an infrastructure object: it MUST live in "system" namespace, not in individual namespace.
# One volterra_bgp object per site. To add a 2nd router later, add a 2nd
# "peers" block inside THIS resource - do not create a second resource.

resource "volterra_bgp" "tf_f5xc_bgp02" {
  name        = "${var.prefix}-bgp-ce02"
  namespace   = "system"
  description = "eBGP CE SLO (${var.f5xc_bgp_asn}) <-> VyOS ${var.azure_nic_rtr_ext_ip_addr} (${var.router_bgp_asn}) - advertises LB VIP /32"

  bgp_parameters {
    asn = var.f5xc_bgp_asn # 65100

    # oneof: from_site | ip_address | local_address
    local_address = true

    # bgp_router_id { ipv4 { addr = "..." } }  # optional, omitted on purpose
  }

  where {
    # oneof: site | virtual_site  -> "site" because this object is in "system"
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL" # SLO = subnet "external"

      # oneof: disable_internet_vip | enable_internet_vip  (mandatory)
      disable_internet_vip = true

      ref {
        name      = volterra_securemesh_site_v2.tf_f5xc_site_02.name
        namespace = "system"
      }
    }
  }

  peers {
    metadata {
      name        = "${var.prefix}-bgp-vyos-ext"
      description = "VyOS 1.5 router, eth1 in subnet external"
      disable     = false # <- THIS is the peer admin state
    }

    # oneof: bfd_disabled | bfd_enabled
    bfd_disabled = true

    # oneof: passive_mode_disabled | passive_mode_enabled
    passive_mode_disabled = true

    # oneof: disable | routing_policies
    # "disable" here means "no routing policies on this peer"
    disable = true

    external {
      # oneof (IPv4 peer address): address | default_gateway | disable |
      #   external_connector | from_site | subnet_begin_offset | subnet_end_offset
      address = azurerm_network_interface.tf_azure_nic_rtr_ext.ip_configuration[0].private_ip_address # 10.1.10.254 var.azure_nic_rtr_ext_ip_addr

      # oneof (IPv6 peer address): disable_v6 => no IPv6 peering
      disable_v6 = true

      asn  = var.router_bgp_asn # 65001
      port = 179

      # oneof: md5_auth_key | no_authentication  (optional but explicit)
      no_authentication = true

      # oneof: inside_interfaces | interface | interface_list | outside_interfaces
      # outside_interfaces = true
/*
      family_inet {
        # oneof: disable | enable
        enable = true
      }
      # family_inet_v6 omitted (no IPv6)
*/
      interface {
        namespace = "system"
        name      = "ves-io-securemesh-site-v2-${volterra_securemesh_site_v2.tf_f5xc_site_02.name}-network-${azurerm_linux_virtual_machine.tf_azure_vm_xc_ce02.name}-eth0-0" # "ves-io-securemesh-site-v2-${var.f5xc_site_name01}-network-${var.azure_vm_xc_ce01}-eth0-0" # "ves-io-securemesh-site-v2-${var.f5xc_site_name02}-network-${var.azure_vm_xc_ce02}-eth0-0"
      }
    }
  }

  # depends_on = [volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name]
}
