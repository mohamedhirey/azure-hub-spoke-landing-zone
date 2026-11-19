# RULE ORDER MATTERS.
# Azure evaluates NSG rules from the LOWEST priority number upward and stops at
# the first match. Allows must therefore sit BELOW the catch-all deny.
#
#    100  AllowFromHub    management plane          (optional)
#    200  tier rules      workload-specific allows  (optional)
#   4096  DenyAllInbound  catch-all                 (always)
#
# 4096 is the highest priority number Azure accepts, which makes it the last
# custom rule evaluated. Any allow rule added later is evaluated first, and a
# broken allow fails CLOSED.
# It also shadows Azure's built-in AllowVNetInBound at 65000, which is why
# VNet-to-VNet traffic needs an explicit allow or peerings carry nothing.

resource "azurerm_network_security_group" "this" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# count is correct here: a true 0-or-1 toggle, not a set needing stable identity.
resource "azurerm_network_security_rule" "allow_from_hub" {
  count = var.hub_source == null ? 0 : 1

  name                        = "AllowFromHub"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.hub_source
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_network_security_rule" "tier" {
  for_each = var.tier_rules

  name                        = each.key
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_range      = each.value.destination_port
  source_address_prefix       = each.value.source
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
}
