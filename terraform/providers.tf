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
      source = "volterraedge/volterra"
      version = "0.11.46"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
      version = ">= 2.3.7"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_sub-id
  tenant_id       = var.azure_tenant-id
  client_id       = var.azure_client-id
  client_secret   = var.azure_client-secret
}

provider "volterra" {
  api_p12_file     = var.f5xc_api-p12-file
  url              = var.f5xc_api-url
}
