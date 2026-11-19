variable "resource_group_name" {
  type        = string
  description = "Resource group holding both virtual networks."
}

variable "local_vnet_name" {
  type        = string
  description = "Name of the local (hub) virtual network."
}

variable "local_vnet_id" {
  type        = string
  description = "Resource ID of the local (hub) virtual network."
}

variable "remote_vnet_name" {
  type        = string
  description = "Name of the remote (spoke) virtual network."
}

variable "remote_vnet_id" {
  type        = string
  description = "Resource ID of the remote (spoke) virtual network."
}
