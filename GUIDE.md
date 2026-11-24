# Deployment guide — Azure Hub-and-Spoke Landing Zone

This is the procedure that produced the deployment recorded in [`docs/evidence/`](docs/evidence/README.md). It takes the repository from a clean clone to a verified deployment and back to an empty subscription.

Every step ends with a **Done when** check. A step is not complete until its check is true.

| Phase | Steps | What happens |
|---|---|---|
| **Prerequisites** | 1–4 | Tools, sign-in, spending limit, resource providers |
| **Repository and offline validation** | 5–9 | Budget alert, repository, design review, validation, unit tests |
| **CI and identity federation** | 10–13 | CI, repository protection, OIDC federation |
| **Deploy, verify, tear down** | 14–22 | Bootstrap, pipeline plan and apply, verification from Azure, evidence, teardown |

**Ground rules:**

1. Nothing is created in Azure before Step 14. Everything earlier is offline or account setup.
2. Teardown is part of the deployment. Steps 14 to 22 are done in one sitting.
3. The repository is public from the first commit. A `.tfvars` file, a state file or a secret is never committed.
4. If the subscription has a spending limit (free trial and credit subscriptions do), it stays **on**. While it is on, Azure disables the subscription instead of charging a card.

## Checklist

**Prerequisites**
- [ ] 1 — Tools installed
- [ ] 2 — Signed in to Azure, subscription pinned
- [ ] 3 — Spending limit checked, providers registered
- [ ] 4 — Signed in to GitHub

**Repository and offline validation**
- [ ] 5 — Budget alert set
- [ ] 6 — Repository created
- [ ] 7 — Design reviewed against the code
- [ ] 8 — Offline validation passes
- [ ] 9 — Unit tests pass and have been seen to fail, first commit pushed

**CI and identity federation**
- [ ] 10 — CI green
- [ ] 11 — Repository protected, `production` environment created
- [ ] 12 — OIDC federated credential created
- [ ] 13 — Three identifier secrets stored

**Deploy, verify, tear down**
- [ ] 14 — Bootstrap applied
- [ ] 15 — Blob access granted, state container created
- [ ] 16 — Pipeline roles granted, last three secrets stored
- [ ] 17 — Remote plan shows 29 to add
- [ ] 18 — Apply green
- [ ] 19 — Verified from live Azure
- [ ] 20 — Evidence captured
- [ ] 21 — Everything torn down
- [ ] 22 — Deployment recorded

---

## Prerequisites

### Step 1 — Install the tools

Four tools must be on `PATH`: **Terraform**, **Azure CLI**, **GitHub CLI** and **Git**. TFLint is needed for Step 8.

On Debian, Ubuntu, Mint or LMDE the bundled installer sets up the package repositories and installs all of them:

```bash
chmod +x scripts/*.sh
./scripts/setup-linux.sh
```

Then confirm:

```bash
terraform version
az version
gh --version
git --version
```

Three things go wrong on Debian-family systems. The script handles all three:

- **VS Code installed as a Flatpak or Snap.** The sandbox hides `az`, `terraform` and `gh` from the integrated terminal. Use the `.deb` from `packages.microsoft.com`.
- **Derivative codenames.** Mint and LMDE use their own codename (LMDE 7 is `gigi`), which exists in no Debian or Microsoft package pool. The repositories must point at the upstream codename (`trixie` for LMDE 7), or `apt update` fails with `does not have a Release file`.
- **The `azure-cli` pool lags** behind new Debian releases. Where there is no build for a codename, `bookworm` works: the package is pure Python.

On Fedora, Arch or macOS, install the tools from the vendors' instructions and skip the script. Nothing else in this guide depends on it.

**Done when** all four commands print a version, and `which -a terraform` shows exactly one path.

---

### Step 2 — Sign in and pin the subscription

```bash
az login
az account set --subscription "<subscription-id>"
az account show --output table
```

Without a browser (SSH or headless): `az login --use-device-code`.

**Done when** `az account show` prints the intended subscription.

---

### Step 3 — Confirm the spending limit and register providers

Portal → **Subscriptions → the subscription → Overview**. If a spending limit is shown, it must read **On**. Pay-as-you-go subscriptions have no spending limit. The budget alert in Step 5 is the guard there, and nothing in this deployment carries a standing charge.

AzureRM 5.x does not register resource providers automatically. Without this, Step 14 fails with `MissingSubscriptionRegistration`:

```bash
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage

az provider show --namespace Microsoft.Network --query registrationState -o tsv
az provider show --namespace Microsoft.Storage --query registrationState -o tsv
```

Registration takes a few minutes.

**Done when** both commands print `Registered`.

---

### Step 4 — Sign in to GitHub

```bash
gh auth login
gh auth status
```

**Done when** `gh auth status` shows a signed-in account with the `repo` and `workflow` scopes.

---

## Repository and offline validation

### Step 5 — Set a budget alert

Portal → **Cost Management + Billing → Budgets → Add**. Amount **$5**, alerts at **50%** and **90%**, sent to a monitored address.

This deployment creates nothing with a standing charge, so the budget should never fire. If it does, something is deployed that should not be: go to Step 21.

**Done when** the budget exists with a recipient.

---

### Step 6 — Create the repository

From the repository root:

```bash
git init -b main
gh repo create azure-hub-spoke-landing-zone --public --source=. --remote=origin
```

Before the first commit, confirm the ignore rules are in effect:

```bash
git status --porcelain | grep -E '\.tfvars$|\.tfstate' || echo "clean - no secrets staged"
```

**Done when** that prints `clean - no secrets staged`.

---

### Step 7 — Review the design before deploying

Each file carries one or two design decisions. Confirm the code does what this table says before running any of it. The reasoning is in a comment next to the code, and again in [`REFERENCE.md`](REFERENCE.md).

| File | What to confirm |
|---|---|
| `bootstrap/main.tf` | The state storage account lives in a different root module from the network, so a workload destroy cannot delete its own backend. |
| `bootstrap/main.tf` | `shared_access_key_enabled = false`: the account refuses Shared Key authorization, so blob access is Entra ID data-plane RBAC and nothing else. |
| `modules/nsg/main.tf` | The catch-all deny sits at priority 4096, the last rule Azure evaluates. Every allow is evaluated first, and a broken allow fails closed. |
| `modules/nsg/variables.tf` | The `validation` block rejects, at plan time, any tier rule whose priority falls outside 101 to 4095. |
| `modules/network/main.tf` | Subnets use `for_each`, keyed by name, so removing one does not re-index and recreate the others. |
| `modules/peering/main.tf` | Each logical peering is two resources, one per direction. A single direction stays `Initiated` and carries no traffic. |
| `envs/prod/main.tf` | Every `for_each` key is built from variables, so it is known at plan time. The IDs the modules return, unknown until apply, are looked up inside the resource bodies. |
| `envs/prod/main.tf` | There is no `azurerm_resource_group`. The workload group belongs to bootstrap, so this module cannot delete the group it deploys into. |

**Done when** the code matches every row.

---

### Step 8 — Validate offline

One script wraps this step:

```bash
./scripts/validate.sh --no-test     # fmt, validate, tflint - fully offline
```

It runs the following. Nothing here contacts Azure; `-backend=false` is what guarantees that.

```bash
terraform fmt -recursive

(cd bootstrap && terraform init -backend=false && terraform validate)
(cd envs/prod && terraform init -backend=false && terraform validate)
```

The subshells keep a failure from leaving the shell in the wrong directory.

Then lint:

```bash
tflint --init
tflint --recursive
```

**Done when** both `validate` runs print `Success!` and tflint prints nothing.

---

### Step 9 — Run the unit tests, and prove they can fail

```bash
cd modules/nsg
terraform init -backend=false
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform test
```

Expect `Success! 4 passed, 0 failed.` (`./scripts/validate.sh` runs Steps 8 and 9 in one pass.)

> `terraform test` needs an authenticated session, because the azurerm provider authenticates during plan. It still creates nothing: `command = plan` asserts against the plan graph only.

A test that has never been seen failing is not a test that can be trusted. In `modules/nsg/main.tf`, change the `deny_all_inbound` priority from `4096` to `100` and run `terraform test` again. The first test must fail with the error message written for it. Restore the value and confirm 4 pass.

Commit:

```bash
cd ../..
git add .
git commit -m "feat: bootstrap, network, nsg and peering modules with unit tests"
git push -u origin main
```

**Done when:**
- [ ] The repository is reachable without signing in
- [ ] `terraform validate` passes in both root modules, offline
- [ ] 4 tests pass, and one has been seen failing
- [ ] No `.tfvars`, state file or secret is committed
- [ ] Nothing exists in Azure

---

## CI and identity federation

Still nothing deployed.

### Step 10 — Get CI green

The push in Step 9 started `.github/workflows/ci.yml`. Watch it finish:

```bash
gh run watch
```

That workflow has no `id-token` permission and no Azure secrets. The repository is public, and validation, linting and scanning do not need cloud access, so they do not get it.

**Done when** the **Validate and scan** job is green on `main`.

---

### Step 11 — Protect the repository

- **Settings → Branches → Add rule** on `main`: require the **Validate and scan** status check, and require a pull request before merging. In a single-maintainer repository, set the number of required approvals to zero, or nothing can be merged.
- **Settings → Actions → General**: workflow permissions read-only by default.
- **Settings → Environments → New environment**: name it exactly **`production`**, with a **required reviewer**.

From here on, every change reaches `main` through a pull request that has passed the check.

The environment is what the rest depends on. Every run that touches Azure now pauses for approval, and the federated credential in Step 12 is scoped to this environment name.

**Done when** all three are set and the environment is named `production`.

---

### Step 12 — Federate GitHub to Entra ID with OIDC

A client secret is a long-lived credential stored in GitHub: something to rotate, and something to leak. With OIDC, GitHub mints a short-lived token for each run, and Entra ID validates it against a **federated credential** whose subject claim limits exactly which repository and environment may use it.

The subject is not always `repo:<owner>/<repo>`. Repositories created after 15 July 2026 issue an **immutable** subject that carries the numeric owner and repository IDs, `repo:<owner>@<owner-id>/<repo>@<repo-id>`, so a renamed or re-created repository cannot inherit the trust. Ask GitHub which form this repository uses:

```bash
REPO="<github-username>/azure-hub-spoke-landing-zone"
SUBID=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)

# The prefix GitHub puts in this repository's tokens. Older repositories do not
# report one, and fall back to the name-based form.
PREFIX=$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty')
PREFIX=${PREFIX:-repo:$REPO}

APPID=$(az ad app create --display-name "gh-azure-hub-spoke-landing-zone" --query appId -o tsv)
az ad sp create --id "$APPID"

cat > /tmp/fedcred.json <<JSON
{
  "name": "gh-azure-hub-spoke-landing-zone",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "${PREFIX}:environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON

az ad app federated-credential create --id "$APPID" --parameters @/tmp/fedcred.json
rm /tmp/fedcred.json

az ad app federated-credential list --id "$APPID" --query "[].{name:name,subject:subject}" -o table
```

The body is passed as a file (`@path`), so no layer of shell quoting can alter the subject claim. Read the output and confirm the subject is that prefix followed by `:environment:production`, character for character. A mismatch surfaces in Step 17 as a token rejection with no useful detail. The quickest diagnosis is the `subject claim` line that the `azure/login` step prints, which is what GitHub actually presented.

This application is never granted Microsoft Graph `Application.ReadWrite.All`. That is tenant-wide application management and has nothing to do with deploying infrastructure.

**Done when** exactly one federated credential exists, with the correct subject.

---

### Step 13 — Store the identifiers

None of these is a secret. They are identifiers, kept in GitHub secrets because that is where the workflow reads them.

```bash
gh secret set AZURE_CLIENT_ID       --body "$APPID"
gh secret set AZURE_TENANT_ID       --body "$TENANT"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBID"
```

`TFSTATE_RG`, `TFSTATE_STORAGE_ACCOUNT` and `WORKLOAD_RG` are set in Step 16, once those resources exist.

**Role assignments wait until Step 16.** Access to resources that do not exist yet serves no purpose, and standing permissions left in place between sessions are what this design avoids.

**Done when:**
- [ ] CI is green, with no Azure credentials in that workflow
- [ ] Branch protection requires the check
- [ ] The `production` environment exists with a required reviewer
- [ ] One federated credential exists, scoped to that environment
- [ ] Three identifier secrets are set
- [ ] Still nothing deployed

---

## Deploy, verify, tear down

Run Steps 14 to 21 in one shell session. Later steps reuse variables set by earlier ones, and re-deriving them in the middle of a teardown is how the wrong scope gets deleted.

If the deployment cannot be completed, go to Step 21 and remove what exists. A complete repository with nothing deployed is a fine outcome. A partial environment that nobody can account for is not.

---

### Step 14 — Confirm the session and apply bootstrap

```bash
az login
az account set --subscription "<subscription-id>"
az provider show --namespace Microsoft.Network --query registrationState -o tsv
az provider show --namespace Microsoft.Storage --query registrationState -o tsv
```

Both must read `Registered`.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set the real subscription_id

terraform init
terraform plan
terraform apply

terraform output
```

Four resources: two resource groups, a random string and a storage account.

**Done when** `terraform output` prints the four values.

---

### Step 15 — Grant blob access, then create the container

Azure has two permission planes, and this step is where they are most often confused. **Contributor is control plane**: it manages the storage account but cannot read or write the blobs inside it. Terraform's blob backend is a **data-plane** operation. With `shared_access_key_enabled = false` the account's keys are refused, so a data-plane RBAC role is the only way in.

```bash
SA=$(terraform output -raw storage_account_name)
STRG=$(terraform output -raw state_resource_group)
SAID=$(terraform output -raw storage_account_id)
WLRG=$(terraform output -raw workload_resource_group)
SUBID=$(az account show --query id -o tsv)
ME=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --assignee "$ME" \
  --role "Storage Blob Data Contributor" \
  --scope "$SAID"
```

RBAC propagation is not instant. Allow up to five minutes: an immediate retry returns a misleading 403.

```bash
az storage container create --name tfstate --account-name "$SA" --auth-mode login
az storage container show   --name tfstate --account-name "$SA" --auth-mode login -o table

cd ..    # back to the repository root; the variables above stay set
```

**Done when** the container shows as existing.

---

### Step 16 — Grant the pipeline exactly two roles, then store the last three secrets

```bash
APPID=$(az ad app list --display-name "gh-azure-hub-spoke-landing-zone" --query "[0].appId" -o tsv)
SPOID=$(az ad sp show --id "$APPID" --query id -o tsv)

# Control plane, scoped to the workload resource group only.
az role assignment create \
  --assignee-object-id "$SPOID" --assignee-principal-type ServicePrincipal \
  --role "Network Contributor" \
  --scope "/subscriptions/$SUBID/resourceGroups/$WLRG"

# Data plane, scoped to the state storage account only.
az role assignment create \
  --assignee-object-id "$SPOID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$SAID"
```

**Network Contributor at resource-group scope**, not Contributor at subscription scope. The pipeline only ever touches networking inside one resource group, so that is all it is given.

```bash
gh secret set TFSTATE_RG              --body "$STRG"
gh secret set TFSTATE_STORAGE_ACCOUNT --body "$SA"
gh secret set WORKLOAD_RG             --body "$WLRG"
```

**Done when** `gh secret list` shows all six.

---

### Step 17 — Plan through the pipeline, and read the plan

```bash
gh workflow run azure-lifecycle.yml -f action=plan -f confirm=plan
```

Approve the `production` environment when GitHub asks.

Expect **29 resources**: 3 VNets, 4 subnets, 4 NSGs, 10 NSG rules, 4 subnet associations, 4 peerings.

Read the plan and confirm two things:
1. Every NSG shows `DenyAllInbound` at priority 4096.
2. Nothing resembling a VM, public IP, NAT gateway, firewall or VPN gateway appears.

**Done when** the plan shows 29 to add, 0 to change, 0 to destroy, and both points are confirmed.

---

### Step 18 — Apply

```bash
gh workflow run azure-lifecycle.yml -f action=apply -f confirm=apply
gh run watch
```

The workflow runs the unit tests, applies, then asserts NSG posture and the absence of billable resources against **live Azure**, not against Terraform state. All of it must pass.

**Done when** the run is green end to end.

---

### Step 19 — Verify from Azure, not from Terraform

Terraform reporting success is not evidence. Ask Azure.

```bash
WLRG="rg-lz-workload-cac-001"

az network vnet list -g "$WLRG" \
  --query "[].{Name:name,Cidr:addressSpace.addressPrefixes[0]}" -o table

for v in $(az network vnet list -g "$WLRG" --query "[].name" -o tsv); do
  az network vnet peering list --vnet-name "$v" -g "$WLRG" \
    --query "[].{Vnet:'$v',Peer:name,State:peeringState}" -o table
done

for n in $(az network nsg list -g "$WLRG" --query "[].name" -o tsv); do
  az network nsg rule list --nsg-name "$n" -g "$WLRG" \
    --query "sort_by([],&priority)[].{Nsg:'$n',Priority:priority,Name:name,Access:access}" -o table
done
```

Confirm: three VNets, four peerings all `Connected`, and `DenyAllInbound` at 4096 as the highest-numbered rule on every NSG.

There is deliberately **no dev-to-prod peering**. That is the isolation proof: peering is non-transitive, so `dev → hub → prod` does not route even though both spokes reach the hub.

**Done when** all three checks match.

---

### Step 20 — Capture evidence

Save the output of Steps 17 to 19 and a screenshot of each pipeline run to `docs/evidence/`: the plan, the apply with its two verification steps, and the read-back from Azure.

Redact the subscription ID, tenant ID, client ID and the storage account name before committing anything. Edit nothing else.

**Done when** the captured output and the run screenshots are in `docs/evidence/`, redacted.

---

### Step 21 — Tear down, in this order

Order matters: destroy the workload while OIDC still works, then revoke access, then remove bootstrap.

```bash
# 1. Workload, through the pipeline that created it
gh workflow run azure-lifecycle.yml -f action=destroy -f confirm=destroy
gh run watch

az resource list -g "$WLRG" -o table    # expect empty
```

```bash
# 2. Remove the pipeline's access and identity
az role assignment delete --assignee-object-id "$SPOID" --scope "/subscriptions/$SUBID/resourceGroups/$WLRG"
az role assignment delete --assignee-object-id "$SPOID" --scope "$SAID"
az ad app delete --id "$APPID"
```

```bash
# 3. Bootstrap last - it owns the state and both resource groups
cd bootstrap
terraform destroy

az group list -o table                  # no rg-lz-* groups remain
```

```bash
# 4. Remove the identifiers stored in GitHub
for s in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID \
         TFSTATE_RG TFSTATE_STORAGE_ACCOUNT WORKLOAD_RG; do
  gh secret delete "$s"
done
```

The workflows stay in the repository. Without secrets or a federated credential they cannot reach anything.

Two things outlive those four steps, and neither belongs to this deployment:

- `az group list` may still show a `NetworkWatcherRG`. Azure creates it by itself the first time a virtual network appears in a region. It is free. To leave the subscription empty: `az group delete --name NetworkWatcherRG --yes`.
- `az ad app delete` moves the app registration to the directory's recycle bin for 30 days. It can no longer sign in, and it purges itself.

**Done when:**
- [ ] `az group list` shows no `rg-lz-*` group
- [ ] The Entra application no longer exists
- [ ] `gh secret list` is empty

---

### Step 22 — Record the deployment

Add the evidence status under the introduction in `README.md`:

> Deployed and verified on `<date>`, then removed. No Azure resource remains.

`main` is protected, so the record goes in through a pull request like any other change:

```bash
git switch -c docs/deployment-evidence
git add .
git commit -m "docs: deployment evidence and verified teardown"
git push -u origin docs/deployment-evidence

gh pr create --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
git switch main && git pull
```

Then, 48 hours later:

```bash
az consumption usage list --output table
```

Billing data lags by hours. A few cents from blob transactions is expected. The claim is "nothing remains that can incur a recurring charge", not "$0.00".

---

## Troubleshooting

[`REFERENCE.md`](REFERENCE.md) has a symptom, cause and fix table for the errors this deployment can produce, along with the naming conventions, tag rules and the NSG priority table.

## Extending this

In rough order of value:

1. **Drift detection.** Delete a subnet in the portal and run the `plan` action. Terraform reports the drift.
2. **Policy.** Add a resource-group-scoped Azure Policy initiative (allowed locations and a required `Project` tag, Deny effect), and verify it by creating a VNet in another region, which must fail with `RequestDisallowedByPolicy`.
3. **A third spoke.** One entry in the `spokes` map and no module changes, which is what `for_each` buys.
