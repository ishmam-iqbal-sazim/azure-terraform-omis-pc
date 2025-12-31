# =============================================================================
# Virtual Machine Module Outputs
# =============================================================================

output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.this.name
}

output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.this.ip_address
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.this.private_ip_address
}

output "identity_principal_id" {
  description = "Principal ID of the VM's managed identity"
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "admin_username" {
  description = "Admin username of the VM"
  value       = azurerm_linux_virtual_machine.this.admin_username
}

output "nic_id" {
  description = "ID of the network interface"
  value       = azurerm_network_interface.this.id
}
