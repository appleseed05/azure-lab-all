###############################################################################
# Terraform and provider configuration
###############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.0"
    }
    volterra = {
      source  = "volterraedge/volterra"
      version = "~>0.11.46"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.7"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_sub_id
  tenant_id       = var.azure_tenant_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
}

provider "volterra" {
  # Resolved against the module directory, not the shell working directory,
  # so the p12 must sit in the project folder alongside the .tf files.
  api_p12_file = "${path.module}/${var.f5xc_api_p12_file}"
  url          = var.f5xc_api_url
}
