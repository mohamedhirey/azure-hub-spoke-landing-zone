# These run against a mocked provider. Terraform loads azurerm for its schema
# and its validation but never configures it, so the tests need no Azure
# account and contact nothing. command = plan asserts against the plan only.

mock_provider "azurerm" {}

variables {
  nsg_name            = "nsg-unit-test"
  location            = "canadacentral"
  resource_group_name = "rg-unit-test"
}

run "catch_all_deny_sits_at_the_maximum_priority" {
  command = plan

  assert {
    condition     = azurerm_network_security_rule.deny_all_inbound.priority == 4096
    error_message = "The catch-all deny must sit at 4096, the highest priority number Azure accepts, so it is evaluated last."
  }

  assert {
    condition     = azurerm_network_security_rule.deny_all_inbound.access == "Deny"
    error_message = "The rule at 4096 must be a Deny."
  }
}

run "allows_are_evaluated_before_the_catch_all" {
  command = plan

  variables {
    hub_source = "10.10.0.0/16"
  }

  assert {
    condition = (
      azurerm_network_security_rule.allow_from_hub[0].priority <
      azurerm_network_security_rule.deny_all_inbound.priority
    )
    error_message = "The hub allow must have a LOWER priority number than the catch-all deny, or Azure never evaluates it."
  }
}

run "optional_rule_is_omitted_when_no_source_is_given" {
  command = plan

  variables {
    hub_source = null
  }

  assert {
    condition     = length(azurerm_network_security_rule.allow_from_hub) == 0
    error_message = "With hub_source unset the module must emit no hub allow rule."
  }
}

run "rejects_a_tier_rule_that_would_be_unreachable" {
  command = plan

  variables {
    tier_rules = {
      UnreachableRule = {
        priority         = 5000
        protocol         = "Tcp"
        destination_port = "443"
        source           = "VirtualNetwork"
      }
    }
  }

  expect_failures = [
    var.tier_rules,
  ]
}
