output "hub_vnet_id" {
  value       = module.hub.vnet_id
  description = "Hub virtual network resource ID."
}

output "spoke_vnet_ids" {
  value       = { for k, m in module.spoke : k => m.vnet_id }
  description = "Map of spoke name to virtual network resource ID."
}

output "nsg_names" {
  value       = concat([module.hub_nsg.nsg_name], [for k, m in module.spoke_nsg : m.nsg_name])
  description = "Every NSG created by this root module. Used by the pipeline's posture check."
}

output "subnet_ids" {
  value = merge(
    module.hub.subnet_ids,
    { for k, v in local.spoke_subnets : k => module.spoke[v.spoke].subnet_ids[v.subnet] }
  )
  description = "Every subnet created, keyed by name (hub) or spoke-subnet (spokes)."
}
