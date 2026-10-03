# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# Claude Code. A CLAUDE_CODE_OAUTH_TOKEN variable (from `claude setup-token`,
# lasts about a year) overrides a sign-in; auth reports that instead.
SVC_NAME="Claude Code"
SVC_LASTS="setup-token: ~1 year · sign-in: long-lived"
SVC_SIGNED_OUT='Invalid API key|Please run /login|OAuth token has expired|authentication_error|Not logged in'

svc_status() {
  command -v claude >/dev/null 2>&1 || { echo "claude not installed"; return 2; }
  local json who
  json="$(claude auth status 2>/dev/null)" || true
  if [ "$(jq -r '.loggedIn // false' <<<"$json" 2>/dev/null)" = true ]; then
    who="$(jq -r '.email // .account.email // empty' <<<"$json" 2>/dev/null)"
    [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && who="${who:+$who · }token"
    echo "${who:-signed in}"; return 0
  fi
  echo "signed out"; return 1
}

svc_login() {
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    printf '\n  %s◆ Claude Code%s uses the CLAUDE_CODE_OAUTH_TOKEN variable (set in\n' "$ACC$B" "$R"
    printf '  %syour shell config), which overrides a sign-in. It lasts about a year;\n' "$DIM"
    printf '  renew it with: claude setup-token%s\n' "$R"
    return 0
  fi
  AUTH_WHO="${AUTH_CLAUDE_EMAIL:-}"
  auth_paste_flow 'https://claude\.(com|ai)/\S*oauth\S*' -- \
    claude auth login ${AUTH_CLAUDE_EMAIL:+--email "$AUTH_CLAUDE_EMAIL"}
}
