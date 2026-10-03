#!/usr/bin/env bash
# Nomad preflight: runs on YOUR computer (macOS or Linux) at the start of
# `make up`, so a fresh clone needs nothing installed beforehand. Checks, and
# offers to fix:
#   1. AWS CLI (installs the latest official build)
#   2. Terraform >= 1.11 (installs the latest)
#   3. Signed in to AWS (create an account, or sign in with your console login
#      or access keys)
#   4. Tailscale on this computer (installs it, signs you in or up): it is how
#      you reach the box
# Safe to re-run; it only acts on what is missing. Written for bash 3.2 (macOS).
set -uo pipefail
export AWS_PAGER="" # never let the AWS CLI open a pager (less) mid-flow

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"

OS="$(uname -s)"
ARCH="$(uname -m)"
BIN="$HOME/.local/bin" # where we put tools we download, when not using a package manager
export PATH="$BIN:$PATH"

ok()   { printf '  %s✓%s %-18s %s%s%s\n' "$LIVE" "$R" "$1" "$DIM" "${2:-}" "$R"; }
bad()  { printf '  %s✗%s %-18s %s%s%s\n' "$BAD" "$R" "$1" "$DIM" "${2:-}" "$R"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$R"; }
die()  { printf '\n  %s%s%s\n\n' "$BAD" "$1" "$R"; exit 1; }
ask()  { # question -> 0 for yes (the default)
  [ -t 0 ] || return 1
  local a; printf '    %s›%s %s %s[Y/n]%s ' "$ACC" "$R" "$1" "$FAINT" "$R"; read -r a || return 1 # no answer = no
  case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac
}
pause() { [ -t 0 ] || return 1; printf '    %s›%s %s ' "$ACC" "$R" "$1"; read -r _; }
have() { command -v "$1" >/dev/null 2>&1; }
# version_ge 2.32.0 2.27.43 -> is the second at least the first?
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]; }

# --- installers ---------------------------------------------------------------

install_aws() {
  local tmp; tmp="$(mktemp -d)"
  case "$OS" in
    Darwin)
      curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$tmp/AWSCLIV2.pkg" &&
        info "macOS asks for your password to install the package." &&
        sudo installer -pkg "$tmp/AWSCLIV2.pkg" -target / >/dev/null ;;
    Linux)
      local a=x86_64; case "$ARCH" in aarch64|arm64) a=aarch64 ;; esac
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$a.zip" -o "$tmp/aws.zip" &&
        unzip -qo "$tmp/aws.zip" -d "$tmp" && sudo "$tmp/aws/install" --update >/dev/null ;;
    *) false ;;
  esac
  local rc=$?; rm -rf "$tmp"; hash -r; return $rc
}

install_terraform() {
  if [ "$OS" = Darwin ] && have brew; then
    brew install hashicorp/tap/terraform >/dev/null && return 0
  fi
  local v os a tmp
  v="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | sed -E 's/.*"current_version":"([^"]+)".*/\1/')"
  [ -n "$v" ] || return 1
  os="$(echo "$OS" | tr '[:upper:]' '[:lower:]')"
  case "$ARCH" in aarch64|arm64) a=arm64 ;; *) a=amd64 ;; esac
  tmp="$(mktemp -d)"
  curl -fsSL "https://releases.hashicorp.com/terraform/$v/terraform_${v}_${os}_${a}.zip" -o "$tmp/tf.zip" &&
    unzip -qo "$tmp/tf.zip" -d "$tmp" && mkdir -p "$BIN" && install -m 755 "$tmp/terraform" "$BIN/terraform"
  local rc=$?; rm -rf "$tmp"; hash -r; return $rc
}

install_tailscale() {
  local tmp; tmp="$(mktemp -d)"
  case "$OS" in
    Darwin)
      # The standalone app (Tailscale's recommended macOS build); it includes the CLI.
      curl -fsSL "https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg" -o "$tmp/Tailscale.pkg" &&
        info "macOS asks for your password to install the package." &&
        sudo installer -pkg "$tmp/Tailscale.pkg" -target / >/dev/null ;;
    Linux) curl -fsSL https://tailscale.com/install.sh | sh ;;
    *) false ;;
  esac
  local rc=$?; rm -rf "$tmp"; hash -r; return $rc
}

# Signs this computer in (opens the browser). On macOS the app must be running
# for its CLI to work.
tailscale_login() {
  local ts; ts="$(tailscale_cli)"
  case "$OS" in
    Darwin) open -a Tailscale 2>/dev/null; sleep 3; "$ts" up ;;
    *)      sudo "$ts" up ;;
  esac
}

tailscale_cli() {
  if have tailscale; then echo tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then echo /Applications/Tailscale.app/Contents/MacOS/Tailscale
  fi
}

# --- checks -------------------------------------------------------------------

printf '\n'; nomad_header "setup" "checking this computer"; printf '\n'

# 1. AWS CLI
if have aws; then
  ok "AWS CLI" "$(aws --version 2>&1 | cut -d' ' -f1 | cut -d/ -f2)"
else
  bad "AWS CLI" "not installed"
  ask "Install the latest AWS CLI?" || die "The AWS CLI is needed to create the box: https://aws.amazon.com/cli/"
  install_aws && have aws || die "Installing the AWS CLI failed. Install it from https://aws.amazon.com/cli/ and re-run make up."
  ok "AWS CLI" "$(aws --version 2>&1 | cut -d' ' -f1 | cut -d/ -f2) installed"
fi

# 2. Terraform
tf_v="$(terraform version 2>/dev/null | head -1 | sed -E 's/^Terraform v//')"
if [ -n "$tf_v" ] && version_ge 1.11.0 "$tf_v"; then
  ok "Terraform" "$tf_v"
else
  bad "Terraform" "${tf_v:+$tf_v is too old (need 1.11+)}${tf_v:-not installed}"
  ask "Install the latest Terraform?" || die "Terraform 1.11+ is needed: https://developer.hashicorp.com/terraform/install"
  install_terraform || die "Installing Terraform failed. Install it from https://developer.hashicorp.com/terraform/install"
  ok "Terraform" "$(terraform version | head -1 | sed -E 's/^Terraform v//') installed"
fi

# 3. Signed in to AWS
aws_who() { aws sts get-caller-identity --query '[Account, Arn]' --output text 2>/dev/null; }
until who="$(aws_who)"; do
  bad "AWS account" "not signed in"
  [ -t 0 ] || die "Sign in to AWS (aws login, or aws configure) and re-run make up."
  info "No AWS account yet? Create one (free to start), then come back:"
  info "  https://signin.aws.amazon.com/signup?request_type=register"
  printf '\n    %s1%s  Sign in with your AWS console login %s(email or root; opens a browser)%s\n' "$ACC" "$R" "$FAINT" "$R"
  printf '    %s2%s  Use access keys %s(from IAM: access key ID + secret)%s\n' "$ACC" "$R" "$FAINT" "$R"
  printf '    %sq%s  Quit\n\n    %s›%s ' "$ACC" "$R" "$ACC" "$R"
  read -r choice || die "No answer. Sign in to AWS (aws login, or aws configure) and re-run make up."
  case "$choice" in
    1)
      # `aws login` (console credentials) arrived in AWS CLI 2.32.
      v="$(aws --version 2>&1 | cut -d' ' -f1 | cut -d/ -f2)"
      if ! version_ge 2.32.0 "$v"; then
        info "Console sign-in needs AWS CLI 2.32+ (you have $v)."
        ask "Update the AWS CLI now?" && install_aws || continue
      fi
      aws login --region "${TF_VAR_region:-us-east-1}" ;;
    2) aws configure ;;
    q|Q) die "Stopped. Re-run make up when you are ready." ;;
  esac
done
ok "AWS account" "$(echo "$who" | awk '{print $1}') · $(echo "$who" | awk '{print $2}' | sed 's/.*:\(.*\)/\1/')"

# 4. Tailscale on this computer: the box has no public ports, so this is how you
# (and make up) reach it. The app and the `tailscale` CLI share one background
# service, so signing in with either signs in both.
ts_state() { local ts; ts="$(tailscale_cli)"; [ -n "$ts" ] && "$ts" status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -1; }
if [ -z "$(tailscale_cli)" ]; then
  bad "Tailscale" "not installed on this computer"
  info "The box has no public ports: you reach it over your Tailscale network."
  ask "Install Tailscale (the official app and CLI)?" || die "Install Tailscale from https://tailscale.com/download and re-run make up."
  install_tailscale && [ -n "$(tailscale_cli)" ] || die "Installing Tailscale failed. Install it from https://tailscale.com/download"
  ok "Tailscale" "installed"
fi
until [ "$(ts_state)" = Running ]; do
  bad "Tailscale" "not signed in"
  [ -t 0 ] || die "Sign in to Tailscale and re-run make up."
  info "Signing in opens your browser. New to Tailscale? The same page creates a"
  info "free account (sign in with Google, GitHub, Microsoft or Apple)."
  ask "Sign in to Tailscale now?" || die "Sign in to Tailscale and re-run make up."
  tailscale_login || pause "If the browser did not open, sign in from the Tailscale app, then press enter"
done
tailnet="$("$(tailscale_cli)" status --json 2>/dev/null | sed -n 's/.*"MagicDNSSuffix": *"\([^"]*\)".*/\1/p' | head -1)"
ok "Tailscale" "connected${tailnet:+ · $tailnet}"
info "Put Tailscale on your phone too (App Store / Play Store), same account."
printf '\n'
