output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "VNet resource ID."
}

output "vnet_name" {
  value       = azurerm_virtual_network.this.name
  description = "VNet name."
}

output "subnet_ids" {
  value       = { for name, s in azurerm_subnet.this : name => s.id }
  description = "Map of subnet name to resource ID."
}
