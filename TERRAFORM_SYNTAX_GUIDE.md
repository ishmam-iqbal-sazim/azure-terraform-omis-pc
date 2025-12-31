# Terraform Syntax Guide: Line-by-Line Walkthrough

This guide explains every line of Terraform code in this repository, teaching you the syntax and the reasoning behind each piece.

---

## Table of Contents

1. [Terraform Fundamentals](#part-1-terraform-fundamentals)
2. [The HCL Language](#part-2-the-hcl-language)
3. [Block Types Explained](#part-3-block-types-explained)
4. [File: production/main.tf](#part-4-file-productionmaintf)
5. [File: production/variables.tf](#part-5-file-productionvariablestf)
6. [File: production/outputs.tf](#part-6-file-productionoutputstf)
7. [File: modules/azure/vnet/](#part-7-file-modulesazurevnet)
8. [File: modules/azure/nsg/](#part-8-file-modulesazurensg)
9. [File: modules/azure/vm/](#part-9-file-modulesazurevm)
10. [File: modules/azure/database/](#part-10-file-modulesazuredatabase)
11. [File: modules/azure/acr/](#part-11-file-modulesazureacr)
12. [Advanced Concepts](#part-12-advanced-concepts)

---

## Part 1: Terraform Fundamentals

### What is Terraform?

Terraform is a tool that reads `.tf` files and:
1. **Parses** your configuration
2. **Plans** what needs to change
3. **Creates/Updates/Deletes** resources in the cloud

### The Three File Types

Every Terraform project typically has three types of files:

| File | Purpose | Analogy |
|------|---------|---------|
| `main.tf` | Defines WHAT to create | The blueprint |
| `variables.tf` | Defines configurable INPUTS | The form you fill out |
| `outputs.tf` | Defines what to DISPLAY after | The receipt |

### How Terraform Works

```
┌─────────────────────────────────────────────────────────────┐
│                     TERRAFORM WORKFLOW                       │
│                                                              │
│   1. terraform init                                          │
│      └── Downloads providers (Azure plugin)                  │
│                                                              │
│   2. terraform plan                                          │
│      └── Shows what will be created/changed/destroyed        │
│                                                              │
│   3. terraform apply                                         │
│      └── Actually creates resources in Azure                 │
│                                                              │
│   4. terraform destroy                                       │
│      └── Deletes everything                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 2: The HCL Language

Terraform uses **HCL** (HashiCorp Configuration Language). Let's learn the syntax.

### Basic Syntax Rules

```hcl
# This is a comment (single line)

# Blocks have a type, labels, and a body
block_type "label1" "label2" {
  argument_name = "argument_value"

  nested_block {
    another_argument = "value"
  }
}
```

### Data Types

```hcl
# String - Text in quotes
name = "hello"

# Number - No quotes
count = 42
price = 3.14

# Boolean - true or false (no quotes)
enabled = true

# List - Ordered collection in square brackets
ports = [80, 443, 8080]
names = ["alice", "bob", "charlie"]

# Map/Object - Key-value pairs in curly braces
tags = {
  Environment = "production"
  Team        = "platform"
}

# Complex object
config = {
  name   = "my-app"
  port   = 8080
  debug  = false
}
```

### String Interpolation

You can embed expressions inside strings:

```hcl
# ${...} embeds a value
name = "app-${var.environment}"

# If var.environment = "prod", result is "app-prod"
```

### References

```hcl
# Reference a variable
var.variable_name

# Reference a local value
local.local_name

# Reference a resource attribute
resource_type.resource_name.attribute

# Reference a module output
module.module_name.output_name
```

---

## Part 3: Block Types Explained

### 1. terraform Block

**Purpose**: Configure Terraform itself.

```hcl
terraform {
  required_version = ">= 1.9.0"    # Minimum Terraform version

  required_providers {              # Which cloud plugins to use
    azurerm = {
      source  = "hashicorp/azurerm"   # Where to download from
      version = "~> 3.0"               # Which version
    }
  }
}
```

**Why needed**: Ensures everyone uses compatible versions.

---

### 2. provider Block

**Purpose**: Configure the cloud provider (Azure, AWS, etc.).

```hcl
provider "azurerm" {
  features {}    # Required but can be empty

  # Authentication happens via Azure CLI by default
  # Or you can specify:
  # subscription_id = "..."
  # client_id       = "..."
  # client_secret   = "..."
  # tenant_id       = "..."
}
```

**Why needed**: Tells Terraform HOW to connect to Azure.

---

### 3. resource Block

**Purpose**: Create something in the cloud.

```hcl
resource "azurerm_resource_group" "this" {
  name     = "my-resource-group"
  location = "westus"
}
```

**Anatomy**:
```
resource "TYPE" "NAME" {
         │       │
         │       └── Your local name (used to reference it)
         └── Azure resource type (from provider docs)
```

**How to reference**: `azurerm_resource_group.this.name`

---

### 4. variable Block

**Purpose**: Define an input that can be customized.

```hcl
variable "location" {
  description = "Azure region"           # Human-readable description
  type        = string                    # Data type
  default     = "westus"                  # Default value (optional)
  sensitive   = false                     # Hide from output? (optional)
}
```

**How to use**: `var.location`

---

### 5. output Block

**Purpose**: Display a value after `terraform apply`.

```hcl
output "public_ip" {
  description = "The public IP address"
  value       = azurerm_public_ip.this.ip_address
  sensitive   = false   # Set true to hide sensitive data
}
```

**Why needed**: So you know important values like IP addresses.

---

### 6. locals Block

**Purpose**: Define reusable values within a file.

```hcl
locals {
  name_prefix = "myapp-prod"
  common_tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

**How to use**: `local.name_prefix`, `local.common_tags`

**Why needed**: Avoid repeating the same values everywhere.

---

### 7. module Block

**Purpose**: Use a reusable component.

```hcl
module "vnet" {
  source = "../../../modules/azure/vnet"   # Where the module code is

  # Pass values to the module
  name     = "my-vnet"
  location = var.location
}
```

**How to reference outputs**: `module.vnet.vnet_id`

---

## Part 4: File: production/main.tf

Let's walk through every single line.

### Lines 1-3: Comment Header

```hcl
# =============================================================================
# OMIS Product Configurator - Production Environment
# =============================================================================
```

**What**: A comment block for documentation.
**Why**: Makes the file self-documenting. Anyone opening this knows what it's for.

---

### Lines 5-14: Terraform Configuration

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

**Line by line**:

| Line | Code | Explanation |
|------|------|-------------|
| 5 | `terraform {` | Start of terraform configuration block |
| 6 | `required_version = ">= 1.9.0"` | Terraform CLI must be version 1.9.0 or higher |
| 8 | `required_providers {` | Start listing which cloud plugins we need |
| 9 | `azurerm = {` | We're configuring the Azure provider |
| 10 | `source = "hashicorp/azurerm"` | Download from HashiCorp's registry |
| 11 | `version = "~> 3.0"` | Use version 3.x (any 3.something) |
| 12-13 | `}` | Close the blocks |
| 14 | `}` | Close terraform block |

**Version Constraint Operators**:
| Operator | Meaning | Example |
|----------|---------|---------|
| `= 3.0.0` | Exactly this version | Only 3.0.0 |
| `>= 3.0` | This or newer | 3.0, 3.1, 4.0, etc. |
| `~> 3.0` | Allows patch/minor updates | 3.0.x, 3.1.x, but NOT 4.0 |
| `>= 3.0, < 4.0` | Range | 3.x only |

---

### Lines 16-19: Provider Configuration

```hcl
provider "azurerm" {
  features {}
  # Uses Azure CLI authentication by default
}
```

| Line | Code | Explanation |
|------|------|-------------|
| 16 | `provider "azurerm" {` | Configure the Azure provider |
| 17 | `features {}` | Required by Azure provider (even if empty) |
| 18 | `# Uses Azure CLI...` | Comment explaining auth method |
| 19 | `}` | Close provider block |

**Why `features {}`?**: Azure provider requires it. It can contain feature flags but we use defaults.

---

### Lines 21-35: Local Variables

```hcl
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
```

| Line | Code | Explanation |
|------|------|-------------|
| 24 | `locals {` | Start defining local values |
| 25 | `project_name = "omis-pc"` | Simple string value |
| 26 | `environment = "prod"` | Another string |
| 27 | `name_prefix = "${local.project_name}-${local.environment}"` | Combine two values → "omis-pc-prod" |
| 28 | `subnet_name = "${local.name_prefix}-vm-subnet"` | → "omis-pc-prod-vm-subnet" |
| 30 | `common_tags = {` | Start a map (key-value pairs) |
| 31 | `Project = "OMIS Product Configurator"` | Tag: Project |
| 32 | `Environment = local.environment` | Tag: Environment (uses another local) |
| 33 | `ManagedBy = "Terraform"` | Tag: Who manages this |
| 34 | `}` | Close the map |

**Why tags?**:
- Azure billing reports can filter by tag
- Helps identify resources
- Shows "this was created by Terraform, don't edit manually"

---

### Lines 36-104: Security Rules Local

```hcl
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
    # ... more rules ...
  ]
}
```

This is a **list of objects**. Each object is one firewall rule.

**Breaking down one rule**:

| Property | Value | Meaning |
|----------|-------|---------|
| `name` | "SSH" | Human-readable name |
| `priority` | 1000 | Order to check (lower = first) |
| `direction` | "Inbound" | Traffic coming INTO the VM |
| `access` | "Allow" | Let it through (vs "Deny") |
| `protocol` | "Tcp" | TCP protocol (vs UDP) |
| `source_port_range` | "*" | From any port |
| `destination_port_range` | "22" | To port 22 (SSH) |
| `source_address_prefix` | "*" | From any IP address |
| `destination_address_prefix` | "*" | To any destination |

**Why a list?**: We have multiple rules (SSH, HTTP, HTTPS, etc.). Putting them in a list makes them easy to pass to the NSG module.

---

### Lines 107-115: Resource Group

```hcl
# =============================================================================
# Resource Group
# =============================================================================
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}
```

| Line | Code | Explanation |
|------|------|-------------|
| 110 | `resource "azurerm_resource_group" "this" {` | Create a resource group, call it "this" |
| 111 | `name = var.resource_group_name` | Name from variable (not hardcoded) |
| 112 | `location = var.location` | Location from variable |
| 114 | `tags = local.common_tags` | Apply our common tags |
| 115 | `}` | Close the resource |

**Why "this" as the name?**: Convention when there's only one of something. Could be "main" or "rg" too.

**Why variables instead of hardcoding?**:
- Same code can be used for different environments
- Easy to change without editing main logic

---

### Lines 117-136: VNet Module

```hcl
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
```

| Line | Code | Explanation |
|------|------|-------------|
| 120 | `module "vnet" {` | Use a module, call it "vnet" |
| 121 | `source = "../../../modules/azure/vnet"` | Path to module code |
| 123 | `name = "${local.name_prefix}-vnet"` | → "omis-pc-prod-vnet" |
| 124 | `location = var.location` | Pass location to module |
| 125 | `resource_group_name = azurerm_resource_group.this.name` | Reference the RG we created |
| 126 | `address_space = ["10.2.0.0/16"]` | IP range (list with one item) |
| 128-133 | `subnets = [...]` | List of subnet definitions |
| 135 | `tags = local.common_tags` | Pass tags to module |

**Why `azurerm_resource_group.this.name`?**:
- This creates a **dependency**
- Terraform knows: "Create RG first, THEN create VNet"

---

### Lines 138-156: NSG Module and Association

```hcl
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
```

**Line 147**: `security_rules = local.security_rules`
- Pass our list of 6 firewall rules to the module

**Line 153-156**: Association resource
- `subnet_id = module.vnet.subnet_ids[local.subnet_name]`
  - `module.vnet` → The VNet module
  - `.subnet_ids` → Its output (a map)
  - `[local.subnet_name]` → Get the subnet with this name
- `network_security_group_id = module.nsg.nsg_id`
  - Get the NSG's ID from its module output

**Why a separate association?**:
- NSG and Subnet are created separately
- Association links them together
- Keeps modules independent/reusable

---

### Lines 158-190: VM Module and Association

```hcl
module "vm" {
  source = "../../../modules/azure/vm"

  name                = "${local.name_prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet.subnet_ids[local.subnet_name]

  size           = var.vm_size
  admin_username = var.vm_admin_username
  ssh_public_key = var.ssh_public_key

  # ARM64 Ubuntu 22.04 LTS
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-arm64"

  custom_data = base64encode(templatefile("${path.module}/../../../common/cloud-init-azure.yaml.tpl", {
    username        = var.vm_admin_username
    public_ssh_keys = var.additional_ssh_keys
  }))

  tags = local.common_tags
}
```

**Line 167**: `subnet_id = module.vnet.subnet_ids[local.subnet_name]`
- VM connects to this subnet

**Lines 169-171**: VM configuration from variables
- Size, username, SSH key

**Lines 173-176**: Image configuration
- **publisher**: Who makes the image (Canonical = Ubuntu)
- **offer**: Product line
- **sku**: Specific version (Ubuntu 22.04 for ARM64)

**Lines 178-181**: Cloud-init (complex!)
```hcl
custom_data = base64encode(templatefile("${path.module}/../../../common/cloud-init-azure.yaml.tpl", {
  username        = var.vm_admin_username
  public_ssh_keys = var.additional_ssh_keys
}))
```

Breaking this down inside-out:
1. `${path.module}` → Current directory
2. `templatefile("path", {vars})` → Read file, replace variables in it
3. `base64encode(...)` → Encode result as base64 (Azure requires this)

---

### Lines 192-204: ACR Module

```hcl
module "acr" {
  source = "../../../modules/azure/acr"

  name                = var.acr_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"

  tags = local.common_tags
}
```

Straightforward module call:
- `name = var.acr_name` → "omispcacrprod"
- `sku = "Standard"` → Hardcoded (not a variable) because production always uses Standard

---

### Lines 206-233: Database Module

```hcl
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
  backup_retention_days = 14

  firewall_rules = [
    {
      name     = "AllowVM"
      start_ip = module.vm.public_ip
      end_ip   = module.vm.public_ip
    }
  ]

  tags = local.common_tags
}
```

**Lines 224-229**: Firewall rules
```hcl
firewall_rules = [
  {
    name     = "AllowVM"
    start_ip = module.vm.public_ip
    end_ip   = module.vm.public_ip
  }
]
```

This creates a firewall rule that:
- Allows connections FROM the VM's public IP
- TO the database
- No one else can connect!

**Why `start_ip` and `end_ip` are the same?**:
- For a single IP, they're identical
- For a range, you'd do `start_ip = "1.1.1.1"`, `end_ip = "1.1.1.10"`

---

## Part 5: File: production/variables.tf

### Variable Anatomy

```hcl
variable "name" {
  description = "..."      # What this variable is for (for humans)
  type        = string     # Data type (string, number, bool, list, map, object)
  default     = "..."      # Default value (optional - if missing, user MUST provide)
  sensitive   = true       # Hide from output (optional, default false)
}
```

### Full File Walkthrough

```hcl
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "sazim-3dif-omis-pc-prod"
}
```

| Property | Value | Explanation |
|----------|-------|-------------|
| name | `resource_group_name` | How to reference: `var.resource_group_name` |
| description | "Name of..." | Shown in `terraform plan` output |
| type | `string` | Must be text |
| default | "sazim-3dif-omis-pc-prod" | Used if not overridden |

---

```hcl
variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}
```

**Note**: No `default`!
- User MUST provide this (in terraform.tfvars or command line)
- `sensitive = true` means it won't show in logs/output

---

### Type Examples in This File

```hcl
# String type
type = string

# Number type
type = number
default = 65536

# List of strings
type = list(string)
default = []

# Boolean
type = bool
default = true
```

---

## Part 6: File: production/outputs.tf

### Output Anatomy

```hcl
output "name" {
  description = "What this output shows"
  value       = some.reference.to.value
  sensitive   = false
}
```

### Examples from the File

```hcl
# Simple: output a resource attribute
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}
```

Reference breakdown:
- `azurerm_resource_group` → Resource type
- `.this` → The name we gave it
- `.name` → The "name" attribute of that resource

---

```hcl
# Module output: reference a module's output
output "vm_public_ip" {
  description = "Public IP address of the application VM"
  value       = module.vm.public_ip
}
```

Reference breakdown:
- `module` → It's a module reference
- `.vm` → The module name
- `.public_ip` → Output from that module's outputs.tf

---

```hcl
# String interpolation in output
output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.vm_admin_username}@${module.vm.public_ip}"
}
```

If `vm_admin_username = "azureuser"` and `public_ip = "52.160.10.21"`:
Result: `"ssh azureuser@52.160.10.21"`

---

```hcl
# Sensitive output
output "db_connection_string" {
  description = "PostgreSQL connection string (add password manually)"
  value       = module.database.connection_string
  sensitive   = true
}
```

`sensitive = true` means:
- Won't show in terminal output
- Still saved in state file
- Use `terraform output db_connection_string` to see it

---

## Part 7: File: modules/azure/vnet/

### main.tf

```hcl
resource "azurerm_virtual_network" "this" {
  name                = var.name
  address_space       = var.address_space
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = { for subnet in var.subnets : subnet.name => subnet }

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes
}
```

**The `for_each` Magic** (Line 14):

```hcl
for_each = { for subnet in var.subnets : subnet.name => subnet }
```

This transforms:
```hcl
# Input list:
[
  { name = "subnet-a", address_prefixes = ["10.0.1.0/24"] },
  { name = "subnet-b", address_prefixes = ["10.0.2.0/24"] }
]

# Into a map:
{
  "subnet-a" = { name = "subnet-a", address_prefixes = ["10.0.1.0/24"] },
  "subnet-b" = { name = "subnet-b", address_prefixes = ["10.0.2.0/24"] }
}
```

**Why?**: `for_each` requires a map. Each key becomes a resource instance.

**Using `each`**:
- `each.key` → "subnet-a" or "subnet-b"
- `each.value` → The full object
- `each.value.name` → "subnet-a"
- `each.value.address_prefixes` → ["10.0.1.0/24"]

---

### variables.tf

```hcl
variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    name             = string
    address_prefixes = list(string)
  }))
  default = []
}
```

**Complex Type**: `list(object({...}))`

This means:
- A list (ordered collection)
- Of objects (structured data)
- Each object has:
  - `name`: a string
  - `address_prefixes`: a list of strings

---

### outputs.tf

```hcl
output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}
```

**For Expression in Output**:

```hcl
{ for k, v in azurerm_subnet.this : k => v.id }
```

This transforms:
```hcl
# azurerm_subnet.this contains:
{
  "subnet-a" = <full subnet object>,
  "subnet-b" = <full subnet object>
}

# Into:
{
  "subnet-a" = "/subscriptions/.../subnets/subnet-a",
  "subnet-b" = "/subscriptions/.../subnets/subnet-b"
}
```

**Why?**: Makes it easy to look up subnet IDs by name later.

---

## Part 8: File: modules/azure/nsg/

### main.tf

```hcl
resource "azurerm_network_security_group" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "security_rule" {
    for_each = var.security_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }

  tags = var.tags
}
```

**The `dynamic` Block** (Lines 10-22):

Normally you'd write:
```hcl
security_rule {
  name = "SSH"
  ...
}
security_rule {
  name = "HTTP"
  ...
}
# Repeat for each rule...
```

`dynamic` generates these blocks from a list:
```hcl
dynamic "security_rule" {        # Create security_rule blocks
  for_each = var.security_rules  # One for each item in this list
  content {                      # The content of each block
    name = security_rule.value.name   # security_rule.value is current item
    ...
  }
}
```

**Why `security_rule.value`?**:
- `security_rule` is the iterator variable (named after the block type)
- `.value` is the current list item
- `.key` would be the index (0, 1, 2...)

---

## Part 9: File: modules/azure/vm/

### main.tf

```hcl
# Public IP
resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}
```

**String Concatenation**: `"${var.name}-pip"`
- If `var.name = "omis-pc-prod-vm"`
- Result: `"omis-pc-prod-vm-pip"`

---

```hcl
resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }

  tags = var.tags
}
```

**Nested Block**: `ip_configuration`
- Some resources have nested blocks for sub-configurations
- NIC needs IP configuration with subnet and public IP links

**Reference within same file**: `azurerm_public_ip.this.id`
- References the public IP we created above
- Creates implicit dependency (public IP created first)

---

```hcl
resource "azurerm_linux_virtual_machine" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.this.id]

  os_disk {
    name                 = "${var.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  custom_data = var.custom_data

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [custom_data]
  }
}
```

**Key Concepts**:

1. **`network_interface_ids = [...]`**: A list (even with one item)

2. **Nested blocks**: `admin_ssh_key`, `os_disk`, `source_image_reference`, `identity`

3. **`lifecycle` block**:
```hcl
lifecycle {
  ignore_changes = [custom_data]
}
```
- Tells Terraform: "Don't recreate VM if only custom_data changes"
- **Why?**: Cloud-init only runs on first boot. Changing it doesn't affect running VM.

4. **`identity { type = "SystemAssigned" }`**:
- Gives VM a managed identity
- Can authenticate to Azure services without passwords

---

## Part 10: File: modules/azure/database/

### main.tf

```hcl
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  for_each = { for rule in var.firewall_rules : rule.name => rule }

  name             = each.value.name
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}
```

**Same pattern as subnets**: Transform list to map, create one resource per item.

---

### outputs.tf

```hcl
output "connection_string" {
  description = "PostgreSQL connection string (password not included)"
  value       = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${azurerm_postgresql_flexible_server_database.this.name}?sslmode=require"
  sensitive   = true
}
```

**Complex String Interpolation**:
- Multiple `${...}` expressions in one string
- Builds a connection URL like:
  `postgresql://omispcadmin@omis-pc-prod-db.postgres.database.azure.com:5432/omis_pc_db?sslmode=require`

---

## Part 11: File: modules/azure/acr/

### main.tf

```hcl
resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = var.admin_enabled

  tags = var.tags
}
```

The simplest module - just creates one resource with configurable properties.

---

## Part 12: Advanced Concepts

### 1. Dependency Management

Terraform automatically detects dependencies from references:

```hcl
# This creates implicit dependency:
resource_group_name = azurerm_resource_group.this.name
#                     ↑ References resource_group
#                     Terraform knows: create RG first, then this
```

**Explicit dependency** (rarely needed):
```hcl
resource "something" "example" {
  depends_on = [azurerm_resource_group.this]
}
```

---

### 2. Count vs For_Each

**count**: Create N identical resources
```hcl
resource "azurerm_subnet" "example" {
  count = 3
  name  = "subnet-${count.index}"   # subnet-0, subnet-1, subnet-2
}
```

**for_each**: Create resources from a collection
```hcl
resource "azurerm_subnet" "example" {
  for_each = toset(["web", "app", "db"])
  name     = "subnet-${each.key}"   # subnet-web, subnet-app, subnet-db
}
```

**When to use which?**:
| Scenario | Use |
|----------|-----|
| Same resource, different count | `count` |
| Different configurations per item | `for_each` |
| Items might be added/removed | `for_each` (safer) |

---

### 3. Conditional Expressions

```hcl
# Ternary: condition ? true_value : false_value
sku = var.environment == "prod" ? "Standard" : "Basic"
```

---

### 4. Functions

Common functions used in this repo:

| Function | What it does | Example |
|----------|--------------|---------|
| `base64encode()` | Encode string to base64 | `base64encode("hello")` |
| `templatefile()` | Read file with variable substitution | `templatefile("file.tpl", {var1 = "value"})` |
| `toset()` | Convert list to set | `toset(["a", "b"])` |

---

### 5. Path References

```hcl
${path.module}   # Directory of current .tf file
${path.root}     # Directory where terraform was run
${path.cwd}      # Current working directory
```

---

### 6. State File

After `terraform apply`, a `terraform.tfstate` file is created:
- JSON file tracking what was created
- Maps your config to real Azure resource IDs
- **NEVER edit manually**
- **NEVER commit to git** (contains secrets)

---

## Summary: The Mental Model

```
┌─────────────────────────────────────────────────────────────┐
│                    HOW IT ALL FITS                           │
│                                                              │
│   variables.tf          main.tf              outputs.tf      │
│   ────────────          ───────              ──────────      │
│   "What can be          "What to             "What to        │
│    configured?"          create"              show after"    │
│                                                              │
│        │                    │                    ▲           │
│        │                    │                    │           │
│        ▼                    ▼                    │           │
│   ┌─────────┐         ┌──────────┐         ┌─────────┐      │
│   │ var.x   │ ──────► │ resource │ ──────► │ output  │      │
│   │ var.y   │         │ module   │         │ values  │      │
│   └─────────┘         │ locals   │         └─────────┘      │
│                       └──────────┘                           │
│                            │                                 │
│                            ▼                                 │
│                    terraform apply                           │
│                            │                                 │
│                            ▼                                 │
│                      Azure Cloud                             │
│                  (Real resources)                            │
└─────────────────────────────────────────────────────────────┘
```

You now understand:
- Every block type in Terraform
- Every line in this repository
- Why each piece exists
- How they connect together
