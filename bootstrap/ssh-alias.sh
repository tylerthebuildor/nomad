#!/usr/bin/env bash
# The `ssh <box>` / `mosh <box>` shortcut, in YOUR ~/.ssh/config (runs on your
# computer). Without it you type ubuntu@<box>, since the box has no user named
# after you.
#
#   ssh-alias.sh add <box>      offer to add "Host <box> / User ubuntu" (asks
#                               first; leaves an existing entry for <box> alone)
#   ssh-alias.sh remove <box>   remove the entry this script added (make down)
#   ssh-alias.sh connect <box>  print how to connect: "mosh <box>" if the
#                               shortcut works, else "mosh ubuntu@<box>"
#
# Entries it adds are marked "# nomad: added by make up", and only those are
# ever removed. On your phone (Termux), add the same two lines to ~/.ssh/config.
# Written for bash 3.2 (macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"
CONFIG="$HOME/.ssh/config"
MARK="# nomad: added by make up"

# Who `ssh <box>` logs in as, per the same config file this script edits.
user_for() {
  local f="$CONFIG"; [ -f "$f" ] || f=/dev/null
  ssh -G -F "$f" "$1" 2>/dev/null | sed -n 's/^user //p'
}
has_entry() { [ -f "$CONFIG" ] && grep -qiE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?$1([[:space:]]|\$)" "$CONFIG"; }
ok() { printf '  %s✓%s %-18s %s%s%s\n' "$LIVE" "$R" "SSH shortcut" "$DIM" "$1" "$R"; }

add() {
  local box="$1" a
  if [ "$(user_for "$box")" = ubuntu ]; then ok "ssh $box · mosh $box"; return 0; fi
  if has_entry "$box"; then
    printf '  %s!%s %-18s %s~/.ssh/config already has a "Host %s" entry (not ubuntu); left alone%s\n' \
      "$IDLE" "$R" "SSH shortcut" "$IDLE" "$box" "$R"
    return 0
  fi
  [ -t 0 ] || return 0
  printf '\n  %s›%s Add a shortcut so %sssh %s%s and %smosh %s%s work %s(adds 2 lines to ~/.ssh/config)%s? %s[Y/n]%s ' \
    "$ACC" "$R" "$B" "$box" "$R" "$B" "$box" "$R" "$FAINT" "$R" "$FAINT" "$R"
  read -r a </dev/tty || a=n # no answer = no
  case "$a" in [nN]*) printf '  %s–%s %-18s %sskipped · connect with ssh ubuntu@%s%s\n' "$FAINT" "$R" "SSH shortcut" "$FAINT" "$box" "$R"; return 0 ;; esac
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  [ -f "$CONFIG" ] && cp "$CONFIG" "$CONFIG.bak-nomad"
  printf '\n%s\nHost %s\n  User ubuntu\n' "$MARK" "$box" >>"$CONFIG"
  chmod 600 "$CONFIG"
  ok "ssh $box · mosh $box"
}

remove() {
  local box="$1" tmp
  [ -f "$CONFIG" ] && grep -qxF "$MARK" "$CONFIG" || return 0
  tmp="$(mktemp)"
  # Drop exactly what add() wrote for this box: the marker, its Host line and
  # User line, and the blank line before them.
  awk -v mark="$MARK" -v box="$box" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] == mark && lines[i+1] == "Host " box && lines[i+2] == "  User ubuntu") {
          if (n > 0 && out[n] == "") n--
          i += 2; removed = 1; continue
        }
        out[++n] = lines[i]
      }
      for (i = 1; i <= n; i++) print out[i]
      exit removed ? 0 : 1
    }' "$CONFIG" >"$tmp" || { rm -f "$tmp"; return 0; }
  cp "$CONFIG" "$CONFIG.bak-nomad" && cat "$tmp" >"$CONFIG" && rm -f "$tmp"
  printf '  %s✓%s %-18s %sremoved "%s" from ~/.ssh/config%s\n' "$LIVE" "$R" "SSH shortcut" "$DIM" "$box" "$R"
}

connect() {
  if [ "$(user_for "$1")" = ubuntu ]; then echo "mosh $1"; else echo "mosh ubuntu@$1"; fi
}

case "${1:-}" in
  add)     add "${2:?box}" ;;
  remove)  remove "${2:?box}" ;;
  connect) connect "${2:?box}" ;;
  *) echo "usage: ssh-alias.sh add|remove|connect <box>" >&2; exit 2 ;;
esac
