variable "nsg_name" {
  type        = string
  description = "Network security group name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the NSG is created in."
}

variable "hub_source" {
  type        = string
  description = "Source for the priority-100 management allow: a CIDR, a service tag such as VirtualNetwork, or null to omit the rule entirely."
  default     = null
}

variable "tier_rules" {
  description = "Workload allow rules keyed by rule name."
  type = map(object({
    priority         = number
    protocol         = string
    destination_port = string
    source           = string
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.tier_rules : r.priority > 100 && r.priority < 4096])
    error_message = "Tier rule priorities must be between 101 and 4095. Anything at or above 4096 is evaluated after the catch-all deny and would never match."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the NSG."
  default     = {}
}
