variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "resource_group_name" {
  type        = string
  description = "Pre-existing workload resource group, created by the bootstrap module."
  default     = "rg-lz-workload-cac-001"
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "canadacentral"
}

variable "hub_address_space" {
  type        = string
  description = "Hub VNet CIDR."
  default     = "10.10.0.0/16"
}

variable "hub_subnets" {
  type        = map(string)
  description = "Hub subnets, keyed by name."
  default = {
    "snet-shared" = "10.10.1.0/24"
  }
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to every taggable resource."
  default = {
    Project     = "azure-hub-spoke-landing-zone"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

variable "spokes" {
  description = "Spoke networks, keyed by environment name."
  type = map(object({
    address_space = string
    subnets       = map(string)
  }))

  default = {
    dev = {
      address_space = "10.20.0.0/16"
      subnets = {
        "snet-web" = "10.20.1.0/24"
        "snet-app" = "10.20.2.0/24"
      }
    }
    prod = {
      address_space = "10.30.0.0/16"
      subnets = {
        "snet-app" = "10.30.1.0/24"
      }
    }
  }
}
