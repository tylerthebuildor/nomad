#!/usr/bin/env bash
# Nomad phone setup: Termux on Android, ready to reach your box.
#
# In Termux, paste (box name optional, default nomad):
#
#   curl -fsSL https://raw.githubusercontent.com/tylerthebuildor/nomad/main/phone/setup.sh | bash -s nomad
#
# Before this: install the Tailscale app (Play Store) and sign in with the same
# account as your computer, and install Termux from F-Droid (f-droid.org; the
# Play Store's Termux is an old build).
#
# What it does, step by step (read it, run it, or do it by hand):
#   1. Installs ssh and mosh in Termux (mosh keeps your session through wifi /
#      cellular switches and echoes typing instantly).
#   2. Adds a shortcut to ~/.ssh/config so `mosh nomad` logs in as `ubuntu`, and
#      trusts the box's key on first connect (the box is only reachable over
#      your own tailnet).
#   3. Termux settings, unless you already set them yourself: an extra-keys row
#      (Esc, Ctrl, Tab, arrows, / - |) above the keyboard, and tap-to-open for
#      links (so the sign-in links `auth` shows open in your browser).
#   4. Checks it can reach the box.
#   5. If you say yes: every new Termux tab opens your box (ctrl-c or exit for a
#      plain Termux shell).
#
# Everything it adds is marked "# nomad", so re-running only updates its own
# lines, and `bash setup.sh nomad --remove` takes them back out.
#
# Not on Termux (e.g. an iPhone)? It prints the three settings to enter in your
# terminal app instead (Blink Shell and Termius both do mosh).
set -uo pipefail

BOX="${1:-nomad}"
case "$BOX" in --remove) BOX=nomad; set -- nomad --remove ;; esac
MODE="${2:-}"
MARK="# nomad: added by phone/setup.sh"
LOG="$HOME/.cache/nomad-phone.log"

# The same look as the rest of Nomad (lib/ui.sh), inline so this stays one file.
e=$'\e'
R="${e}[0m" B="${e}[1m" DIM="${e}[38;5;244m" FAINT="${e}[38;5;240m" ACC="${e}[38;5;208m"
LIVE="${e}[38;5;114m" IDLE="${e}[38;5;179m" BAD="${e}[38;5;203m"
ok()   { printf '  %s✓%s %-14s %s%s%s\n' "$LIVE" "$R" "$1" "$DIM" "${2:-}" "$R"; }
warn() { printf '  %s!%s %-14s %s%s%s\n' "$IDLE" "$R" "$1" "$IDLE" "${2:-}" "$R"; }
skip() { printf '  %s–%s %-14s %s%s%s\n' "$FAINT" "$R" "$1" "$FAINT" "${2:-}" "$R"; }
fail() { printf '  %s✗ %s%s %s\n' "$BAD" "$1" "$R" "${2:-}"; }
# The script itself arrives on stdin (curl | bash), so questions read the keyboard.
# No answer means no.
ask() { local a; printf '\n  %s›%s %s %s[Y/n]%s ' "$ACC" "$R" "$1" "$FAINT" "$R"; read -r a </dev/tty || return 1
        case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac; }

# Remove this script's marked block (the marker line through the next blank line).
# A file left empty (one this script created) is removed.
drop_block() { # file
  [ -f "$1" ] || return 0
  awk -v m="$MARK" '$0 == m { skip = 1; next } skip && /^$/ { skip = 0; next } !skip' "$1" >"$1.nomad-tmp" &&
    mv "$1.nomad-tmp" "$1"
  [ -s "$1" ] || rm -f "$1"
}

printf '\n  %s%s◆ Nomad on this phone%s %s(box: %s)%s\n\n' "$ACC" "$B" "$R" "$FAINT" "$BOX" "$R"

# --- Not Termux: say what to set in your own app ----------------------------------
if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d /data/data/com.termux ]; then
  printf '  This is not Termux, so set these in your terminal app (Blink Shell or\n'
  printf '  Termius on iPhone, for example):\n\n'
  printf '    %sHost%s      %s\n' "$DIM" "$R" "$BOX"
  printf '    %sUser%s      ubuntu\n' "$DIM" "$R"
  printf '    %sConnect%s   with mosh (or ssh)\n\n' "$DIM" "$R"
  printf '  %sWith the Tailscale app on and signed in to the same account.%s\n\n' "$FAINT" "$R"
  exit 0
fi

# --- --remove: take out everything this script added ---------------------------------
if [ "$MODE" = "--remove" ]; then
  for f in "$HOME/.ssh/config" "$HOME/.termux/termux.properties" "$HOME/.bashrc" \
           "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    drop_block "$f"
  done
  rm -f "$LOG"; rmdir "$(dirname "$LOG")" 2>/dev/null
  command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings
  ok "Removed" "Nomad's lines from ssh config, extra keys and shell startup"
  printf '\n'; exit 0
fi

mkdir -p "$(dirname "$LOG")"; : >"$LOG"

# --- 1. ssh + mosh ------------------------------------------------------------------------
if command -v ssh >/dev/null 2>&1 && command -v mosh >/dev/null 2>&1; then
  ok "ssh + mosh" "already installed"
else
  printf '  %s◦ Installing ssh and mosh (a minute or two)…%s' "$FAINT" "$R"
  # Keep existing config files on upgrade instead of stopping to ask.
  if { pkg update -y && apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade &&
       pkg install -y openssh mosh; } >>"$LOG" 2>&1 </dev/null; then
    printf '\r\033[K'; ok "ssh + mosh" "installed"
  else
    printf '\r\033[K'; fail "Could not install ssh and mosh." "Last lines of $LOG:"
    tail -6 "$LOG" | sed "s/^/      ${FAINT}/; s/\$/${R}/"; exit 1
  fi
fi

# --- 2. The shortcut: "mosh nomad" logs in as ubuntu ---------------------------------------
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
drop_block "$HOME/.ssh/config" # replace this script's entry, never yours
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if grep -qiE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?$BOX([[:space:]]|\$)" "$HOME/.ssh/config"; then
  warn "Shortcut" "you already have a \"Host $BOX\" entry; left as is"
else
  printf '%s\nHost %s\n  User ubuntu\n  StrictHostKeyChecking accept-new\n\n' "$MARK" "$BOX" >>"$HOME/.ssh/config"
  ok "Shortcut" "mosh $BOX · ssh $BOX"
fi

# --- 3. Termux settings: extra keys, tap links to open ------------------------------------
props="$HOME/.termux/termux.properties"
mkdir -p "$HOME/.termux"; drop_block "$props"; touch "$props"
lines="" added=""
if ! grep -q '^[[:space:]]*extra-keys' "$props"; then
  lines+="extra-keys = [['ESC','/','-','|','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]"$'\n'
  added+="extra keys"
fi
if ! grep -q '^[[:space:]]*terminal-onclick-url-open' "$props"; then
  lines+="terminal-onclick-url-open = true"$'\n'
  added+="${added:+ · }tap links to open"
fi
if [ -n "$lines" ]; then
  printf '%s\n%s\n' "$MARK" "$lines" >>"$props"
  command -v termux-reload-settings >/dev/null 2>&1 && termux-reload-settings
  ok "Termux" "$added"
else
  skip "Termux" "your own extra keys and link settings; left as is"
fi

# --- 4. Can we reach the box? ------------------------------------------------------------------
if ssh -o BatchMode=yes -o ConnectTimeout=10 "$BOX" true >>"$LOG" 2>&1 </dev/null; then
  ok "Reach $BOX" "connected over your tailnet"
else
  warn "Reach $BOX" "not yet: is the Tailscale app on, same account as your computer?"
fi

# --- 5. Open Termux = open your box --------------------------------------------------------------
drop_block "$HOME/.bashrc"
if ask "Open your box every time you open Termux? (ctrl-c or exit for a Termux shell)"; then
  printf '%s\nif [ -z "${NOMAD_CONNECTING:-}" ] && [ -t 0 ]; then\n  export NOMAD_CONNECTING=1\n  mosh %s || echo "Could not reach %s. Is Tailscale on? Retry: mosh %s"\nfi\n\n' \
    "$MARK" "$BOX" "$BOX" "$BOX" >>"$HOME/.bashrc"
  # If Termux starts bash as a login shell, bash reads the first of
  # ~/.bash_profile, ~/.bash_login, ~/.profile instead of ~/.bashrc; have that
  # one load ~/.bashrc too (NOMAD_CONNECTING stops a double connect).
  login="$HOME/.bash_profile"
  for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do [ -f "$f" ] && { login="$f"; break; }; done
  drop_block "$login"
  grep -q '\.bashrc' "$login" 2>/dev/null || printf '%s\n[ -f ~/.bashrc ] && . ~/.bashrc\n\n' "$MARK" >>"$login"
  ok "Auto-connect" "new Termux tabs open $BOX"
else
  skip "Auto-connect" "off · connect with: mosh $BOX"
fi

printf '\n  📱 %sReady.%s Open a new Termux tab %s(swipe from the left edge → New session)%s\n' "$B" "$R" "$FAINT" "$R"
printf '     or type: %smosh %s%s\n\n' "$B" "$BOX" "$R"
