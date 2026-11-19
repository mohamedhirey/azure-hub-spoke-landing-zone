output "forward_peering_id" {
  value       = azurerm_virtual_network_peering.forward.id
  description = "Resource ID of the local-to-remote peering."
}

output "reverse_peering_id" {
  value       = azurerm_virtual_network_peering.reverse.id
  description = "Resource ID of the remote-to-local peering."
}
