###############################################################################
# F5 XC Known Label (key and value)
###############################################################################

resource "volterra_known_label_key" "tf_f5xc_vsite_label_key" {
  key         = "${var.prefix}-vsite-label-key"
  namespace   = "shared"
  description = "Label key grouping CE sites into Virtual Site"
}

resource "volterra_known_label" "tf_f5xc_vsite_label_value" {
  key         = "${volterra_known_label_key.tf_f5xc_vsite_label_key.key}"
  value       = "${var.prefix}-vsite-label-value"
  namespace   = "shared"
  description = "Label value selecting CE sites for Virtual Site"

  # The key must be registered before its value.
  # depends_on = [volterra_known_label_key.tf_f5xc_vsite_label_key] # Commented since key argument reference existing key resource, the depends_on should not be necessary anymore
}

###############################################################################
# F5 XC SMSv2 site creation
###############################################################################

# site01
resource "volterra_securemesh_site_v2" "tf_f5xc_site_01" {
  name                    = "${var.prefix}-site-01"
  namespace               = "system"
  block_all_services      = false
  logs_streaming_disabled = true
  enable_ha               = false

  labels = {
    "ves.io/provider" = "ves-io-AZURE"
    # Custom label used by the Virtual Site site_selector (defined below).
    # Both CE nodes belong to this single site, so labelling the site adds it
    # as the (single) member of the Virtual Site. The key is registered as a
    # Known Label above.
    "${volterra_known_label_key.tf_f5xc_vsite_label_key.key}" = "${volterra_known_label.tf_f5xc_vsite_label_value.value}"
  }

  lifecycle {
    ignore_changes = [labels]
  }

  # Register the Known Label key/value before tagging the site with it (no-op
  # when var.f5xc_manage_labels = false, i.e. the label is managed elsewhere).
  # depends_on = [volterra_known_label.tf_f5xc_vsite_label_value]

  re_select {
    geo_proximity = true
  }

  azure {
    not_managed {
      node_list {
        hostname = "${var.prefix}-${var.azure_vm_ce01}"
        type     = "Control"
        interface_list {
          ethernet_interface {
            device = "eth0"
            mac    = ""
          }

          name        = "eth0"
          dhcp_client = true
          mtu         = 0
          priority    = 0

          network_option {
            site_local_network = true
          }
        }
        interface_list {
          ethernet_interface {
            device = "eth1"
            mac    = ""
          }

          name        = "eth1"
          dhcp_client = true
          mtu         = 0
          priority    = 0

          network_option {
            site_local_inside_network = true
          }
        }
      }
    }
  }
  tunnel_type = "SITE_TO_SITE_TUNNEL_SSL"
  # in json view of console => "tunnel_type": "SITE_TO_SITE_TUNNEL_SSL"
}

#site02
resource "volterra_securemesh_site_v2" "tf_f5xc_site_02" {
  name                    = "${var.prefix}-site-02"
  namespace               = "system"
  block_all_services      = false
  logs_streaming_disabled = true
  enable_ha               = false

  labels = {
    "ves.io/provider" = "ves-io-AZURE"
    # Custom label used by the Virtual Site site_selector (defined below).
    # Both CE nodes belong to this single site, so labelling the site adds it
    # as the (single) member of the Virtual Site. The key is registered as a
    # Known Label above.
    "${volterra_known_label_key.tf_f5xc_vsite_label_key.key}" = "${volterra_known_label.tf_f5xc_vsite_label_value.value}"
  }

  lifecycle {
    ignore_changes = [labels]
  }

  # Register the Known Label key/value before tagging the site with it (no-op
  # when var.f5xc_manage_labels = false, i.e. the label is managed elsewhere).
  # depends_on = [volterra_known_label.tf_f5xc_vsite_label_value]

  re_select {
    geo_proximity = true
  }

  azure {
    not_managed {
      node_list {
        hostname = "${var.prefix}-${var.azure_vm_ce02}"
        type     = "Control"
        interface_list {
          ethernet_interface {
            device = "eth0"
            mac    = ""
          }

          name        = "eth0"
          dhcp_client = true
          mtu         = 0
          priority    = 0

          network_option {
            site_local_network = true
          }
        }
        interface_list {
          ethernet_interface {
            device = "eth1"
            mac    = ""
          }

          name        = "eth1"
          dhcp_client = true
          mtu         = 0
          priority    = 0

          network_option {
            site_local_inside_network = true
          }
        }
      }
    }
  }
  tunnel_type = "SITE_TO_SITE_TUNNEL_SSL"
  # in json view of console => "tunnel_type": "SITE_TO_SITE_TUNNEL_SSL"
}

/*

###############################################################################
# F5 XC SMSv2 site token
###############################################################################

resource "volterra_token" "tf_f5xc_site_token01" {
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_site_01]
  name       = var.f5xc_site_token01
  namespace  = "system"
  type       = 1
  site_name  = volterra_securemesh_site_v2.tf_f5xc_smsv2-site-01.name
}

resource "volterra_token" "tf_f5xc_site_token02" {
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_site_02]
  name       = var.f5xc_site_token02
  namespace  = "system"
  type       = 1
  site_name  = volterra_securemesh_site_v2.tf_f5xc_smsv2-site-02.name
}

###############################################################################
# F5 XC CE Cloud Init
###############################################################################

# original token in cloud-init config data:
# token: ${replace(volterra_token.tf_f5xc_smsv2-site-token.id, "id=", "")}

data "cloudinit_config" "tf_f5xc_ce_config" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      write_files = [
        {
          path        = "/etc/vpm/user_data"
          permissions = "0644"
          owner       = "root"
          content     = <<-EOT
            token: "${trimprefix(volterra_token.tf_f5xc_smsv2-site-token.id, "id=")}"
          EOT
        }
      ]
    })
  }
}
*/

###############################################################################
# F5 XC Virtual Site creation
###############################################################################

# A Virtual Site is a label-based grouping of Sites (not of individual CE
# nodes). The two CE VMs (ce01 / ce02) share one site token, so they are two
# nodes of the SINGLE Secure Mesh Site defined above. That site is tagged with
# the custom label "<f5xc_label-key> = <f5xc_vsite-name>" and selected here.
#
# Ref: https://docs.cloud.f5.com/docs-v2/multi-cloud-app-connect/how-to/app-nw/create-virtual-site

resource "volterra_virtual_site" "tf_f5xc_vsite" {
  name      = "${var.prefix}-vsite"
  namespace = "shared"
  site_type = "CUSTOMER_EDGE"

  # Selects every CE Site carrying the label key with this value.
  # The key comes from the same variable used for the site label and the
  # Known Label, so all three stay in sync.
  site_selector {
    expressions = ["${volterra_known_label_key.tf_f5xc_vsite_label_key.key} in (${volterra_known_label.tf_f5xc_vsite_label_value.value})"]
  }

  labels = {
    "ves.io/provider" = "ves-io-AZURE"
  }

  # Ensure the Site (and its label) exists before the Virtual Site references it.
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_site_01, volterra_securemesh_site_v2.tf_f5xc_site_02]
}
