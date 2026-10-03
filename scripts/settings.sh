#!/usr/bin/env bash
# Your personal settings for the box, asked once and saved (runs on YOUR
# computer, from `make up` and `make settings`):
#   config/git.env   git name + email, set on the box so commits are yours
#   config/auth.env  accounts `auth` uses on the box (see box/auth/README.md)
# Both are gitignored; the .example files next to them document every setting.
#
# Defaults come from this computer (git config, gcloud, gh, vercel, claude, aws),
# so usually you just press enter.
#
#   settings.sh            ask only for files that do not exist yet (make up)
#   settings.sh --edit     review and change everything (make settings)
# Written for bash 3.2 (macOS).
set -uo pipefail
export AWS_PAGER=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/ui.sh"
CFG="$ROOT/config"
GIT_ENV="$CFG/git.env" AUTH_ENV="$CFG/auth.env"

edit=0; [ "${1:-}" = "--edit" ] && edit=1
have() { command -v "$1" >/dev/null 2>&1; }
val() { [ -f "$1" ] && sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" | tail -1; }

# Nothing to ask: say what is set, in one line, and move on.
if [ "$edit" = 0 ] && [ -f "$GIT_ENV" ] && [ -f "$AUTH_ENV" ]; then
  printf '  %s✓%s %-18s %sgit as %s · change: make settings%s\n' "$LIVE" "$R" "Your settings" "$DIM" \
    "$(val "$GIT_ENV" GIT_USER_EMAIL || true)" "$R"
  exit 0
fi
if [ ! -t 0 ]; then
  printf '  %s–%s %-18s %snot set (run make settings in a terminal)%s\n' "$FAINT" "$R" "Your settings" "$DIM" "$R"
  exit 0
fi

# --- defaults: what is saved, else what this computer already knows ----------
detect() { # key -> value from this computer (never waits on a prompt)
  case "$1" in
    GIT_USER_NAME)     git config --global user.name 2>/dev/null ;;
    GIT_USER_EMAIL)    git config --global user.email 2>/dev/null ;;
    AUTH_GCLOUD_ACCOUNT) have gcloud && gcloud config get-value account 2>/dev/null ;;
    AUTH_GH_USER)      have gh && gh api user --jq .login 2>/dev/null ;;
    AUTH_VERCEL_USER)  have vercel && vercel whoami 2>/dev/null | tail -1 ;;
    AUTH_CLAUDE_EMAIL) have claude && claude auth status 2>/dev/null | sed -n 's/.*"email": *"\([^"]*\)".*/\1/p' | head -1 ;;
    AUTH_AWS_MODE)     if aws configure get aws_access_key_id >/dev/null 2>&1; then echo keys; else echo login; fi ;;
  esac
}

# key | label | file | hint
FIELDS='GIT_USER_NAME|Git name|git|your name on commits
GIT_USER_EMAIL|Git email|git|the email on your GitHub/Vercel account
AUTH_GCLOUD_ACCOUNT|Google account|auth|preselected when signing in to gcloud
AUTH_GH_USER|GitHub user|auth|auth warns if signed in as someone else
AUTH_VERCEL_USER|Vercel user|auth|auth warns if signed in as someone else
AUTH_CLAUDE_EMAIL|Claude email|auth|prefilled when signing in to Claude Code
AUTH_AWS_MODE|AWS sign-in|auth|keys, login (console/root) or sso'

printf '\n  %s%s◆ Your settings%s %s(asked once · saved in config/, not committed)%s\n\n' "$ACC" "$B" "$R" "$FAINT" "$R"
printf '  %sFound on this computer:%s\n\n' "$DIM" "$R"

values=""
while IFS='|' read -r key label file hint; do
  f="$GIT_ENV"; [ "$file" = auth ] && f="$AUTH_ENV"
  # Only fields whose file is missing get asked, unless editing everything.
  [ "$edit" = 0 ] && [ -f "$f" ] && continue
  v="$(val "$f" "$key")"; [ -n "$v" ] || v="$(detect "$key" </dev/null)"
  values="$values$key=$v
"
  printf '    %s%-15s%s %s%s%s\n' "$DIM" "$label" "$R" "$NAME" "${v:-–}" "$R"
done <<EOF
$FIELDS
EOF

get() { printf '%s' "$values" | sed -n "s/^$1=//p" | head -1; }
set_value() { # key value
  values="$(printf '%s' "$values" | grep -v "^$1=")
$1=$2
"
}

printf '\n  %s›%s Use these? %s[Y/n]%s ' "$ACC" "$R" "$FAINT" "$R"; read -r a || a=n # no answer = no
case "$a" in
  [nN]*)
    printf '\n  %sEnter keeps the value shown, - clears it.%s\n' "$DIM" "$R"
    while IFS='|' read -r key label file hint; do
      printf '%s' "$values" | grep -q "^$key=" || continue
      cur="$(get "$key")"
      printf '    %s%-15s%s %s(%s)%s [%s]: ' "$NAME" "$label" "$R" "$FAINT" "$hint" "$R" "${cur:-–}"
      read -r new
      case "$new" in "") ;; -) set_value "$key" "" ;; *) set_value "$key" "$new" ;; esac
    done <<EOF
$FIELDS
EOF
    ;;
esac

# --- save: start from the documented example, fill in the values -------------
write() { # file example prefix
  local out="$1" tmp key v
  [ -f "$out" ] || cp "$2" "$out"
  tmp="$(mktemp)"; cp "$out" "$tmp"
  printf '%s' "$values" | grep "^$3" | while IFS='=' read -r key v; do
    v="${v//\"/}" # keep the file a plain KEY="value" list
    if grep -q "^$key=" "$tmp"; then
      awk -v k="$key" -v v="$v" 'index($0, k "=") == 1 { print k "=\"" v "\""; next } { print }' "$tmp" >"$tmp.new" && mv "$tmp.new" "$tmp"
    else
      printf '%s="%s"\n' "$key" "$v" >>"$tmp"
    fi
  done
  mv "$tmp" "$out"; chmod 600 "$out"
}
printf '%s' "$values" | grep -q '^GIT_' && write "$GIT_ENV" "$CFG/git.env.example" GIT_
printf '%s' "$values" | grep -q '^AUTH_' && write "$AUTH_ENV" "$CFG/auth.env.example" AUTH_

printf '\n  %s✓%s Saved %s(config/, not committed · change anytime: make settings)%s\n\n' "$LIVE" "$R" "$DIM" "$R"
