# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# Google Cloud: gcloud CLI + Application Default Credentials, in one sign-in.
SVC_NAME="Google Cloud"
SVC_LASTS="often ~1 day (set by your org's session policy)"
SVC_SIGNED_OUT='Reauthentication required|invalid_grant|Reauthentication failed|problem refreshing your current auth tokens|Could not automatically determine credentials|DefaultCredentialsError|UNAUTHENTICATED'

svc_status() {
  command -v gcloud >/dev/null 2>&1 || { echo "gcloud not installed"; return 2; }
  local who; who="$(gcloud config get-value account 2>/dev/null)"
  if gcloud auth print-access-token >/dev/null 2>&1 \
    && gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "${who:-signed in}"; return 0
  fi
  echo "signed out"; return 1
}

svc_login() {
  local account="${AUTH_GCLOUD_ACCOUNT:-${GAUTH_ACCOUNT:-}}"
  AUTH_WHO="$account"
  # gcloud does not pass the account on to Google, so add login_hint ourselves;
  # it preselects the account and skips Google's account picker. --force: with an
  # account named, gcloud otherwise reuses its stored (maybe expired) credentials.
  auth_paste_flow 'https://accounts\.google\.com/\S+' ${account:+"login_hint=${account//@/%40}"} -- \
    gcloud auth login ${account:+"$account"} --force --update-adc --no-launch-browser
}
