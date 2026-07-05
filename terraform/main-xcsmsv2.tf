#########################################
### F5 XC Known Label (key and value) ###
#########################################

# Registers the custom label used to group CE sites into the Virtual Site as a
# first-class "Known Label" in the tenant (Shared Configuration > Labels).
# Known Labels must live in the "shared" namespace (the API rejects any other,
# including "system").
#
# NOTE on "does it already exist?": the volterra provider has no data source for
# labels, so Terraform cannot look one up and conditionally skip. Behaviour is
# controlled by var.f5xc_manage-labels:
#   * true  (default) -> Terraform creates and owns the key/value. If they
#                        ALREADY exist in the tenant, apply fails with an
#                        "already exists" error; either set the flag to false or
#                        import them once (see README).
#   * false           -> Terraform does not touch them; assumes they pre-exist.
# Setting an arbitrary label on a site does not require the key to be registered
# first, so disabling this only removes the console typeahead/validation nicety.

resource "volterra_known_label_key" "tf_f5xc_vsite-label-key" {
  count       = var.f5xc_manage-labels ? 1 : 0
  key         = var.f5xc_vsite-label-key
  namespace   = "shared"
  description = "Label key grouping CE sites into Virtual Site ${var.f5xc_vsite-name}"
}

resource "volterra_known_label" "tf_f5xc_vsite-label-value" {
  count       = var.f5xc_manage-labels ? 1 : 0
  key         = var.f5xc_vsite-label-key
  value       = var.f5xc_vsite-name
  namespace   = "shared"
  description = "Label value selecting CE sites for Virtual Site ${var.f5xc_vsite-name}"

  # The key must be registered before its value.
  depends_on = [volterra_known_label_key.tf_f5xc_vsite-label-key]
}

#################################
### F5 XC SMSv2 site creation ###
#################################

resource "volterra_securemesh_site_v2" "tf_f5xc_smsv2-site-name" {
  name                    = var.f5xc_smsv2-site-name
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
    (var.f5xc_vsite-label-key) = var.f5xc_vsite-name
  }

  # Register the Known Label key/value before tagging the site with it (no-op
  # when var.f5xc_manage-labels = false, i.e. the label is managed elsewhere).
  depends_on = [volterra_known_label.tf_f5xc_vsite-label-value]

  re_select {
    geo_proximity = true
  }

  azure {
    not_managed {}
  }
  tunnel_type = "SITE_TO_SITE_TUNNEL_SSL"
  # in json view of console => "tunnel_type": "SITE_TO_SITE_TUNNEL_SSL"
}


##############################
### F5 XC SMSv2 site token ###
##############################

resource "volterra_token" "tf_f5xc_smsv2-site-token" {
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name]
  name       = var.f5xc_smsv2-site-token
  namespace  = "system"
  type       = 1
  site_name  = volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name.name
}

###########################
### F5 XC CE Cloud Init ###
###########################

# original token in cloud-init config data:
# token: ${replace(volterra_token.tf_f5xc_smsv2-site-token.id, "id=", "")}

data "cloudinit_config" "tf_f5xc_ce-config" {
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

###################################
### F5 XC Virtual Site creation ###
###################################

# A Virtual Site is a label-based grouping of Sites (not of individual CE
# nodes). The two CE VMs (ce01 / ce02) share one site token, so they are two
# nodes of the SINGLE Secure Mesh Site defined above. That site is tagged with
# the custom label "<f5xc_vsite-label-key> = <f5xc_vsite-name>" and selected here.
#
# Ref: https://docs.cloud.f5.com/docs-v2/multi-cloud-app-connect/how-to/app-nw/create-virtual-site

resource "volterra_virtual_site" "tf_f5xc_vsite" {
  name      = var.f5xc_vsite-name
  namespace = var.f5xc_vsite-namespace
  site_type = "CUSTOMER_EDGE"

  # Selects every CE Site carrying the label key with this value.
  # The key comes from the same variable used for the site label and the
  # Known Label, so all three stay in sync.
  site_selector {
    expressions = ["${var.f5xc_vsite-label-key} in (${var.f5xc_vsite-name})"]
  }

  labels = {
    "ves.io/provider" = "ves-io-AZURE"
  }

  # Ensure the Site (and its label) exists before the Virtual Site references it.
  depends_on = [volterra_securemesh_site_v2.tf_f5xc_smsv2-site-name]
}
