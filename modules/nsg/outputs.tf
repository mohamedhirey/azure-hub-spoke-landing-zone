output "nsg_id" {
  value       = azurerm_network_security_group.this.id
  description = "NSG resource ID."
}

output "nsg_name" {
  value       = azurerm_network_security_group.this.name
  description = "NSG name."
}
