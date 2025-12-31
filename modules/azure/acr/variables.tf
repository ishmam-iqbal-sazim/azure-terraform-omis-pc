# =============================================================================
# Container Registry Module Variables
# =============================================================================

variable "name" {
  description = "Name of the container registry (must be globally unique, alphanumeric only)"
  type        = string
}

variable "location" {
  description = "Azure region for the registry"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "sku" {
  description = "SKU tier for the registry"
  type        = string
  default     = "Basic"
}

variable "admin_enabled" {
  description = "Enable admin user for the registry"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
