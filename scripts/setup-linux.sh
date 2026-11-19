#!/usr/bin/env bash
#
# setup-linux.sh - install Terraform, Azure CLI, GitHub CLI and Git on a
# Debian-family system (Debian, Ubuntu, Linux Mint, LMDE).
#
# Safe to re-run. Installs nothing that is already present at a usable version.
# Run from the repository root:   ./scripts/setup-linux.sh
#
set -euo pipefail

TERRAFORM_MIN="1.9.0"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Do not run this as root. It calls sudo only where needed."
command -v sudo >/dev/null || die "sudo is required."
command -v apt-get >/dev/null || die "This script targets Debian-family systems. On Fedora, Arch or macOS, install the four tools with your own package manager."

# ---------------------------------------------------------------------------
# Work out which upstream codename the package pools actually publish for.
#
# Derivatives ship their own codename - LMDE 7 is "gigi", Mint 22 is "wilma" -
# and neither Debian nor Microsoft publishes a pool under those names. Every
# Debian-family release records the upstream codename it is built on in
# /etc/os-release as DEBIAN_CODENAME or UBUNTU_CODENAME. That is the value the
# repositories need.
# ---------------------------------------------------------------------------
. /etc/os-release
CODENAME="${DEBIAN_CODENAME:-${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}}"
[[ -n "$CODENAME" ]] || die "Could not determine an upstream codename from /etc/os-release."

case "${ID:-}:${ID_LIKE:-}" in
  ubuntu:*|*:*ubuntu*) DISTRO="ubuntu" ;;
  *)                   DISTRO="debian" ;;
esac

info "Detected ${PRETTY_NAME:-unknown} -> using $DISTRO pool, codename '$CODENAME'"

ARCH="$(dpkg --print-architecture)"
KEYRINGS=/etc/apt/keyrings
sudo install -m 0755 -d "$KEYRINGS"

info "Installing prerequisites"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  ca-certificates curl gnupg lsb-release unzip apt-transport-https git

# ---------------------------------------------------------------------------
# Terraform - HashiCorp apt repository
# ---------------------------------------------------------------------------
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

if command -v terraform >/dev/null && \
   version_ge "$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version":"\([^"]*\)".*/\1/p')" "$TERRAFORM_MIN"; then
  ok "Terraform $(terraform version -json | sed -n 's/.*"terraform_version":"\([^"]*\)".*/\1/p') already installed"
else
  info "Installing Terraform"
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o "$KEYRINGS/hashicorp.gpg"
  sudo chmod a+r "$KEYRINGS/hashicorp.gpg"
  echo "deb [arch=$ARCH signed-by=$KEYRINGS/hashicorp.gpg] https://apt.releases.hashicorp.com $CODENAME main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq terraform
fi

# ---------------------------------------------------------------------------
# Azure CLI - Microsoft apt repository
#
# The azure-cli pool lags behind new Debian releases. If there is no build for
# our codename, fall back to bookworm: the package is pure Python, so the
# codename affects only which pool apt reads, not what gets installed.
# ---------------------------------------------------------------------------
if command -v az >/dev/null; then
  ok "Azure CLI already installed"
else
  info "Installing Azure CLI"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | sudo gpg --dearmor -o "$KEYRINGS/microsoft.gpg"
  sudo chmod a+r "$KEYRINGS/microsoft.gpg"

  AZ_CODENAME="$CODENAME"
  if ! curl -fsI "https://packages.microsoft.com/repos/azure-cli/dists/$CODENAME/Release" >/dev/null 2>&1; then
    warn "No azure-cli pool published for '$CODENAME' - falling back to 'bookworm'"
    AZ_CODENAME="bookworm"
  fi

  echo "deb [arch=$ARCH signed-by=$KEYRINGS/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_CODENAME main" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq azure-cli
fi

# ---------------------------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------------------------
if command -v gh >/dev/null; then
  ok "GitHub CLI already installed"
else
  info "Installing GitHub CLI"
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee "$KEYRINGS/githubcli.gpg" >/dev/null
  sudo chmod a+r "$KEYRINGS/githubcli.gpg"
  echo "deb [arch=$ARCH signed-by=$KEYRINGS/githubcli.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh
fi

# ---------------------------------------------------------------------------
# TFLint - single binary, no repository
# ---------------------------------------------------------------------------
if command -v tflint >/dev/null; then
  ok "TFLint already installed"
else
  info "Installing TFLint"
  curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo
info "Versions"
for t in terraform az gh git tflint; do
  if command -v "$t" >/dev/null; then
    case "$t" in
      az) printf '  %-10s %s\n' "$t" "$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo installed)" ;;
      *)  printf '  %-10s %s\n' "$t" "$("$t" --version 2>/dev/null | head -1)" ;;
    esac
  else
    warn "$t is NOT on PATH"
  fi
done

# A distro package shadowing /usr/local/bin is the classic "wrong version" cause.
if command -v terraform >/dev/null && [[ $(which -a terraform | wc -l) -gt 1 ]]; then
  echo
  warn "More than one terraform on PATH:"
  which -a terraform | sed 's/^/    /'
  warn "Remove the one you do not want, or the wrong version will run."
fi

echo
ok "Done. Next: Step 2 of GUIDE.md - az login"
