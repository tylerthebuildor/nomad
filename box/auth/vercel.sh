# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# Vercel CLI. Sign-in is long-lived.
SVC_NAME="Vercel"
SVC_LASTS="long-lived"
SVC_SIGNED_OUT='vercel login|not logged in|The specified token is not valid|No existing credentials found|invalid token'

svc_status() {
  command -v vercel >/dev/null 2>&1 || { echo "vercel not installed"; return 2; }
  local who
  if who="$(vercel whoami 2>/dev/null | tail -1)" && [ -n "$who" ]; then
    [ -n "${AUTH_VERCEL_USER:-}" ] && [ "$who" != "$AUTH_VERCEL_USER" ] && who+=" (expected $AUTH_VERCEL_USER)"
    echo "$who"; return 0
  fi
  echo "signed out"; return 1
}

svc_login() {
  AUTH_WHO="${AUTH_VERCEL_USER:-}"
  auth_device_flow 'https://vercel\.com/oauth/device\S*' 'user_code=([A-Z0-9-]+)' -- vercel login
}
