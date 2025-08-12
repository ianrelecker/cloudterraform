terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "aifoundry.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"            { default = "aifoundry" }
variable "location"          { default = "eastus" }
variable "environment"       { default = "prod" }
variable "project_name"      { default = "aifoundry" }

# AI Foundry specific variables
variable "workspace_name"    { default = "ai-foundry-workspace" }
variable "hub_name"          { default = "ai-foundry-hub" }
variable "storage_account_name" { 
  description = "Storage account name for AI Foundry (must be globally unique)"
  type        = string
  default     = "aifoundrystorage"
}
variable "key_vault_name" {
  description = "Key Vault name for AI Foundry (must be globally unique)"
  type        = string
  default     = "aifoundry-kv"
}

# GPT-5 and OSS120B configuration
variable "enable_gpt5" {
  description = "Enable GPT-5 deployment"
  type        = bool
  default     = true
}
variable "enable_oss120b" {
  description = "Enable OSS120B model deployment for MAAS"
  type        = bool
  default     = true
}
variable "create_dev_instance" {
  description = "Create optional development compute instance"
  type        = bool
  default     = false
}

# Networking
variable "vnet_cidr"         { default = "10.100.0.0/16" }
variable "subnet_cidr"       { default = "10.100.1.0/24" }
variable "allowed_ip_ranges" { 
  description = "Allowed IP ranges for access"
  type        = list(string)
  default     = ["0.0.0.0/0"] 
}

# Read configuration from YAML file
locals {
  config_file = "${path.module}/aifoundry-config.yaml"
  raw_config = fileexists(local.config_file) ? yamldecode(file(local.config_file)) : null
  
  name_prefix = "${try(local.raw_config.project_name, var.project_name)}-${try(local.raw_config.environment, var.environment)}"
  
  # Merge YAML config with variables, YAML takes precedence
  location = try(local.raw_config.location, var.location)
  workspace_name = try(local.raw_config.ai_foundry.workspace_name, var.workspace_name)
  hub_name = try(local.raw_config.ai_foundry.hub_name, var.hub_name)
  storage_account_name = try(local.raw_config.storage.account_name, var.storage_account_name)
  key_vault_name = try(local.raw_config.security.key_vault_name, var.key_vault_name)
  vnet_cidr = try(local.raw_config.network.vnet_cidr, var.vnet_cidr)
  subnet_cidr = try(local.raw_config.network.subnet_cidr, var.subnet_cidr)
  allowed_ip_ranges = try(local.raw_config.security.allowed_ip_ranges, var.allowed_ip_ranges)
  enable_gpt5 = try(local.raw_config.models.gpt5.enabled, var.enable_gpt5)
  enable_oss120b = try(local.raw_config.models.oss120b.enabled, var.enable_oss120b)
}

# ----------------- Data Sources -----------------
data "azurerm_client_config" "current" {}

# ----------------- Resource Group -----------------
resource "azurerm_resource_group" "rg" {
  name     = "${local.name_prefix}-rg"
  location = local.location
}

# ----------------- Storage Account -----------------
resource "azurerm_storage_account" "ai_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 1
    }
    container_delete_retention_policy {
      days = 1
    }
    change_feed_enabled = false
    last_access_time_enabled = false
  }
  
  lifecycle {
    prevent_destroy = false
  }
}

# ----------------- Key Vault -----------------
resource "azurerm_key_vault" "ai_vault" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  
  lifecycle {
    prevent_destroy = false
  }
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
      "Set",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

# ----------------- Application Insights -----------------
resource "azurerm_application_insights" "ai_insights" {
  name                = "${local.name_prefix}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  retention_in_days   = 30
  
  lifecycle {
    prevent_destroy = false
  }
}

# ----------------- Network -----------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [local.vnet_cidr]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${local.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnet_cidr]
  
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name_prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = local.allowed_ip_ranges
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = local.allowed_ip_ranges
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ----------------- AI Foundry Hub -----------------
resource "azurerm_machine_learning_workspace" "ai_hub" {
  name                    = local.hub_name
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.ai_insights.id
  key_vault_id            = azurerm_key_vault.ai_vault.id
  storage_account_id      = azurerm_storage_account.ai_storage.id
  
  identity {
    type = "SystemAssigned"
  }
  
  public_network_access_enabled = true
  
  description = "AI Foundry Hub for GPT-5 and OSS120B MAAS deployment"
  
  lifecycle {
    prevent_destroy = false
  }
}

# ----------------- AI Foundry Workspace -----------------
resource "azurerm_machine_learning_workspace" "ai_workspace" {
  name                    = local.workspace_name
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.ai_insights.id
  key_vault_id            = azurerm_key_vault.ai_vault.id
  storage_account_id      = azurerm_storage_account.ai_storage.id
  container_registry_id   = azurerm_container_registry.ai_registry.id
  
  identity {
    type = "SystemAssigned"
  }
  
  public_network_access_enabled = true
  
  description = "AI Foundry Workspace for model deployments"
  
  lifecycle {
    prevent_destroy = false
  }
}

# ----------------- Serverless Compute Configuration -----------------
# Note: Azure ML provides serverless compute automatically - no explicit resource creation needed
# Serverless compute is managed by Azure ML and scales on-demand with zero idle costs

# Optional: Compute Instance for development/testing (can be disabled in production)
resource "azurerm_machine_learning_compute_instance" "dev_instance" {
  count                         = var.create_dev_instance ? 1 : 0
  name                          = "dev-instance"
  machine_learning_workspace_id = azurerm_machine_learning_workspace.ai_workspace.id
  virtual_machine_size          = "Standard_DS3_v2"
  
  assign_to_user {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
  }
  
  description = "Development compute instance (optional)"
  
  lifecycle {
    prevent_destroy = false
  }
}

# Serverless compute for GPT-5 and OSS120B is handled automatically by Azure ML
# No additional compute resources needed - Azure ML manages scaling and billing

# ----------------- Model Datastores -----------------
# GPT-5 Model Datastore (using blob storage)
resource "azurerm_machine_learning_datastore_blobstorage" "model_store" {
  count                = local.enable_gpt5 ? 1 : 0
  name                 = "gpt5-model-store"
  workspace_id         = azurerm_machine_learning_workspace.ai_workspace.id
  storage_container_id = azurerm_storage_container.models.resource_manager_id
  account_key          = azurerm_storage_account.ai_storage.primary_access_key
  
  description = "Data store for GPT-5 model artifacts"
  
  lifecycle {
    prevent_destroy = false
  }
}

# OSS120B Model Datastore for MAAS (using blob storage)
resource "azurerm_machine_learning_datastore_blobstorage" "oss120b_store" {
  count                = local.enable_oss120b ? 1 : 0
  name                 = "oss120b-model-store"
  workspace_id         = azurerm_machine_learning_workspace.ai_workspace.id
  storage_container_id = azurerm_storage_container.oss120b.resource_manager_id
  account_key          = azurerm_storage_account.ai_storage.primary_access_key
  
  description = "Data store for OSS120B model artifacts for MAAS"
  
  lifecycle {
    prevent_destroy = false
  }
}

# ----------------- Storage Containers -----------------
resource "azurerm_storage_container" "models" {
  name                  = "models"
  storage_account_name  = azurerm_storage_account.ai_storage.name
  container_access_type = "private"
  
  lifecycle {
    prevent_destroy = false
  }
}

resource "azurerm_storage_container" "oss120b" {
  name                  = "oss120b"
  storage_account_name  = azurerm_storage_account.ai_storage.name
  container_access_type = "private"
  
  lifecycle {
    prevent_destroy = false
  }
}

# Ensure all blob data is deleted before destroy
resource "azurerm_storage_management_policy" "cleanup_policy" {
  storage_account_id = azurerm_storage_account.ai_storage.id
  
  rule {
    name    = "cleanup-policy"
    enabled = true
    
    filters {
      prefix_match = [""]  # Apply to all blobs
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 1
      }
      version {
        delete_after_days_since_creation = 1
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 1
      }
    }
  }
}

# ----------------- Container Registry (often orphaned) -----------------
resource "azurerm_container_registry" "ai_registry" {
  name                = "${replace(local.name_prefix, "-", "")}registry"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  
  lifecycle {
    prevent_destroy = false
  }
}

# Cleanup resources to prevent orphaned billing
resource "terraform_data" "cleanup_warning" {
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'WARNING: Destroying AI Foundry infrastructure. Check Azure portal for any remaining: model endpoints, deployments, AKS clusters, or orphaned compute resources.'"
  }
}

# --------------- Output ---------------
output "resource_group_name" { 
  value = azurerm_resource_group.rg.name 
}
output "ai_hub_name" { 
  value = azurerm_machine_learning_workspace.ai_hub.name 
}
output "ai_workspace_name" { 
  value = azurerm_machine_learning_workspace.ai_workspace.name 
}
output "storage_account_name" { 
  value = azurerm_storage_account.ai_storage.name 
}
output "key_vault_name" { 
  value = azurerm_key_vault.ai_vault.name 
}
output "dev_instance_name" { 
  value = var.create_dev_instance ? azurerm_machine_learning_compute_instance.dev_instance[0].name : "serverless-only"
}
output "workspace_url" {
  value = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.ai_workspace.name}"
}

output "container_registry_name" { 
  value = azurerm_container_registry.ai_registry.name 
}

# Cost monitoring outputs
output "cost_optimization_notes" {
  value = <<EOT
IMPORTANT COST CONSIDERATIONS:
1. Using Azure ML serverless compute - no idle compute costs, pay only for actual inference time
2. Storage has aggressive lifecycle policies (1-day retention)
3. Key Vault has soft delete disabled for complete cleanup
4. Container Registry included and managed by Terraform
5. Application Insights retention set to 30 days minimum
6. Optional dev compute instance disabled by default (set create_dev_instance=true to enable)
7. MANUAL CLEANUP REQUIRED: Check Azure portal after destroy for:
   - Model endpoints/deployments (not managed by Terraform)
   - AKS clusters (if created outside Terraform)
   - Any orphaned compute instances
8. Run 'terraform destroy' to remove all infrastructure resources
9. Serverless compute automatically scales to zero when not in use

RESOURCES MANAGED BY TERRAFORM (will be deleted on destroy):
✓ Resource Group      ✓ Storage Account     ✓ Key Vault
✓ Container Registry  ✓ Application Insights ✓ Virtual Network
✓ ML Hub & Workspace  ✓ Dev Instance (if enabled)
EOT
}