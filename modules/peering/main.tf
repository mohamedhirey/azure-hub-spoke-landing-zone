# Azure VNet peering is DIRECTIONAL. hub -> spoke and spoke -> hub are two
# separate resources. Create only one and the peering sits in "Initiated" and
# carries no traffic. This module always creates both.

resource "azurerm_virtual_network_peering" "forward" {
  name                      = "${var.local_vnet_name}-to-${var.remote_vnet_name}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = var.local_vnet_name
  remote_virtual_network_id = var.remote_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "reverse" {
  name                      = "${var.remote_vnet_name}-to-${var.local_vnet_name}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = var.remote_vnet_name
  remote_virtual_network_id = var.local_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
