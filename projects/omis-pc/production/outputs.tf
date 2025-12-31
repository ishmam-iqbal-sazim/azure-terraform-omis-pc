# =============================================================================
# Resource Group
# =============================================================================
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.this.location
}

# =============================================================================
# Virtual Machine
# =============================================================================
output "vm_public_ip" {
  description = "Public IP address of the application VM"
  value       = module.vm.public_ip
}

output "vm_private_ip" {
  description = "Private IP address of the application VM"
  value       = module.vm.private_ip
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = module.vm.vm_name
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.vm_admin_username}@${module.vm.public_ip}"
}

# =============================================================================
# Database
# =============================================================================
output "db_server_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = module.database.server_fqdn
}

output "db_name" {
  description = "Name of the PostgreSQL database"
  value       = module.database.database_name
}

output "db_admin_username" {
  description = "PostgreSQL admin username"
  value       = module.database.admin_username
}

output "db_connection_string" {
  description = "PostgreSQL connection string (add password manually)"
  value       = module.database.connection_string
  sensitive   = true
}

# =============================================================================
# Network
# =============================================================================
output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.vnet_name
}

output "subnet_id" {
  description = "ID of the VM subnet"
  value       = module.vnet.subnet_ids[local.subnet_name]
}

# =============================================================================
# Container Registry
# =============================================================================
output "acr_login_server" {
  description = "ACR login server URL"
  value       = module.acr.login_server
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = module.acr.admin_username
}

output "acr_admin_password" {
  description = "ACR admin password"
  value       = module.acr.admin_password
  sensitive   = true
}

# =============================================================================
# Application URLs (for reference after deployment)
# =============================================================================
output "frontend_url" {
  description = "Frontend application URL (after deployment)"
  value       = "http://${module.vm.public_ip}:3000"
}

output "backend_api_url" {
  description = "Backend API URL (after deployment)"
  value       = "http://${module.vm.public_ip}:5000"
}

output "backend_websocket_url" {
  description = "Backend WebSocket URL (after deployment)"
  value       = "ws://${module.vm.public_ip}:5001"
}
