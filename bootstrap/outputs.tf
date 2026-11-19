output "state_resource_group" {
  value       = azurerm_resource_group.state.name
  description = "Resource group holding the state storage account."
}

output "workload_resource_group" {
  value       = azurerm_resource_group.workload.name
  description = "Resource group the workload root module deploys into."
}

output "storage_account_name" {
  value       = azurerm_storage_account.state.name
  description = "State storage account name. Needed for -backend-config."
}

output "storage_account_id" {
  value       = azurerm_storage_account.state.id
  description = "State storage account resource ID. Needed for the data-plane role assignment."
}
