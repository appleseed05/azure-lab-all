# This part is totally optional and just for test purpose.
# It can be removed without any impact on the rest of the project.

###############################################################################
# F5 XC namespace ID
###############################################################################

data "volterra_namespace" "tf_f5xc_namespace_name" {
  name = var.f5xc_namespace_name
}
