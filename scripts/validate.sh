#!/usr/bin/env bash
#
# validate.sh - the full offline check. Contacts Azure only for `terraform test`,
# which authenticates but creates nothing (command = plan).
#
# Run from the repository root:   ./scripts/validate.sh
#                                 ./scripts/validate.sh --no-test   (fully offline)
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RUN_TESTS=1
[[ "${1:-}" == "--no-test" ]] && RUN_TESTS=0

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

command -v terraform >/dev/null || die "terraform is not on PATH. Run ./scripts/setup-linux.sh (Step 1 of GUIDE.md)."

info "terraform fmt"
terraform fmt -check -recursive || {
  printf '\033[1;33m  !\033[0m Formatting differences found. Fixing them now:\n'
  terraform fmt -recursive
  ok "reformatted - review the diff before committing"
}

# -backend=false guarantees no Azure connection is attempted.
for root in bootstrap envs/prod; do
  info "terraform validate ($root)"
  ( cd "$root" && terraform init -backend=false -no-color >/dev/null && terraform validate -no-color )
  ok "$root"
done

if command -v tflint >/dev/null; then
  info "tflint"
  tflint --init >/dev/null
  tflint --recursive --format compact && ok "tflint clean"
else
  printf '\033[1;33m  !\033[0m tflint not installed - skipping lint\n'
fi

if [[ $RUN_TESTS -eq 1 ]]; then
  info "terraform test (modules/nsg)"
  if ! az account show >/dev/null 2>&1; then
    printf '\033[1;33m  !\033[0m Not signed in to Azure. Run `az login`, or pass --no-test.\n'
    printf '      The azurerm provider authenticates during plan, so the tests need a session.\n'
    printf '      They still create nothing.\n'
    exit 1
  fi
  export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  ( cd modules/nsg && terraform init -backend=false -no-color >/dev/null && terraform test )
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
