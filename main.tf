# -------------------
# Resource Group
# -------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-aravind-datavault"
  location = "East US"

  tags = {
    environment = "dev"
    owner       = "aravind"
  }
}

# -------------------
# Networking (VNet, Subnets, NSGs)
# -------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aravind-datavault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/20"]

  tags = {
    owner = "aravind"
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

resource "azurerm_network_security_group" "nsg_backend" {
  name                = "nsg-backend"
  location            = azurerm_resource_group.rg.location
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
  location            = azurerm_resource_group.rg.location
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

# -------------------
# Storage Account
# -------------------
resource "azurerm_storage_account" "stg" {
  name                     = "stgaravinddatavault"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
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
    owner = "aravind"
  }
}

# -------------------
# Key Vault
# -------------------
resource "azurerm_key_vault" "kv" {
  name                        = "kv-aravind-datavault"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7
  enable_rbac_authorization   = true

  tags = {
    owner = "aravind"
  }
}

# -------------------
# Private Endpoints + DNS
# -------------------
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
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.backend.id

  private_service_connection {
    name                           = "stg-priv-conn"
    private_connection_resource_id = azurerm_storage_account.stg.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone_group" "stg_dns_group" {
  name                = "stg-dns-group"
  private_endpoint_id = azurerm_private_endpoint.stg_endpoint.id

  private_dns_zone_ids = [
    azurerm_private_dns_zone.blob_dns.id
  ]
}

# -------------------
# Log Analytics + Diagnostics
# -------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-aravind-datavault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "storage_diag" {
  name                       = "diag-storage"
  target_resource_id         = azurerm_storage_account.stg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}


resource "azurerm_monitor_diagnostic_setting" "kv_diag" {
  name                       = "diag-kv"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
