resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "state" {
  name     = "rg-lz-state-cac-001"
  location = var.location
  tags     = var.tags
}

# Created here, not in the workload root module, so that a workload destroy can
# never delete the resource group it lives in. This structural separation is why
# no prevent_destroy lifecycle lock is needed anywhere in this repo.
resource "azurerm_resource_group" "workload" {
  name     = "rg-lz-workload-cac-001"
  location = var.location
  tags     = var.tags
}

# Trivy AZU-0012 (no network default-deny) is accepted here on purpose.
# GitHub-hosted runners have no fixed address, so a firewall default of Deny
# would lock the pipeline out of its own state. Closing the network path needs
# a private endpoint and a self-hosted runner, which this build scopes out
# (REFERENCE.md). Access is restricted by identity instead: account keys
# refused, no anonymous access, Entra ID data-plane RBAC only.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "state" {
  name                = "stlz${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Shared Key authorization is off: the account's keys, and SAS tokens signed
  # with them, are refused. This is what enforces "no long-lived storage
  # credentials" - not a policy document, not a promise.
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# NOTE: there is deliberately no azurerm_storage_container here.
# Creating a container is a DATA-PLANE operation. With account keys disabled it
# requires an Entra ID data-plane role that does not exist yet at this point in
# the run. The container is created by hand in Step 15 of GUIDE.md, after the
# role assignment. See REFERENCE.md, "Control plane vs data plane".
