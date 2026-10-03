#!/usr/bin/env bash
# The checks every pull request must pass. GitHub runs each one as its own job
# (.github/workflows/checks.yml); `make check` runs them all locally.
#
#   check.sh secrets     gitleaks over the whole git history
#   check.sh shell       shellcheck on every shell script
#   check.sh terraform   terraform fmt + validate
#   check.sh workflows   actionlint on .github/workflows
#   check.sh [all]       all of the above
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
. lib/ui.sh

# Tracked shell scripts: *.sh, plus anything with a sh/bash shebang (box/bin/, the
# cloud-init template).
shell_files() {
  git ls-files | while IFS= read -r f; do
    case "$f" in
      *.sh) echo "$f" ;;
      *) [ -f "$f" ] && head -1 "$f" | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)' && echo "$f" ;;
    esac
  done
}

need() { command -v "$1" >/dev/null 2>&1 || { printf '  %s✗%s %-12s %s%s is not installed%s\n' "$BAD" "$R" "$2" "$DIM" "$1" "$R"; return 1; }; }

check() { # name, then the command
  local name="$1" out; shift
  if out="$("$@" 2>&1)"; then
    printf '  %s✓%s %s\n' "$LIVE" "$R" "$name"
  else
    printf '  %s✗ %s%s\n' "$BAD" "$name" "$R"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  fi
}

secrets() {
  need gitleaks secrets || return 1
  check secrets gitleaks git . --redact --no-banner
}

shell() {
  need shellcheck shell || return 1
  # shellcheck disable=SC2046 # one argument per file is the point
  check "shell ($(shell_files | wc -l | tr -d ' ') scripts)" shellcheck -S warning $(shell_files)
}

terraform_() {
  need terraform terraform || return 1
  check "terraform fmt" terraform -chdir=terraform fmt -check -recursive || return 1
  # validate needs providers; a fresh checkout (CI) gets them without a backend.
  [ -d terraform/.terraform ] || terraform -chdir=terraform init -backend=false -input=false >/dev/null || return 1
  check "terraform validate" terraform -chdir=terraform validate -no-color
}

workflows() {
  need actionlint workflows || return 1
  check workflows actionlint
}

case "${1:-all}" in
  secrets) secrets ;;
  shell) shell ;;
  terraform) terraform_ ;;
  workflows) workflows ;;
  all)
    rc=0
    secrets || rc=1; shell || rc=1; terraform_ || rc=1; workflows || rc=1
    exit "$rc" ;;
  *) echo "usage: check.sh [secrets|shell|terraform|workflows|all]" >&2; exit 2 ;;
esac
