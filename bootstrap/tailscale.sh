#!/usr/bin/env bash
# Joining a new box to your tailnet, used by `make up` (runs on your computer).
#
#   tailscale.sh join <host>
#       Interactive. Gets what the box needs to join, and prints shell
#       `export` lines for make to eval:
#       - default: asks for a Tailscale API access token (opens the admin page
#         with exact steps), then creates a single-use auth key with it. The
#         token is kept only in memory for this `make up`, to finish below.
#       - fallback: press enter at the token prompt to paste an auth key instead.
#       With a token it also checks nothing on the tailnet already holds <host>.
#   tailscale.sh finish <host> <since>
#       With a token: waits for the new box (created after <since>) to join,
#       then turns off its key expiry, so it never drops off the tailnet.
#   tailscale.sh remove <host>
#       After `make down`: offers to remove the box's machine entry from your
#       tailnet (asks for a token; enter skips).
#   tailscale.sh checkmode
#       With a token: if your access rules make Tailscale SSH re-approve you in
#       a browser (~every 12h, "check" mode), offers to switch them to "accept".
#   tailscale.sh lock <host> [--offer]
#       Tailnet lock (`make lock`; `make up` passes --offer): new devices can
#       join only when a signing device approves them. The only signer is this
#       computer (Tailscale needs two keys to turn it on, so <host>'s key is
#       used for that and removed right after). Shows the recovery secrets.
#   tailscale.sh approve <host>
#       While the lock is on: waits for a new <host> to show up locked out, then
#       approves (signs) it from this computer. Adds no keys to the lock.
#
# Written for bash 3.2 (macOS). Uses curl and jq (built into macOS 15+).
set -uo pipefail
export AWS_PAGER="" # never let the AWS CLI open a pager (less) mid-flow

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"

API="https://api.tailscale.com/api/v2"
KEYS_PAGE="https://login.tailscale.com/admin/settings/keys"

say() { printf '%s\n' "$*" >&2; } # the UI goes to stderr; stdout is for make
api() { # method path [json-body]
  curl -fsS -X "$1" "$API$2" -H "Authorization: Bearer $TS_API_TOKEN" \
    ${3:+-H "Content-Type: application/json" --data "$3"}
}
open_url() {
  [ -n "${NOMAD_NO_OPEN:-}" ] && return 0
  if command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1; fi
}
export_line() { printf 'export %s=%q\n' "$1" "$2"; }
line() { # icon color label detail
  say "  ${2}${1}${R} $(printf '%-18s' "$3") ${DIM}${4}${R}"
}

# This computer's tailscale CLI (on macOS it lives inside the app).
ts_cli() {
  if command -v tailscale >/dev/null 2>&1; then echo tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then echo /Applications/Tailscale.app/Contents/MacOS/Tailscale
  fi
}
lock_json() { local ts; ts="$(ts_cli)"; [ -n "$ts" ] && "$ts" lock status --json 2>/dev/null; }
lock_on() { lock_json | grep -q '"Enabled": *true'; }

# While tailnet lock is on, a new box joins locked out until a signer approves
# it. This computer approves it by its node key (`tailscale lock sign nodekey:`),
# which adds nothing to the lock. (Pre-signing the join key instead would add a
# trusted key to the lock for every box, with its private half in the box's AWS
# launch data.)
approve() {
  local host="$1" ts nodekey i
  lock_on || return 0
  ts="$(ts_cli)"
  printf '  %s◦ Waiting for %s to ask to join (tailnet lock)…%s' "$FAINT" "$host" "$R" >&2
  for i in $(seq 1 120); do
    # Locked-out devices are in FilteredPeers, named by DNSName
    # ("nomad.tailXXXX.ts.net."). Anything unexpected reads as "not yet".
    nodekey="$("$ts" lock status --json 2>/dev/null | jq -r --arg h "$host" '
      [(.FilteredPeers // [])[] | select(((.DNSName // .Name // "") | ascii_downcase | split(".")[0]) == ($h | ascii_downcase))]
      | last | .NodeKey // empty' 2>/dev/null)"
    [ -n "$nodekey" ] && break
    sleep 5
  done
  printf '\r\033[K' >&2
  if [ -z "$nodekey" ]; then
    line "!" "$IDLE" "Tailnet lock" "$host did not show up to approve; approve it in the admin console (Machines)"
    return 0
  fi
  if "$ts" lock sign "$nodekey" >/dev/null 2>&1; then
    line "✓" "$LIVE" "Tailnet lock" "$host approved by this computer"
  else
    line "✗" "$BAD" "Tailnet lock" "could not approve $host: is this computer a signer? (tailscale lock status)"
    return 1
  fi
}

# Machines on the tailnet already using <host> (name nomad or nomad-1, ...).
holders() {
  api GET "/tailnet/-/devices" | jq -r --arg h "$1" '
    .devices[] | select(.hostname == $h or (.name | test("^" + $h + "(-[0-9]+)?\\.")))
    | "\(.id)\t\(.name | split(".")[0])\t\(.lastSeen // "now")\t\(.connectedToControl // false)"'
}

paste_key() {
  say ""
  say "  ${DIM}Make a single-use auth key instead:${R} $KEYS_PAGE"
  say "  ${DIM}Generate auth key → not reusable, not ephemeral, expires in 1 day${R}"
  local key
  while true; do
    read -rsp "  Paste the auth key (hidden): " key </dev/tty || key=""; say ""
    case "$key" in
      "") say "  ${BAD}A Tailscale key is needed to create the box.${R}"; exit 1 ;;
      tskey-auth-*) break ;;
      tskey-api-*) say "  ${IDLE}That is an API access token, not an auth key (those start tskey-auth-).${R}"
                   say "  ${DIM}Generate auth key on the same page, or re-run make up and paste the token first.${R}" ;;
      *) say "  ${IDLE}That does not look like an auth key (they start tskey-auth-). Try again.${R}" ;;
    esac
  done
  export_line TF_VAR_tailscale_auth_key "$key"
}

join() {
  local host="$1" token key
  say "  ${ACC}${B}◆ Joining the box to your tailnet${R}"
  say "  ${DIM}Easiest: give make up a Tailscale API access token. It then makes the${R}"
  say "  ${DIM}join key and turns off key expiry on the box for you.${R}"
  say ""
  say "  ${ACC}1${R}  Opening ${NAME}$KEYS_PAGE${R}"
  say "  ${ACC}2${R}  Under ${B}API access tokens${R}, click ${B}Generate access token…${R}"
  say "  ${ACC}3${R}  Description ${B}nomad${R}, expiry ${B}1 day${R} (it is only needed now)"
  say "  ${ACC}4${R}  Generate, copy the token, paste it below"
  say ""
  open_url "$KEYS_PAGE"
  read -rsp "  Paste the token (hidden), or press enter to paste an auth key instead: " token </dev/tty; say ""
  [ -n "$token" ] || { paste_key; return; }
  command -v jq >/dev/null 2>&1 || { say "  ${BAD}jq is needed to use a token (install it), so:${R}"; paste_key; return; }
  export TS_API_TOKEN="$token"

  # Something already holding the name would make the new box "<host>-1", and
  # the next steps (and your phone) expect "<host>".
  local found; found="$(holders "$host" 2>/dev/null)" || {
    say "  ${BAD}That token did not work (check it was copied whole, and is an API access token).${R}"
    paste_key; return
  }
  if [ -n "$found" ]; then
    say ""
    say "  ${IDLE}Your tailnet already has a machine using the name \"$host\":${R}"
    printf '%s\n' "$found" | while IFS=$'\t' read -r _ name seen online; do
      say "    ${NAME}$name${R}  ${DIM}$([ "$online" = true ] && echo "online now" || echo "last seen $seen")${R}"
    done
    say "  ${DIM}If that is an old box that no longer exists, remove it so the new box gets${R}"
    say "  ${DIM}the name. If it is a box you still use, stop and pick another name:${R}"
    say "  ${DIM}  make up PROJECT=othername${R}"
    local a; read -rp "  Remove the machine(s) above from your tailnet? [y/N] " a </dev/tty || a=n
    case "$a" in
      [yY]*) printf '%s\n' "$found" | while IFS=$'\t' read -r id name _ _; do
               api DELETE "/device/$id" >/dev/null && say "  ${LIVE}✓${R} $(printf '%-18s' Tailscale) ${DIM}removed old $name${R}"
             done ;;
      *) say "  ${BAD}Stopped. Nothing was created.${R}"; exit 1 ;;
    esac
  fi

  key="$(api POST "/tailnet/-/keys" \
    '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true}}},"expirySeconds":3600,"description":"nomad first boot"}' |
    jq -r '.key // empty')"
  [ -n "$key" ] || { say "  ${BAD}Could not create an auth key with that token.${R}"; paste_key; return; }
  say "  ${LIVE}✓${R} $(printf '%-18s' 'Join key') ${DIM}single-use, expires in 1 hour${R}"
  export_line TF_VAR_tailscale_auth_key "$key"
  export_line TS_API_TOKEN "$token"
}

finish() {
  local host="$1" since="$2" id="" i
  [ -n "${TS_API_TOKEN:-}" ] || return 0
  printf '  %s◦ Waiting for %s to join your tailnet… (1-3 min)%s' "$FAINT" "$host" "$R" >&2
  for i in $(seq 1 120); do
    id="$(api GET "/tailnet/-/devices" 2>/dev/null | jq -r --arg h "$host" --arg s "$since" '
      [.devices[] | select(.hostname == $h and .created >= $s)] | sort_by(.created) | last | .id // empty')"
    [ -n "$id" ] && break
    sleep 5
  done
  printf '\r\033[K' >&2
  if [ -z "$id" ]; then
    say "  ${IDLE}!${R} $(printf '%-18s' Tailscale) ${IDLE}not joined after 10 min; turn off its key expiry by hand later:${R}"
    say "  ${DIM}https://login.tailscale.com/admin/machines → $host → Disable key expiry${R}"
    return 0
  fi
  if api POST "/device/$id/key" '{"keyExpiryDisabled":true}' >/dev/null; then
    say "  ${LIVE}✓${R} $(printf '%-18s' Tailscale) ${DIM}joined your tailnet · key expiry off${R}"
  else
    say "  ${IDLE}!${R} $(printf '%-18s' Tailscale) ${IDLE}joined, but turning off key expiry failed; do it by hand:${R}"
    say "  ${DIM}https://login.tailscale.com/admin/machines → $host → Disable key expiry${R}"
  fi
}

remove() {
  local host="$1" token found
  [ -t 0 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  say ""
  say "  ${ACC}${B}◆ Remove ${host} from your tailnet too?${R} ${FAINT}(else it stays listed, offline)${R}"
  say "  ${DIM}Paste a Tailscale API access token (Settings → Keys → Generate access token,${R}"
  say "  ${DIM}1 day), or press enter to skip and remove it later in the admin console.${R}"
  open_url "$KEYS_PAGE"
  read -rsp "  Token (hidden): " token </dev/tty; say ""
  [ -n "$token" ] || { say "  ${FAINT}– Skipped. Remove it later: https://login.tailscale.com/admin/machines${R}"; return 0; }
  export TS_API_TOKEN="$token"
  found="$(holders "$host" 2>/dev/null)" || { say "  ${BAD}That token did not work; remove it in the admin console instead.${R}"; return 0; }
  [ -n "$found" ] || { say "  ${LIVE}✓${R} $(printf '%-18s' Tailscale) ${DIM}nothing named $host on your tailnet${R}"; return 0; }
  printf '%s\n' "$found" | while IFS=$'\t' read -r id name _ online; do
    # Tailscale takes a minute or two to notice a destroyed box is gone, so an
    # "online" machine gets up to 2 minutes to drop off before we decide. One
    # that stays online is a live box (maybe another one with this name): kept.
    local i=0
    while [ "$online" = true ] && [ "$i" -lt 24 ]; do
      [ "$i" = 0 ] && printf '  %s◦ Waiting for Tailscale to see %s is gone… (up to 2 min)%s' "$FAINT" "$name" "$R" >&2
      sleep 5; i=$((i + 1))
      online="$(api GET "/device/$id" 2>/dev/null | jq -r '.connectedToControl // false')"
    done
    [ "$i" -gt 0 ] && printf '\r\033[K' >&2
    if [ "$online" = true ]; then
      say "  ${IDLE}!${R} $(printf '%-18s' "$name") ${IDLE}still online after 2 min, so it is a live box: left alone${R}"
    elif api DELETE "/device/$id" >/dev/null; then
      say "  ${LIVE}✓${R} $(printf '%-18s' "$name") ${DIM}removed from your tailnet${R}"
    fi
  done
}

# Tailscale SSH's "check" action makes you re-approve in a browser about every
# 12 hours, which breaks a phone session. "accept" relies on your login (and
# tailnet lock) instead. Edits only the action, after showing it and asking.
checkmode() {
  local acl new etag hdr err
  [ -n "${TS_API_TOKEN:-}" ] || return 0
  hdr="$(mktemp)"
  acl="$(curl -fsS -D "$hdr" "$API/tailnet/-/acl" -H "Authorization: Bearer $TS_API_TOKEN" -H "Accept: application/hujson")" || { rm -f "$hdr"; return 0; }
  etag="$(sed -n 's/^[Ee][Tt]ag: *//p' "$hdr" | tr -d '\r')"; rm -f "$hdr"
  if ! printf '%s' "$acl" | grep -qE '"action"[[:space:]]*:[[:space:]]*"check"'; then
    line "✓" "$LIVE" "SSH check mode" "off · no browser re-approval"
    return 0
  fi
  say ""
  say "  ${ACC}${B}◆ SSH check mode is on${R}"
  say "  ${DIM}Connecting makes you re-approve in a browser about every 12 hours, which${R}"
  say "  ${DIM}interrupts phone sessions. Turning it off changes your access rules' SSH${R}"
  say "  ${DIM}action from \"check\" to \"accept\"; access still needs your Tailscale login.${R}"
  [ -t 0 ] || return 0
  local a; read -rp "  Turn check mode off? [Y/n] " a </dev/tty || a=n
  case "$a" in [nN]*) line "–" "$FAINT" "SSH check mode" "left on"; return 0 ;; esac
  new="$(printf '%s' "$acl" | sed -E 's/("action"[[:space:]]*:[[:space:]]*)"check"/\1"accept"/; /"checkPeriod"/d')"
  err="$(curl -fsS -X POST "$API/tailnet/-/acl/validate" -H "Authorization: Bearer $TS_API_TOKEN" \
    -H "Content-Type: application/hujson" --data-binary "$new" 2>&1)"
  if printf '%s' "$err" | grep -q '"message"'; then
    line "!" "$IDLE" "SSH check mode" "could not change it safely; turn it off in the admin console (Access Controls)"
    return 0
  fi
  if curl -fsS -X POST "$API/tailnet/-/acl" -H "Authorization: Bearer $TS_API_TOKEN" \
       -H "Content-Type: application/hujson" ${etag:+-H "If-Match: $etag"} --data-binary "$new" >/dev/null; then
    line "✓" "$LIVE" "SSH check mode" "off · no browser re-approval"
  else
    line "!" "$IDLE" "SSH check mode" "the change was refused; turn it off in the admin console (Access Controls)"
  fi
}

lock() {
  local host="$1" offer="${2:-}" ts json mine theirs a
  ts="$(ts_cli)"
  [ -n "$ts" ] || { line "!" "$IDLE" "Tailnet lock" "needs Tailscale on this computer"; return 0; }
  json="$(lock_json)"
  if printf '%s' "$json" | grep -q '"Enabled": *true'; then
    line "✓" "$LIVE" "Tailnet lock" "on · new devices need a signer's approval"
    return 0
  fi
  [ -t 0 ] || return 0

  say ""
  say "  ${ACC}${B}◆ Tailnet lock${R} ${FAINT}(recommended)${R}"
  say "  ${DIM}New devices can join your tailnet only when one of your signing devices${R}"
  say "  ${DIM}approves them, so a stolen Tailscale login cannot add one. Your current${R}"
  say "  ${DIM}devices stay as they are.${R}"
  say ""
  say "  ${ACC}·${R} Signer: ${B}this computer${R} only. The box never holds a signing key, so"
  say "    a broken-into box cannot add devices. Add more signers later: tailscale lock add"
  say "  ${ACC}·${R} You get ${B}10 recovery secrets${R}; any one turns the lock off. ${B}Save them${R}"
  say "    ${B}in your password manager${R}. One more goes to Tailscale support as a backstop."
  say "  ${ACC}·${R} Later: a new phone or computer needs one approval command from a signer"
  say "    ${FAINT}(the admin console shows it); tailscale lock add/remove changes signers.${R}"
  say ""
  # No answer (no keyboard, input used up) means no: never turn this on unasked.
  if [ "$offer" = "--offer" ]; then read -rp "  Turn on tailnet lock? [Y/n] " a </dev/tty || a=n
  else read -rp "  Turn it on now? [Y/n] " a </dev/tty || a=n; fi
  case "$a" in [nN]*) line "–" "$FAINT" "Tailnet lock" "off · turn it on anytime: make lock"; return 0 ;; esac

  mine="$(printf '%s' "$json" | sed -n 's/.*"PublicKey": *"\([^"]*\)".*/\1/p')"
  theirs="$(ssh -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -o ConnectTimeout=15 "ubuntu@$host" \
    'tailscale lock status --json' 2>/dev/null | sed -n 's/.*"PublicKey": *"\([^"]*\)".*/\1/p')"
  [ -n "$mine" ] || { line "✗" "$BAD" "Tailnet lock" "could not read this computer's lock key"; return 1; }
  [ -n "$theirs" ] || { line "✗" "$BAD" "Tailnet lock" "could not reach $host to read its lock key; try again: make lock"; return 1; }

  say ""
  say "  ${IDLE}${B}▼ Your recovery secrets: save ALL of them in your password manager now ▼${R}"
  say ""
  "$ts" lock init --gen-disablements 10 --gen-disablement-for-support --confirm "$mine" "$theirs" || {
    line "✗" "$BAD" "Tailnet lock" "could not turn it on (above); nothing changed"; return 1; }
  # Tailscale needs two keys to turn the lock on; the box's was only for that.
  # Removing it leaves this computer as the only signer (the box stays approved:
  # this computer's key signed it).
  "$ts" lock remove "$theirs" >/dev/null 2>&1 ||
    say "  ${IDLE}! Could not remove ${host}'s key; do it yourself: tailscale lock remove $theirs${R}"
  say ""
  say "  ${IDLE}${B}▲ Save the secrets above before you go on ▲${R}"
  until [ "${a:-}" = saved ]; do
    read -rp "  Type saved once they are in your password manager: " a </dev/tty || {
      say "  ${BAD}No keyboard to confirm: the secrets above were NOT cleared from this screen.${R}"; return 1; }
  done
  printf '\033[2J\033[3J\033[H' >&2 # clear the screen and scrollback, so the secrets do not linger
  if lock_on; then line "✓" "$LIVE" "Tailnet lock" "on · signer: this computer"
  else line "!" "$IDLE" "Tailnet lock" "not showing as on yet; check: tailscale lock status"; fi
}

case "${1:-}" in
  join)      join "${2:?host}" ;;
  finish)    finish "${2:?host}" "${3:?since}" ;;
  remove)    remove "${2:?host}" ;;
  checkmode) checkmode ;;
  lock)      lock "${2:?host}" "${3:-}" ;;
  approve)   approve "${2:?host}" ;;
  *) echo "usage: tailscale.sh join <host> | finish <host> <since> | remove <host> | checkmode | lock <host> [--offer] | approve <host>" >&2; exit 2 ;;
esac
