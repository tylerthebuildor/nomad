#!/usr/bin/env bash
# Wait until the box is reachable over the tailnet (it joins on first boot,
# usually 1-3 minutes after Terraform creates it), so `make up` can go straight
# on to `make bootstrap`. Usage: wait-for-box.sh <hostname> [minutes]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"

HOST="${1:-nomad}"
LIMIT=$(( ${2:-10} * 60 ))

# Tailscale SSH answers on port 22 of the tailnet address, before any sign-in.
reachable() {
  if [ "$(uname -s)" = Darwin ]; then nc -z -G 3 "$HOST" 22 >/dev/null 2>&1
  else nc -z -w 3 "$HOST" 22 >/dev/null 2>&1; fi
}

tailscale_cli() {
  if command -v tailscale >/dev/null 2>&1; then echo tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then echo /Applications/Tailscale.app/Contents/MacOS/Tailscale
  fi
}

start=$(date +%s); warned=0
until reachable; do
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -ge "$LIMIT" ]; then
    printf '\n  %s✗ %s did not show up after %s minutes.%s\n' "$BAD" "$HOST" "$(( LIMIT / 60 ))" "$R"
    printf '    %sCheck the Tailscale admin console (Machines). When it is there, run: make bootstrap%s\n' "$DIM" "$R"
    exit 1
  fi
  # A box from before still holding the name makes the new one "nomad-1".
  if [ "$warned" = 0 ] && [ "$elapsed" -ge 150 ]; then
    ts="$(tailscale_cli)"
    if [ -n "$ts" ] && "$ts" status 2>/dev/null | awk '{print $2}' | grep -q "^$HOST-[0-9]"; then
      printf '\n    %sA machine named %s-1 (or similar) is on your tailnet: probably this new box,%s\n' "$IDLE" "$HOST" "$R"
      printf '    %sbecause an old "%s" still holds the name. Remove the old one in the Tailscale%s\n' "$IDLE" "$HOST" "$R"
      printf '    %sadmin console (Machines), then rename the new one to "%s".%s\n' "$IDLE" "$HOST" "$R"
    fi
    warned=1
  fi
  printf '\r\033[K  %s◦ Waiting for %s on your tailnet… %dm%02ds (first boot takes 1-3 min)%s' \
    "$FAINT" "$HOST" $(( elapsed / 60 )) $(( elapsed % 60 )) "$R"
  sleep 5
done
printf '\r\033[K  %s✓%s %-18s %sreachable over your tailnet%s\n' "$LIVE" "$R" "SSH" "$DIM" "$R"
