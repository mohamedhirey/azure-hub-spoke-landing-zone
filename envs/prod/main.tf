locals {
  # Flatten spokes x subnets into one map keyed like "dev-snet-web".
  #
  # Every key comes from var.spokes, so it is known at plan time. for_each
  # requires that: Terraform has to know the full set of keys before it can
  # plan the instances. Only the keys are restricted; a map value may be
  # unknown until apply. The subnet and NSG IDs are still looked up in the
  # resource bodies below, which keeps this map free of anything computed.
  spoke_subnets = merge([
    for spoke_key, spoke in var.spokes : {
      for subnet_key, cidr in spoke.subnets :
      "${spoke_key}-${subnet_key}" => {
        spoke  = spoke_key
        subnet = subnet_key
        cidr   = cidr

        tier_rules = subnet_key == "snet-web" ? {
          AllowHttpsFromVnet = {
            priority         = 200
            protocol         = "Tcp"
            destination_port = "443"
            source           = "VirtualNetwork"
          }
          } : (subnet_key == "snet-app" && contains(keys(spoke.subnets), "snet-web")) ? {
          AllowAppFromWebTier = {
            priority         = 200
            protocol         = "Tcp"
            destination_port = "8080"
            source           = spoke.subnets["snet-web"]
          }
        } : {}
      }
    }
    # The ... after the closing bracket is Terraform's spread operator. merge()
    # takes maps as separate arguments, but the for expression produces a LIST
    # of maps. Without the spread this is a type error.
  ]...)
}

# ---------------------------------------------------------------- hub --------

module "hub" {
  source = "../../modules/network"

  vnet_name           = "vnet-lz-hub-cac-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.hub_address_space
  subnets             = var.hub_subnets
  tags                = var.tags
}

module "hub_nsg" {
  source = "../../modules/nsg"

  nsg_name            = "nsg-lz-hub-cac-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  # The VirtualNetwork service tag covers this VNet plus every peered address
  # space. Declared explicitly because the deny at 4096 shadows Azure's built-in
  # AllowVNetInBound rule at 65000.
  hub_source = "VirtualNetwork"
  tags       = var.tags
}

resource "azurerm_subnet_network_security_group_association" "hub" {
  for_each = var.hub_subnets

  subnet_id                 = module.hub.subnet_ids[each.key]
  network_security_group_id = module.hub_nsg.nsg_id
}

# ------------------------------------------------------------- spokes --------

module "spoke" {
  source   = "../../modules/network"
  for_each = var.spokes

  vnet_name           = "vnet-lz-${each.key}-cac-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = each.value.address_space
  subnets             = each.value.subnets
  tags                = merge(var.tags, { Environment = each.key })
}

module "spoke_nsg" {
  source   = "../../modules/nsg"
  for_each = local.spoke_subnets

  nsg_name            = "nsg-lz-${each.value.spoke}-${each.value.subnet}-cac-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  hub_source          = var.hub_address_space
  tier_rules          = each.value.tier_rules
  tags                = merge(var.tags, { Environment = each.value.spoke })
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each = local.spoke_subnets

  # These IDs are unknown until apply. That is fine in an argument. It would
  # not be fine as a for_each key.
  subnet_id                 = module.spoke[each.value.spoke].subnet_ids[each.value.subnet]
  network_security_group_id = module.spoke_nsg[each.key].nsg_id
}

# ----------------------------------------------------------- peerings --------

# Hub to each spoke, both directions. No spoke-to-spoke peering exists, which is
# what proves the isolation: peering is non-transitive, so dev -> hub -> prod
# does not route.
module "peering" {
  source   = "../../modules/peering"
  for_each = var.spokes

  resource_group_name = var.resource_group_name

  local_vnet_name = module.hub.vnet_name
  local_vnet_id   = module.hub.vnet_id

  remote_vnet_name = module.spoke[each.key].vnet_name
  remote_vnet_id   = module.spoke[each.key].vnet_id
}

# NOTE: there is deliberately no azurerm_resource_group in this root module.
# The workload group is created by bootstrap. That is what stops a workload
# destroy from deleting the container it runs inside.
