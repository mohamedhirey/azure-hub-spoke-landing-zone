variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into."
}

variable "location" {
  type        = string
  description = "Azure region. One region for the whole build."
  default     = "canadacentral"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource."
  default = {
    Project     = "azure-hub-spoke-landing-zone"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}
