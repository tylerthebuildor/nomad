# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# AWS CLI. AUTH_AWS_MODE picks how you sign in:
#   keys   long-lived access keys (aws configure); nothing to sign in to
#   login  console sign-in, root or IAM user (aws login --remote); up to 12h
#   sso    IAM Identity Center (aws sso login); usually 8-12h
SVC_NAME="AWS"
SVC_LASTS="keys: until rotated · login/sso: ~8-12h"
SVC_SIGNED_OUT='ExpiredToken|Token has expired|session has expired|Error loading SSO Token|Unable to locate credentials|InvalidClientTokenId|login session|aws login'

_aws() { aws --profile "${AUTH_AWS_PROFILE:-default}" ${AUTH_AWS_REGION:+--region "$AUTH_AWS_REGION"} "$@"; }

svc_status() {
  command -v aws >/dev/null 2>&1 || { echo "aws not installed"; return 2; }
  local arn
  if arn="$(_aws sts get-caller-identity --query Arn --output text 2>/dev/null)"; then
    # arn:aws:iam::123:user/name -> user/name, arn:aws:iam::123:root -> root
    echo "${arn##*:} · ${AUTH_AWS_MODE:-keys}"; return 0
  fi
  echo "signed out"; return 1
}

svc_login() {
  AUTH_WHO="profile ${AUTH_AWS_PROFILE:-default}"
  case "${AUTH_AWS_MODE:-keys}" in
    login)
      auth_paste_flow 'https://\S*signin\.aws\.amazon\.com/\S+' -- \
        aws login --remote --profile "${AUTH_AWS_PROFILE:-default}" --region "${AUTH_AWS_REGION:-us-east-1}" ;;
    sso)
      auth_device_flow 'https://\S+/device\S*' '([A-Z0-9]{4}-[A-Z0-9]{4})' -- \
        aws sso login --use-device-code --no-browser --profile "${AUTH_AWS_PROFILE:-default}" ;;
    *)
      printf '\n  %s◆ AWS%s\n    %sprofile %s · access keys%s\n\n' "$ACC$B" "$R" "$DIM" "${AUTH_AWS_PROFILE:-default}" "$R"
      printf '  Access keys never expire, so there is\n  nothing to sign in to.\n\n'
      printf '  %sNew keys:%s aws configure\n' "$DIM" "$R"
      printf '  %sConsole or root sign-in:%s set\n  AUTH_AWS_MODE=login in the auth config\n' "$DIM" "$R"
      return 0 ;;
  esac
}
