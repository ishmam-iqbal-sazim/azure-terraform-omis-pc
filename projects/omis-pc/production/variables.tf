# =============================================================================
# General Configuration
# =============================================================================
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "sazim-3dif-omis-pc-prod"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  # default     = "australiacentral"
  default     = "westus"
}

# =============================================================================
# Virtual Machine Configuration
# =============================================================================
variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D4ds_v6" # x64 (4 vCPUs, 16GB RAM) - latest generation
  # Fallback options if Standard_D4ds_v6 is not available:
  # default     = "Standard_D4as_v6"  # AMD-based alternative (4 vCPUs, 16GB RAM)
  # default     = "Standard_D4s_v3"   # Older generation (4 vCPUs, 16GB RAM)
}

variable "vm_admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VM authentication"
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCbp3moLswLCpi6K9rr7MWKrrXyUJzsMGa8hy9SuiDW1lGm4xYc2e19eVNuU7xBGctOK0/hG1+6AHNgk3bokqyxaw6lS8A+L2CQWSBKmJpAhWJMqiBvARDDxEy75o/OsWFzNuofziah2PTgMB6k7c8eKmtSHBB3gpTX5iUMuo+FzV+JBM48b6JKyiBKuISbg1hBgytyFnpbLD8OyBE81g6DLWteG8bH8+snoS4Ulh0DjkL2o2vqD3ghFZQExemPgGtfAcbBZ7HrdAf8jczMdpL7pzT9lbmDW4a0nHhUe0lHsTiyCty+SjDzAGw8tGQkNScYYY/N6iTFfgjPHY2lr9xGeeNNVTcKiVrKDc5GJkp6+qG/CDSRmfrKRADlMQ85kA60ptdmm4yGlpFuGOEM5qq53hGufjGihuST+iSneR8CSXJtVCpNGAX1+RAi6gX9a+4ZqJ3qpBX5V/SoxA+0pUofACxn9Uj5r/Vccsib0SPQq6Ehf43774cGJy1r86Tr/LYBgTWC3uu7AQew3qgmJFY5xCGhNSPms1Spcb1b3ce8ektYajyPiFxzfY6mHKcplTfARtc9YQwLHFE1XlJ0pJZFjqSS+mdTf+spLmS6nL0bxdscBjYnZk98J6513D2lItbCfPByluj5HmSREfgBh+unorJ9L7/iCj5iApbUtmofhQ== azure"
}

variable "additional_ssh_keys" {
  description = "Additional SSH public keys to add via cloud-init"
  type        = list(string)
  default     = []
}

# =============================================================================
# Container Registry Configuration
# =============================================================================
variable "acr_name" {
  description = "Name of the Azure Container Registry (must be globally unique, alphanumeric only)"
  type        = string
  default     = "omispcacrprod"
}

# =============================================================================
# Database Configuration
# =============================================================================
variable "db_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B2ms" # Burstable, 2 vCores, 4GB RAM (production)
}

variable "db_storage_mb" {
  description = "Storage size for PostgreSQL in MB"
  type        = number
  default     = 65536 # 64GB (production)
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "omispcadmin"
}

variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}
