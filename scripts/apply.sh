#!/usr/bin/env bash
# The Terraform half of `make up` (runs on your computer): plan, show what will
# happen in a line or two, confirm, apply. Usage: apply.sh <project> <region>
#
#   nothing to change     one line, no prompt
#   creating / changing   a short summary, then [Y/n]
#   destroying/replacing  the FULL plan, a warning, and you type the box's name
#                         (a replaced box loses its disk)
#
# A new box first needs to join your tailnet (scripts/tailscale.sh), and
# afterwards gets its key expiry turned off. Terraform's own output goes to a
# log, shown if something fails. Written for bash 3.2 (macOS).
set -uo pipefail
export AWS_PAGER=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"
PROJECT="${1:?project}" REGION="${2:?region}"
TF="terraform -chdir=$ROOT/terraform"
LOG="$(mktemp -t nomad-terraform.XXXXXX)" PLAN="$ROOT/terraform/.nomad.tfplan"
trap 'rm -f "$PLAN"' EXIT

ok()   { printf '  %s✓%s %-18s %s%s%s\n' "$LIVE" "$R" "$1" "$DIM" "${2:-}" "$R"; }
fail() { printf '  %s✗ %s%s\n' "$BAD" "$1" "$R"; grep -v '^\s*$' "$LOG" | tail -15 | sed "s/^/      ${FAINT}/; s/\$/${R}/"
         printf '    %sFull Terraform output: %s%s\n\n' "$DIM" "$LOG" "$R"; exit 1; }
box_id() { $TF state list 2>/dev/null | grep -qx aws_instance.nomad && $TF output -raw instance_id 2>/dev/null; }

printf '\n  %s%s◆ The box%s %s(%s · %s)%s\n\n' "$ACC" "$B" "$R" "$FAINT" "$PROJECT" "$REGION" "$R"

before="$(box_id)"
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -z "$before" ] && [ -z "${TF_VAR_tailscale_auth_key:-}" ]; then
  join="$(bash "$ROOT/scripts/tailscale.sh" join "$PROJECT")" || exit 1
  eval "$join"
fi
if [ -z "$before" ] && [ -z "${TF_VAR_tailscale_auth_key:-}" ]; then
  printf '  %s✗ Stopped: a new box needs a Tailscale key, or it can never join your tailnet.%s\n\n' "$BAD" "$R"
  exit 1
fi

# --- plan -------------------------------------------------------------------------
printf '  %s◦ Planning…%s' "$FAINT" "$R"
$TF plan -input=false -no-color -detailed-exitcode -out="$PLAN" >"$LOG" 2>&1; rc=$?
printf '\r\033[K'
[ "$rc" = 1 ] && fail "Terraform could not plan"

summary="$(grep -E '^Plan: ' "$LOG" | tail -1)"
adds="$(echo "$summary" | sed -n 's/.* \([0-9]*\) to add.*/\1/p')"
destroys="$(echo "$summary" | sed -n 's/.* \([0-9]*\) to destroy.*/\1/p')"

if [ "$rc" = 0 ] || [ -z "$summary" ]; then
  # Nothing to change on AWS (at most Terraform's saved outputs, e.g. a new public
  # IP after a restart, which apply just records).
  [ "$rc" = 2 ] && { $TF apply -input=false -no-color "$PLAN" >>"$LOG" 2>&1 || fail "Terraform could not save its outputs"; }
  ok "Box" "up to date · $before"
else
  if [ "${destroys:-0}" -gt 0 ]; then
    # Anything destroyed or replaced: show everything and make it deliberate.
    $TF show -no-color "$PLAN"
    printf '\n  %s%s⚠  This DESTROYS %s resource(s).%s\n' "$BAD" "$B" "$destroys" "$R"
    if grep -q 'aws_instance.nomad.*\(destroyed\|replaced\)' "$LOG"; then
      printf '  %sIt replaces the box itself: everything on its disk is lost.%s\n' "$BAD" "$R"
    fi
    [ -t 0 ] || { printf '  %sStopped (needs a person to confirm).%s\n\n' "$BAD" "$R"; exit 1; }
    printf '\n  %s›%s To go ahead, type the box name (%s): ' "$ACC" "$R" "$PROJECT"; read -r answer || answer=""
    [ "$answer" = "$PROJECT" ] || { printf '  %sStopped. Nothing changed.%s\n\n' "$DIM" "$R"; exit 1; }
  else
    if [ -z "$before" ]; then
      type="$(sed -n 's/.*+ instance_type *= *"\(.*\)"/\1/p' "$LOG" | head -1)"
      disk="$(sed -n 's/.*+ volume_size *= *\([0-9]*\).*/\1/p' "$LOG" | head -1)"
      printf '  %s+%s Create %s%s%s: %s · %s GB encrypted disk · %s %s(%s resources)%s\n' \
        "$LIVE" "$R" "$B" "$PROJECT" "$R" "${type:-?}" "${disk:-?}" "$REGION" "$FAINT" "$adds" "$R"
      question="Create it?"
    else
      grep -E '^  # .* (will be|must be)' "$LOG" | sed "s/^  # /    ${DIM}/; s/\$/${R}/"
      question="Apply these changes?"
    fi
    if [ -t 0 ]; then
      printf '\n  %s›%s %s %s[Y/n]%s ' "$ACC" "$R" "$question" "$FAINT" "$R"; read -r a || a=n # no answer = no
      case "$a" in [nN]*) printf '  %sStopped. Nothing changed.%s\n\n' "$DIM" "$R"; exit 1 ;; esac
    elif [ -z "${NOMAD_YES:-}" ]; then
      printf '  %sStopped (no terminal to confirm; set NOMAD_YES=1 to approve).%s\n\n' "$BAD" "$R"; exit 1
    fi
  fi

  # --- apply ------------------------------------------------------------------------
  t0=$(date +%s)
  printf '  %s◦ Building… (about a minute)%s' "$FAINT" "$R"
  $TF apply -input=false -no-color "$PLAN" >>"$LOG" 2>&1; rc=$?
  printf '\r\033[K'
  [ "$rc" = 0 ] || fail "Terraform could not apply"
  after="$(box_id)"
  if [ -z "$before" ]; then ok "Box" "created · $after $FAINT($(( $(date +%s) - t0 ))s)"
  else ok "Box" "updated · $after"; fi
fi
after="$(box_id)"

# A new or replaced box has new SSH host keys: forget the old ones for its name.
[ "$before" != "$after" ] && ssh-keygen -R "$PROJECT" >/dev/null 2>&1
# With an API token: wait for it to join, turn off its key expiry, and offer to
# turn off SSH check mode. A new box also gets the tailnet lock offer at the end
# of make up (the marker file tells make it is new).
if [ "$before" != "$after" ]; then
  touch "$ROOT/terraform/.nomad-new-box"
  # Under tailnet lock the new box joins locked out; approve it from here.
  bash "$ROOT/scripts/tailscale.sh" approve "$PROJECT" || exit 1
  if [ -n "${TS_API_TOKEN:-}" ]; then
    bash "$ROOT/scripts/tailscale.sh" finish "$PROJECT" "$since"
    bash "$ROOT/scripts/tailscale.sh" checkmode
  fi
fi
rm -f "$LOG"
exit 0
