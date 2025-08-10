terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "networking.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "networking-rg"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westus3"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "network"
}

variable "on_premises_gateway_fqdn" {
  description = "FQDN or public IP of the on-premises VPN gateway"
  type        = string
  default     = "vpn.example.com"
}

variable "on_premises_address_spaces" {
  description = "Address spaces of the on-premises network"
  type        = list(string)
  default     = ["10.0.0.0/16", "192.168.0.0/24"]
}


variable "public_ip_sku" {
  description = "SKU for the public IP address"
  type        = string
  default     = "Standard"
}

variable "public_ip_idle_timeout" {
  description = "Idle timeout in minutes for the public IP"
  type        = number
  default     = 4
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.100.0.0/16"]
}

variable "custom_dns_servers" {
  description = "Custom DNS servers for the virtual network"
  type        = list(string)
  default     = []
}

variable "workload_subnet_prefixes" {
  description = "Address prefixes for the workload subnet"
  type        = list(string)
  default     = ["10.100.1.0/24"]
}

variable "gateway_subnet_prefixes" {
  description = "Address prefixes for the gateway subnet"
  type        = list(string)
  default     = ["10.100.255.0/27"]
}

variable "vpn_gateway_type" {
  description = "Type of the VPN gateway (Vpn or ExpressRoute)"
  type        = string
  default     = "Vpn"
}

variable "vpn_type" {
  description = "VPN routing type (RouteBased or PolicyBased)"
  type        = string
  default     = "RouteBased"
}

variable "vpn_gateway_sku" {
  description = "SKU of the VPN gateway"
  type        = string
  default     = "VpnGw1"
}

variable "vpn_gateway_generation" {
  description = "Generation of the VPN gateway"
  type        = string
  default     = "Generation1"
}

variable "bgp_autonomous_system_number" {
  description = "BGP Autonomous System Number"
  type        = number
  default     = 65515
}

variable "bgp_peer_weight" {
  description = "Weight for BGP peer"
  type        = number
  default     = 0
}

variable "connection_protocol" {
  description = "VPN connection protocol (IKEv1 or IKEv2)"
  type        = string
  default     = "IKEv2"
}

variable "connection_routing_weight" {
  description = "Routing weight for the VPN connection"
  type        = number
  default     = 0
}

variable "dpd_timeout_seconds" {
  description = "Dead Peer Detection timeout in seconds"
  type        = number
  default     = 45
}

variable "enable_bgp" {
  description = "Enable BGP for the VPN connection"
  type        = bool
  default     = false
}

variable "shared_key" {
  description = "Shared key for the VPN connection"
  type        = string
  sensitive   = true
}

# ----------------- Data Sources -----------------
# Read configuration from YAML file
locals {
  config_file = "${path.module}/vpn-config.yaml"
  raw_config = fileexists(local.config_file) ? yamldecode(file(local.config_file)) : null
  
  name_prefix = "${try(local.raw_config.project_name, var.project_name)}-${try(local.raw_config.environment, var.environment)}"
  
  # Merge YAML config with variables, YAML takes precedence
  resource_group_name = try(local.raw_config.resource_group_name, var.resource_group_name)
  location = try(local.raw_config.location, var.location)
  on_premises_gateway_fqdn = try(local.raw_config.on_premises.gateway_fqdn, var.on_premises_gateway_fqdn)
  on_premises_address_spaces = try(local.raw_config.on_premises.address_spaces, var.on_premises_address_spaces)
  vnet_address_space = try(local.raw_config.network.vnet_address_space, var.vnet_address_space)
  custom_dns_servers = try(local.raw_config.network.custom_dns_servers, var.custom_dns_servers)
  workload_subnet_prefixes = try(local.raw_config.network.workload_subnet_prefixes, var.workload_subnet_prefixes)
  gateway_subnet_prefixes = try(local.raw_config.network.gateway_subnet_prefixes, var.gateway_subnet_prefixes)
  public_ip_sku = try(local.raw_config.public_ip.sku, var.public_ip_sku)
  public_ip_idle_timeout = try(local.raw_config.public_ip.idle_timeout, var.public_ip_idle_timeout)
  vpn_gateway_type = try(local.raw_config.vpn_gateway.type, var.vpn_gateway_type)
  vpn_type = try(local.raw_config.vpn_gateway.vpn_type, var.vpn_type)
  vpn_gateway_sku = try(local.raw_config.vpn_gateway.sku, var.vpn_gateway_sku)
  vpn_gateway_generation = try(local.raw_config.vpn_gateway.generation, var.vpn_gateway_generation)
  enable_bgp = try(local.raw_config.vpn_gateway.enable_bgp, var.enable_bgp)
  bgp_autonomous_system_number = try(local.raw_config.vpn_gateway.bgp.autonomous_system_number, var.bgp_autonomous_system_number)
  bgp_peer_weight = try(local.raw_config.vpn_gateway.bgp.peer_weight, var.bgp_peer_weight)
  connection_protocol = try(local.raw_config.connection.protocol, var.connection_protocol)
  connection_routing_weight = try(local.raw_config.connection.routing_weight, var.connection_routing_weight)
  dpd_timeout_seconds = try(local.raw_config.connection.dpd_timeout_seconds, var.dpd_timeout_seconds)
  shared_key = try(local.raw_config.connection.shared_key, var.shared_key)
}

# ----------------- Resources -----------------
resource "azurerm_local_network_gateway" "on_premises" {
  name                = "${local.name_prefix}-lng"
  resource_group_name = local.resource_group_name
  location            = local.location
  
  gateway_fqdn = local.on_premises_gateway_fqdn
  
  address_space = local.on_premises_address_spaces
}

resource "azurerm_network_security_group" "workload" {
  name                = "${local.name_prefix}-nsg"
  resource_group_name = local.resource_group_name
  location            = local.location
}


resource "azurerm_public_ip" "vpn_gateway" {
  name                = "${local.name_prefix}-vpngw-pip"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static"
  sku                 = local.public_ip_sku
  sku_tier           = "Regional"
  ip_version         = "IPv4"
  idle_timeout_in_minutes = local.public_ip_idle_timeout
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = local.resource_group_name
  location            = local.location
  address_space       = local.vnet_address_space
  
  dns_servers = length(local.custom_dns_servers) > 0 ? local.custom_dns_servers : null
}

resource "azurerm_subnet" "workload" {
  name                 = "workload-subnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = local.workload_subnet_prefixes
  
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = local.gateway_subnet_prefixes
  
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}

resource "azurerm_virtual_network_gateway" "main" {
  name                = "${local.name_prefix}-vpngw"
  resource_group_name = local.resource_group_name
  location            = local.location
  
  type     = local.vpn_gateway_type
  vpn_type = local.vpn_type
  
  active_active = false
  enable_bgp    = local.enable_bgp
  
  sku = local.vpn_gateway_sku
  generation = local.vpn_gateway_generation
  
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
  
  bgp_settings {
    asn         = local.bgp_autonomous_system_number
    peer_weight = local.bgp_peer_weight
  }
}

resource "azurerm_virtual_network_gateway_connection" "site_to_site" {
  name                = "${local.name_prefix}-s2s-connection"
  resource_group_name = local.resource_group_name
  location            = local.location
  
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.on_premises.id
  
  shared_key              = local.shared_key
  connection_protocol     = local.connection_protocol
  routing_weight          = local.connection_routing_weight
  enable_bgp              = local.enable_bgp
  use_policy_based_traffic_selectors = false
  dpd_timeout_seconds     = local.dpd_timeout_seconds
}

# --------------- Output ---------------
output "vpn_gateway_public_ip" { 
  value = azurerm_public_ip.vpn_gateway.ip_address 
  description = "Public IP address of the VPN gateway"
}
output "virtual_network_id" { 
  value = azurerm_virtual_network.main.id 
  description = "ID of the virtual network"
}
output "workload_subnet_id" { 
  value = azurerm_subnet.workload.id 
  description = "ID of the workload subnet"
}