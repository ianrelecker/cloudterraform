# main.tf
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.113"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "azure-ai-openai.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region for the OpenAI account (must support Azure OpenAI)"
  type        = string
  default     = "eastus2"
}

# --- Basics --------------------------------------------------------

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-openai-${random_string.suffix.result}"
  location = var.location
}

# Azure OpenAI account (pay-as-you-go account layer)
resource "azurerm_cognitive_account" "openai" {
  name                = "cog-openai-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  kind     = "OpenAI"  # This makes it an Azure OpenAI account
  sku_name = "S0"      # Account SKU is S0; usage is billed per-token at the deployment level

  # "Super basic": public network + key auth on so you can grab a key easily.
  public_network_access_enabled = true
  local_auth_enabled            = true

  tags = {
    env  = "dev"
    cost = "payg"
  }
}

# Model deployment (token-metered, only pay for what you use)
# Choose GlobalStandard for the simple, burst-friendly on-demand option.
resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini-gs"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18" # GA version; adjust as Microsoft updates models
  }

  sku {
    # PAYG deployment types include Standard (regional) and GlobalStandard (globally routed).
    # GlobalStandard is a great default: high default quota, pay-per-token.
    name = "GlobalStandard"
  }
}

# --- Handy outputs -------------------------------------------------

output "openai_endpoint" {
  description = "Base endpoint for the account"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "API key (requires local_auth_enabled = true)"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o_mini.name
}
