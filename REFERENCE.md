# Reference

Naming, tags, rule priorities, design exclusions and troubleshooting for this repository. [`GUIDE.md`](GUIDE.md) has the deployment steps.

## Naming

`<type>-lz-<role>-<region>-<instance>`

| Resource | Example |
|---|---|
| Resource group | `rg-lz-workload-cac-001` |
| Virtual network | `vnet-lz-hub-cac-001` |
| Subnet | `snet-web` |
| Network security group | `nsg-lz-dev-snet-web-cac-001` |
| Storage account | `stlz<8 random>` — globally unique, 3–24 chars, lowercase alphanumeric only, no hyphens |

One region for everything: `canadacentral` (`cac`).

## Tags

`Project`, `Environment` and `ManagedBy` on every taggable resource.

Not everything is taggable. Subnets, NSG rules, subnet-NSG associations, peerings and role assignments carry no tags — inventory those through their parent resource.

## NSG rule priorities

Azure evaluates NSG rules from the **lowest** number upward and stops at the **first match**.

| Priority | Rule | Scope |
|---|---|---|
| 100 | `AllowFromHub` | management plane — hub CIDR, or the `VirtualNetwork` service tag |
| 200 | tier rule | web: 443 from `VirtualNetwork` · app: 8080 from the web subnet |
| 4096 | `DenyAllInbound` | catch-all, the highest number Azure accepts |

Two consequences:

1. An allow numbered *above* a catch-all deny is unreachable. It looks correct in the portal and blocks everything.
2. A deny at 4096 is evaluated *before* Azure's built-ins at 65000+, including `AllowVNetInBound`. So VNet-to-VNet traffic needs an **explicit** allow at 100, or your peerings carry nothing.

The `validation` block on `var.tier_rules` in `modules/nsg/variables.tf` enforces this rather than documenting it — a rule at 5000 fails the plan.

## `count` vs `for_each`

| | Addresses by | Removing a middle item | Use for |
|---|---|---|---|
| `count` | index — `[0]`, `[1]` | shifts every later index, so Terraform destroys and recreates them | a true 0-or-1 toggle only |
| `for_each` | stable string key | touches only that item | anything resembling a set |

In this repo: `count` appears exactly once, on the optional hub allow rule. Everything else uses `for_each`.

## Module outputs and `for_each`

Terraform must know every `for_each` key at plan time, because the keys decide which instances exist. A value that is only known after apply, such as a resource ID returned by a module, cannot be a key or an element of a set passed to `for_each`. As a map *value* it is allowed.

The pattern in `envs/prod/main.tf`: the keys of `local.spoke_subnets` are built from variables only, and the IDs the network and NSG modules return are looked up **inside the resource body**.

## Control plane vs data plane

- **Control plane** roles (`Contributor`, `Network Contributor`) manage a resource's existence and configuration.
- **Data plane** roles (`Storage Blob Data Contributor`) read and write the data inside it.

A storage account with `shared_access_key_enabled = false` **refuses its own account keys**. Only data-plane RBAC grants blob access, regardless of what control-plane role you hold. This single fact is behind most "403 on terraform init" threads online.

## Identity checklist

- OIDC federation, never a client secret. Tokens are short-lived and minted per run.
- The federated credential's subject is scoped to a GitHub **environment**, not a branch, and names the repository by its immutable ID: `repo:OWNER@OWNER_ID/azure-hub-spoke-landing-zone@REPO_ID:environment:production`. Repositories created before 15 July 2026 use the name-only form, `repo:OWNER/azure-hub-spoke-landing-zone:environment:production`.
- Pull requests get **no** Azure credentials. Only manual dispatch does.
- Roles are granted on the day of deployment and removed the same day.
- Never grant Microsoft Graph `Application.ReadWrite.All`. It is tenant-wide app management, unrelated to deploying infrastructure.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `MissingSubscriptionRegistration` | AzureRM 5.x no longer auto-registers providers | Step 3 |
| `403` / `AuthorizationPermissionMismatch` on `init` | Contributor is control plane only | Grant Storage Blob Data Contributor, wait 5 minutes |
| Storage account name rejected | Not globally unique, or contains a hyphen | 3–24 chars, lowercase alphanumeric only |
| `azure/login` fails, no `ACTIONS_ID_TOKEN_REQUEST_URL` | `permissions: id-token: write` missing | Add it at workflow or job level |
| OIDC token rejected, no useful detail | Subject claim mismatch | Compare the credential with the `subject claim` line the `azure/login` step prints. New repositories embed IDs: `repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:production` |
| CI fails on missing variables | `.tfvars` is gitignored, correctly | Set `TF_VAR_*` from secrets at job level |
| Peering stuck at `Initiated` | Only one direction was created | Peering is two resources; the module creates both |
| Everything blocked despite an allow rule | Deny numbered below the allow | Catch-all belongs at 4096, allows beneath it |
| `for_each` refuses the map or set | A key that is only known after apply | Build the keys from variables. An apply-time value may be a map value, never a key or a set element |
| `RequestDisallowedByPolicy` on your own apply | Resource missing the `Project` tag | Add it to `var.tags` |
| `terraform test` fails to authenticate | The azurerm provider authenticates during plan | `az login` first, and export `ARM_SUBSCRIPTION_ID` |
| Step 21 `$SAID` / `$SPOID` are empty | Shell variables die with the terminal tab | Stay in one terminal, or re-derive from `terraform output` |

### Platform-specific

| Symptom | Cause | Fix |
|---|---|---|
| VS Code terminal cannot see `az` / `terraform` / `gh` | VS Code is the Flatpak or Snap build, which is sandboxed | Install the `.deb`/`.msi` from the vendor |
| `terraform version` is not the expected version | A distro package shadows `/usr/local/bin` on `PATH` | `which -a terraform`, remove the other one |
| `az login` hangs with no browser | Headless or SSH session | `az login --use-device-code` |
| `does not have a Release file` on `apt update` | A derivative distro's codename is not in the upstream pool | Point the repo at the upstream Debian/Ubuntu codename |

## Why the design excludes these

Every exclusion here is a deliberate trade-off.

| Excluded | Why |
|---|---|
| VM, disk, NIC, public IP, Bastion | Cost and attack surface. A public IPv4 bills roughly $3.65/month whether or not it is attached to anything. |
| NAT gateway, VPN/ExpressRoute gateway, Azure Firewall | Metered services, incompatible with a zero-standing-cost build |
| Private endpoint | A good production pattern, but needs a private runner and more infrastructure than this project scopes |
| Key Vault, Log Analytics | Not required to demonstrate the platform, and adds teardown surface |
| Resource locks, `prevent_destroy` | Would obstruct same-session teardown. Structural state separation does the same job without the friction. |
| Azure credentials on pull requests | Public PR validation stays cloud-neutral and unable to mutate Azure |
| Spoke-to-spoke peering | Its absence is the isolation proof. Peering is non-transitive, so `dev → hub → prod` does not route. |

## What this costs

Nothing in this design carries a standing charge. VNets, subnets, NSGs and peerings are free to exist; peering bills only on data transferred, and no compute exists to transfer any. The storage account bills per GB and per transaction — a few kilobytes of state for one session rounds to zero.

Expect a few cents to appear in billing 24–48 hours later from blob transactions. That is why the honest claim is "nothing remains capable of a recurring charge", not "$0.00".
