# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# GitHub CLI (gh). Sign-in does not expire. A GH_TOKEN environment variable
# overrides it; auth reports that instead of signing in over the top of it.
SVC_NAME="GitHub"
SVC_LASTS="doesn't expire"
SVC_SIGNED_OUT='gh auth login|not logged into any GitHub hosts|Bad credentials|HTTP 401|authentication required'

svc_status() {
  command -v gh >/dev/null 2>&1 || { echo "gh not installed"; return 2; }
  local who
  if who="$(gh api user --jq .login 2>/dev/null)" && [ -n "$who" ]; then
    [ -n "${GH_TOKEN:-}" ] && who+=" · GH_TOKEN"
    [ -n "${AUTH_GH_USER:-}" ] && [ "${who%% *}" != "$AUTH_GH_USER" ] && who+=" (expected $AUTH_GH_USER)"
    echo "$who"; return 0
  fi
  echo "signed out"; return 1
}

svc_login() {
  if [ -n "${GH_TOKEN:-}" ]; then
    printf '\n  %s◆ GitHub%s uses the GH_TOKEN variable (set in your shell config),\n' "$ACC$B" "$R"
    printf '  %swhich overrides a sign-in. Remove it to sign in with auth instead.%s\n' "$DIM" "$R"
    return 0
  fi
  AUTH_WHO="${AUTH_GH_USER:-}"
  # gh waits for Enter before "opening a browser"; feed it one, and point
  # BROWSER at `true` so it does not complain that there is no browser.
  auth_device_flow 'https://github\.com/login/device' 'one-time code: (\S+)' -- \
    sh -c 'printf "\n" | BROWSER=true gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web'
}
