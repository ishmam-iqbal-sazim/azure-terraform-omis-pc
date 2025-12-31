# =============================================================================
# OMIS Product Configurator - Production Environment
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Uses Azure CLI authentication by default
}

# =============================================================================
# Local Variables
# =============================================================================
locals {
  project_name = "omis-pc"
  environment  = "prod"
  name_prefix  = "${local.project_name}-${local.environment}"
  subnet_name  = "${local.name_prefix}-vm-subnet"

  common_tags = {
    Project     = "OMIS Product Configurator"
    Environment = local.environment
    ManagedBy   = "Terraform"
  }

  # Security rules for the application
  security_rules = [
    {
      name                       = "SSH"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "HTTP"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "HTTPS"
      priority                   = 1002
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "Frontend"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3000"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "Backend-HTTP"
      priority                   = 1011
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5000"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "Backend-WebSocket"
      priority                   = 1012
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5001"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# =============================================================================
# Resource Group
# =============================================================================
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

# =============================================================================
# Virtual Network
# =============================================================================
module "vnet" {
  source = "../../../modules/azure/vnet"

  name                = "${local.name_prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.2.0.0/16"]

  subnets = [
    {
      name             = local.subnet_name
      address_prefixes = ["10.2.1.0/24"]
    }
  ]

  tags = local.common_tags
}

# =============================================================================
# Network Security Group
# =============================================================================
module "nsg" {
  source = "../../../modules/azure/nsg"

  name                = "${local.name_prefix}-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  security_rules      = local.security_rules

  tags = local.common_tags
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "vm_subnet" {
  subnet_id                 = module.vnet.subnet_ids[local.subnet_name]
  network_security_group_id = module.nsg.nsg_id
}

# =============================================================================
# Virtual Machine
# =============================================================================
module "vm" {
  source = "../../../modules/azure/vm"

  name                = "${local.name_prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet.subnet_ids[local.subnet_name]

  size           = var.vm_size
  admin_username = var.vm_admin_username
  ssh_public_key = var.ssh_public_key

  # x64 Ubuntu 22.04 LTS
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"

  custom_data = base64encode(templatefile("${path.module}/../../../common/cloud-init-azure.yaml.tpl", {
    username        = var.vm_admin_username
    public_ssh_keys = var.additional_ssh_keys
  }))

  tags = local.common_tags
}

# Associate NSG with VM NIC
resource "azurerm_network_interface_security_group_association" "vm_nic" {
  network_interface_id      = module.vm.nic_id
  network_security_group_id = module.nsg.nsg_id
}

# =============================================================================
# Container Registry
# =============================================================================
module "acr" {
  source = "../../../modules/azure/acr"

  name                = var.acr_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard" # Production uses Standard tier

  tags = local.common_tags
}

# =============================================================================
# PostgreSQL Database
# =============================================================================
module "database" {
  source = "../../../modules/azure/database"

  name                = "${local.name_prefix}-db"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  database_name  = "omis_pc_db"
  admin_username = var.db_admin_username
  admin_password = var.db_admin_password

  sku_name              = var.db_sku_name
  storage_mb            = var.db_storage_mb
  backup_retention_days = 14 # Longer retention for production

  firewall_rules = [
    {
      name     = "AllowVM"
      start_ip = module.vm.public_ip
      end_ip   = module.vm.public_ip
    }
  ]

  tags = local.common_tags
}
