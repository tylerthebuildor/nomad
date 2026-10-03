#!/usr/bin/env bash
# `make down` (runs on your computer): destroy the box and everything Terraform
# made for it, then offer to remove it from your tailnet. You confirm by typing
# the box's name, since its disk is lost. Usage: destroy.sh <project> <region>
# Written for bash 3.2 (macOS).
set -uo pipefail
export AWS_PAGER=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"
PROJECT="${1:?project}" REGION="${2:?region}"
TF="terraform -chdir=$ROOT/terraform"
LOG="$(mktemp -t nomad-terraform.XXXXXX)" PLAN="$ROOT/terraform/.nomad-destroy.tfplan"
trap 'rm -f "$PLAN"' EXIT

ok()   { printf '  %s✓%s %-18s %s%s%s\n' "$LIVE" "$R" "$1" "$DIM" "${2:-}" "$R"; }
fail() { printf '  %s✗ %s%s\n' "$BAD" "$1" "$R"; grep -v '^\s*$' "$LOG" | tail -15 | sed "s/^/      ${FAINT}/; s/\$/${R}/"
         printf '    %sFull Terraform output: %s%s\n\n' "$DIM" "$LOG" "$R"; exit 1; }
box_id() { $TF state list 2>/dev/null | grep -qx aws_instance.nomad && $TF output -raw instance_id 2>/dev/null; }

printf '\n  %s%s◆ Tearing down%s %s(%s · %s)%s\n\n' "$ACC" "$B" "$R" "$FAINT" "$PROJECT" "$REGION" "$R"

id="$(box_id)"
count="$($TF state list 2>/dev/null | grep -v '^data\.' | grep -c .)"
if [ "${count:-0}" = 0 ]; then
  ok "Nothing to destroy" "no box or network for $PROJECT in $REGION"
else
  printf '  %s◦ Planning…%s' "$FAINT" "$R"
  $TF plan -destroy -input=false -no-color -out="$PLAN" >"$LOG" 2>&1 || { printf '\r\033[K'; fail "Terraform could not plan the teardown"; }
  printf '\r\033[K'
  printf '  %s-%s Destroy %s%s%s: %s %s(%s resources: box, disk, network)%s\n' \
    "$BAD" "$R" "$B" "$PROJECT" "$R" "${id:-no box}" "$FAINT" "$count" "$R"
  [ -n "$id" ] && printf '  %sEverything on its disk is lost.%s\n' "$BAD" "$R"
  [ -t 0 ] || { printf '  %sStopped (needs a person to confirm).%s\n\n' "$BAD" "$R"; exit 1; }
  printf '\n  %s›%s To go ahead, type the box name (%s): ' "$ACC" "$R" "$PROJECT"; read -r answer || answer=""
  [ "$answer" = "$PROJECT" ] || { printf '  %sStopped. Nothing changed.%s\n\n' "$DIM" "$R"; exit 1; }

  t0=$(date +%s)
  printf '  %s◦ Destroying… (about a minute)%s' "$FAINT" "$R"
  $TF apply -input=false -no-color "$PLAN" >>"$LOG" 2>&1; rc=$?
  printf '\r\033[K'
  [ "$rc" = 0 ] || fail "Terraform could not destroy everything"
  ok "Box" "destroyed · $count resources $FAINT($(( $(date +%s) - t0 ))s)"
fi

ssh-keygen -R "$PROJECT" >/dev/null 2>&1
bash "$ROOT/bootstrap/ssh-alias.sh" remove "$PROJECT"
bash "$ROOT/bootstrap/tailscale.sh" remove "$PROJECT"
printf '\n  %sKept: the Terraform state bucket (tiny, and make up reuses it).%s\n\n' "$FAINT" "$R"
rm -f "$LOG"
