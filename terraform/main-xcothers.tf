##########################
### F5 XC namespace ID ###
##########################

data "volterra_namespace" "tf_f5xc_namespace-name" {
  name = var.f5xc_namespace-name
}
