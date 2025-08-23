terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110.0"
    }
  }
  backend "azurerm" {
    resource_group_name   = "rg-aravind-tfstate"
    storage_account_name  = "stgaravindtfstate01"
    container_name        = "tfstate"
    key                   = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  skip_provider_registration = true
  use_oidc        = true
  subscription_id = "5b9a55fa-56e0-4847-8260-39eaa4ff49ca"
  tenant_id       = "2e493aa5-02f1-4df8-8b03-4bca3f8d01e2"
  client_id       = "a4c1933e-fcd0-4c01-9b17-22cf8b6b7d2a"
}
