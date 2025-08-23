# -------------------------------------------------
# Backend Configuration (stores Terraform state in Azure)
# -------------------------------------------------
terraform {
  backend "azurerm" {
    resource_group_name   = "rg-aravind-tfstate"
    storage_account_name  = "stgaravindtfstate01"
    container_name        = "tfstate"
    key                   = "terraform.tfstate"
  }
}

# -------------------------------------------------
# Resource Group
# -------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-aravind-datavault"
  location = var.location

  tags = {
    environment = "dev"
    owner       = var.owner_name
  }
}

# -------------------------------------------------
# Virtual Network & Subnets
# -------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aravind-datavault"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/20"]

  tags = {
    owner = var.owner_name
  }
}

resource "azurerm_subnet" "backend" {
  name                 = "sn-backend"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_subnet" "jumphost" {
  name                 = "sn-jumphost"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "hpc" {
  name                 = "sn-hpc"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

# -------------------------------------------------
# Network Security Groups
# -------------------------------------------------
resource "azurerm_network_security_group" "nsg_backend" {
  name                = "nsg-backend"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Deny-Internet-All"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_network_security_group" "nsg_jumphost" {
  name                = "nsg-jumphost"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "assoc_backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.nsg_backend.id
}

resource "azurerm_subnet_network_security_group_association" "assoc_jumphost" {
  subnet_id                 = azurerm_subnet.jumphost.id
  network_security_group_id = azurerm_network_security_group.nsg_jumphost.id
}

# -------------------------------------------------
# Storage Account
# -------------------------------------------------
resource "azurerm_storage_account" "stg" {
  name                     = "stgaravinddatavault"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false
  min_tls_version          = "TLS1_2"

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }

  tags = {
    owner = var.owner_name
  }
}

# -------------------------------------------------
# Key Vault
# -------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-aravind-datavault"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7
  enable_rbac_authorization   = true

  tags = {
    owner = var.owner_name
  }
}

# -------------------------------------------------
# Private DNS & Private Endpoint
# -------------------------------------------------
resource "azurerm_private_dns_zone" "blob_dns" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_dns_link" {
  name                  = "blobdnslink"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "stg_endpoint" {
  name                = "stg-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.backend.id

  private_service_connection {
    name                           = "stg-priv-conn"
    private_connection_resource_id = azurerm_storage_account.stg.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

# -------------------------------------------------
# Log Analytics + Diagnostic Settings
# -------------------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-aravind-datavault"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "storage_diag" {
  name                       = "diag-storage-tftt"
  target_resource_id         = azurerm_storage_account.stg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  metric {
    category = "Transaction"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "kv_diag" {
  name                       = "diag-kv-tftt"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
