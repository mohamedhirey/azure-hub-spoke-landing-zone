variable "vnet_name" {
  type        = string
  description = "Virtual network name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the VNet is created in."
}

variable "address_space" {
  type        = string
  description = "VNet CIDR, e.g. 10.10.0.0/16."

  validation {
    condition     = can(cidrhost(var.address_space, 0))
    error_message = "address_space must be a valid CIDR block, e.g. 10.10.0.0/16."
  }
}

variable "subnets" {
  type        = map(string)
  description = "Subnets to create, keyed by name with the CIDR as the value."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the VNet."
  default     = {}
}
