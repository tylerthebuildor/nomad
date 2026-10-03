#!/usr/bin/env bash
# Nomad box bootstrap: dev environment + CLIs for a headless Ubuntu (ARM64) box,
# using each tool's official install method (nvm + corepack, rustup, deno, the
# gh / gcloud apt repos, the aws v2 zip, ...). `make up` runs it automatically;
# `make bootstrap` re-runs it.
#
# Idempotent: each tool is installed only if missing, so re-runs skip what is
# there (they do not upgrade). The nomad pieces (helper scripts, auth services,
# settings, skills, tmux config) are re-copied every run.
#
# Output: one line per step (✓ done, "new" if just installed, – skipped,
# ! needs attention, ✗ failed). Everything the installers print goes to
# ~/.cache/nomad/setup.log; a failed step shows its last lines right there.
#
# Sign-ins are not handled here: run `auth` on the box afterwards. Run as the
# regular user (e.g. `ubuntu`), not root.
set -o pipefail

NOMAD_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
HOST="${NOMAD_HOSTNAME:-nomad}"
if [ -f "$NOMAD_REPO/lib/ui.sh" ]; then . "$NOMAD_REPO/lib/ui.sh"
else R="" B="" DIM="" FAINT="" ACC="" LIVE="" IDLE="" BAD=""; fi

LOG="$HOME/.cache/nomad/setup.log"
mkdir -p "$(dirname "$LOG")"; : >"$LOG"
FAILED="" START=$(date +%s)

# step <label> <check> <fn>
#   check: a command that succeeds if the thing is already there (for "new")
#   fn:    does the work, output to the log; sets NOTE (shown after the label).
#          Returns 0 done, 3 skipped, 4 done but needs attention, else failed.
step() {
  local label="$1" check="$2" fn="$3" had=1 rc from tag=""
  NOTE=""
  [ -n "$check" ] && { eval "$check" >/dev/null 2>&1 || had=0; }
  printf '  %s◦ %s…%s' "$FAINT" "$label" "$R"
  printf '\n=== %s ===\n' "$label" >>"$LOG"
  from=$(wc -l <"$LOG")
  "$fn" >>"$LOG" 2>&1; rc=$?
  printf '\r\033[K'
  [ "$had" = 0 ] && [ "$rc" = 0 ] && tag="  ${LIVE}new${R}"
  case "$rc" in
    0) printf '  %s✓%s %-18s %s%s%s%s\n' "$LIVE" "$R" "$label" "$DIM" "$NOTE" "$R" "$tag" ;;
    3) printf '  %s–%s %-18s %s%s%s\n' "$FAINT" "$R" "$label" "$FAINT" "$NOTE" "$R" ;;
    4) printf '  %s!%s %-18s %s%s%s\n' "$IDLE" "$R" "$label" "$IDLE" "$NOTE" "$R" ;;
    *) printf '  %s✗ %-18s%s %sfailed (exit %s)%s\n' "$BAD" "$label" "$R" "$BAD" "$rc" "$R"
       tail -n +"$((from + 1))" "$LOG" | grep -v '^\s*$' | tail -12 | sed "s/^/      ${FAINT}/; s/\$/${R}/"
       FAILED="${FAILED:+$FAILED, }$label" ;;
  esac
}

# apt, quietly. sudo would drop DEBIAN_FRONTEND (the "debconf: unable to
# initialize frontend" noise), so pass it through; NEEDRESTART_SUSPEND skips the
# service-restart report.
apt_get() { sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get -qq -o=Dpkg::Use-Pty=0 "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Every tool's install location, up front, so the "already installed?" checks
# find tools from earlier runs (a non-interactive SSH shell does not read
# ~/.bashrc). Without this, re-runs reinstalled Rust, Bun, Deno and Claude Code.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.deno/bin:/usr/local/go/bin:$HOME/go/bin:$HOME/.local/share/solana/install/active_release/bin:$HOME/.avm/bin:$PATH"
export NVM_DIR="$HOME/.nvm"

# --- the steps ------------------------------------------------------------------

system_packages() {
  apt_get update && apt_get install -y build-essential curl unzip gpg git jq ripgrep fzf tmux pkg-config libssl-dev || return
  NOTE="build tools, git, tmux, fzf, ripgrep, jq"
}

set_hostname() { # so the prompt reads ubuntu@<name>, across reboots
  sudo hostnamectl set-hostname "$HOST" || return
  echo 'preserve_hostname: true' | sudo tee /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg >/dev/null
  NOTE="$HOST"
}

node_js() { # Node via nvm, pnpm + yarn via corepack
  [ -s "$NVM_DIR/nvm.sh" ] || curl -fsS -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash || return
  . "$NVM_DIR/nvm.sh"
  # The current LTS on the first run only. Re-runs keep the existing Node: a new
  # Node version would not have the global npm tools (vercel, LSPs) installed.
  if nvm which default >/dev/null 2>&1; then nvm use default >/dev/null
  else nvm install --lts --latest-npm && nvm alias default 'lts/*' || return; fi
  corepack enable && corepack prepare pnpm@latest --activate && corepack prepare yarn@stable --activate || return
  NOTE="$(node -v | sed 's/^v//') · pnpm · yarn"
}

bun_js() {
  have bun || curl -fsSL https://bun.sh/install | bash || return
  NOTE="$(bun --version)"
}

deno_js() {
  have deno || curl -fsSL https://deno.land/install.sh | sh || return
  NOTE="$(deno --version | head -1 | awk '{print $2}')"
}

rust() {
  have rustc || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y -q || return
  . "$HOME/.cargo/env" 2>/dev/null
  rustup component add rust-analyzer 2>/dev/null
  NOTE="$(rustc --version | awk '{print $2}')"
}

golang() {
  if ! have go; then
    local v arch
    v="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)" || return
    arch="$(dpkg --print-architecture)" # arm64 / amd64
    curl -fsSL "https://go.dev/dl/${v}.linux-${arch}.tar.gz" -o /tmp/go.tgz &&
      sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz || return
  fi
  NOTE="$(go version | awk '{print $3}' | sed 's/^go//')"
}

github_cli() { # official apt repo
  if ! have gh; then
    sudo mkdir -p /etc/apt/keyrings &&
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null &&
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg &&
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null &&
      apt_get update && apt_get install -y gh || return
  fi
  NOTE="$(gh --version | head -1 | awk '{print $3}')"
}

aws_cli() { # v2, arch-aware
  if ! have aws; then
    local a=x86_64; case "$(uname -m)" in aarch64|arm64) a=aarch64 ;; esac
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${a}.zip" -o /tmp/awscliv2.zip &&
      unzip -qo /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install --update && rm -rf /tmp/aws /tmp/awscliv2.zip || return
  fi
  NOTE="$(aws --version 2>&1 | cut -d' ' -f1 | cut -d/ -f2)"
}

gcloud_cli() { # official apt repo
  if ! have gcloud; then
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg &&
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null &&
      apt_get update && apt_get install -y google-cloud-cli || return
  fi
  NOTE="$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')"
}

vercel_cli() {
  have vercel || npm install -g vercel || return
  NOTE="$(vercel --version 2>/dev/null | tail -1)"
}

solana() {
  # Anza's installer has no prebuilt ARM Linux build (it 404s on Graviton), and
  # Anchor needs the Solana CLI, so both are skipped there.
  if [ "$(uname -s)-$(uname -m)" = Linux-aarch64 ]; then
    NOTE="skipped · no ARM Linux build"; return 3
  fi
  have solana || sh -c "$(curl -fsSL https://release.anza.xyz/stable/install)" || return
  have avm || cargo install --git https://github.com/coral-xyz/anchor avm --force || return
  if ! have anchor; then
    avm install latest </dev/null
    yes | avm use latest # it asks y/n; never let it wait on a prompt
  fi
  NOTE="$(solana --version | awk '{print $2}') · anchor"
}

language_servers() { # help Claude Code: definitions, diagnostics, completions
  have typescript-language-server || npm install -g typescript typescript-language-server || return
  have pyright || npm install -g pyright || return
  have gopls || go install golang.org/x/tools/gopls@latest || return
  NOTE="TypeScript, Python, Go"
}

claude_code() {
  have claude || curl -fsSL https://claude.ai/install.sh | bash || return
  NOTE="$(claude --version 2>/dev/null | awk '{print $1}')"
}

nomad_tools() { # bin/ -> ~/.local/bin, lib/ + auth/ -> ~/.local/share/nomad, skills/ -> ~/.claude/skills
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/nomad" "$HOME/.claude/skills"
  install -m 755 "$NOMAD_REPO/bin"/* "$HOME/.local/bin/" || return
  local d
  for d in lib auth; do
    rm -rf "$HOME/.local/share/nomad/$d" && cp -R "$NOMAD_REPO/$d" "$HOME/.local/share/nomad/$d" || return
  done
  rm -rf "$HOME/.claude/skills/gauth" # replaced by the auth skill
  cp -R "$NOMAD_REPO/skills"/. "$HOME/.claude/skills/" || return
  NOTE="t, auth, note · Claude skills"
}

your_settings() { # config/ (asked once by make up) -> ~/.config/nomad
  mkdir -p "$HOME/.config/nomad"
  # Your config/auth.env (gitignored) wins; otherwise start from the example once.
  if [ -f "$NOMAD_REPO/config/auth.env" ]; then
    install -m 600 "$NOMAD_REPO/config/auth.env" "$HOME/.config/nomad/auth.env"
  elif [ ! -f "$HOME/.config/nomad/auth.env" ] && [ -f "$NOMAD_REPO/config/auth.env.example" ]; then
    install -m 600 "$NOMAD_REPO/config/auth.env.example" "$HOME/.config/nomad/auth.env"
  fi
  # Git identity, so commits are yours, not ubuntu@<host> (which GitHub will not
  # attribute and Vercel's GitHub integration rejects).
  if [ -f "$NOMAD_REPO/config/git.env" ]; then
    install -m 600 "$NOMAD_REPO/config/git.env" "$HOME/.config/nomad/git.env"
    ( . "$HOME/.config/nomad/git.env"
      [ -n "${GIT_USER_NAME:-}" ] && git config --global user.name "$GIT_USER_NAME"
      [ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "$GIT_USER_EMAIL"
      true )
  fi
  if [ -z "$(git config --global user.email)" ]; then
    NOTE="no git identity: commits would be ubuntu@$HOST (make settings, then make bootstrap)"
    return 4
  fi
  NOTE="git as $(git config --global user.name) <$(git config --global user.email)>"
}

shell_and_tmux() {
  local rc="$HOME/.bashrc"
  add_line() { grep -qF "$1" "$rc" 2>/dev/null || echo "$1" >>"$rc"; }
  add_line 'export PATH="$HOME/.local/bin:$PATH"'
  add_line 'export NVM_DIR="$HOME/.nvm"'
  add_line '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
  add_line '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
  add_line 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"'
  add_line 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"'
  add_line 'export PATH="$HOME/.avm/bin:$PATH"'
  add_line 'export PATH="$HOME/.bun/bin:$PATH"'
  add_line 'export DENO_INSTALL="$HOME/.deno"'
  add_line '[ -d "$DENO_INSTALL/bin" ] && export PATH="$DENO_INSTALL/bin:$PATH"'
  add_line "alias claw='claude --permission-mode bypassPermissions --'"

  # tmux, tuned for a phone (Termux + mosh).
  cat >"$HOME/.tmux.conf" <<'TMUXCONF'
# Nomad tmux config, tuned for phone (Termux + mosh) use.
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -sg escape-time 0
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
set -g status-style 'bg=colour236 fg=colour252'
set -g status-left '#[bold] #S '
set -g status-left-length 30
set -g status-right ' %H:%M '
bind r source-file ~/.tmux.conf \; display "tmux.conf reloaded"
# prefix + S: session picker (bin/t) in a popup, to switch sessions
bind S display-popup -E -B -w 100% -h 100% "$HOME/.local/bin/t"
# prefix + G: Google Cloud sign-in (auth gcloud) in a popup
bind G display-popup -E -B -w 100% -h 100% "$HOME/.local/bin/auth gcloud"
# prefix + A: sign-in board for every service (bin/auth)
bind A display-popup -E -B -w 100% -h 100% "$HOME/.local/bin/auth"
TMUXCONF

  # Session menu on login. Older boxes auto-attached every login to one shared
  # "main" session; drop that.
  perl -0pi -e 's/\n# Nomad: auto-attach tmux.*?\nfi\n//s' "$rc" 2>/dev/null
  if ! grep -q 'Nomad: session picker' "$rc" 2>/dev/null; then
    cat >>"$rc" <<'ATTACH'

# Nomad: session picker on interactive login (phone-friendly). Each tab picks a
# running tmux session or starts a new one via bin/t; esc gives a plain shell.
if command -v t >/dev/null 2>&1 && [ -z "$TMUX" ] && [ -n "$PS1" ]; then
  t
fi
ATTACH
  fi
  NOTE="claw alias · session menu on login · tmux for phones"
}

# --- run ------------------------------------------------------------------------

printf '\n  %s%s◆ Setting up %s%s\n\n' "$ACC" "$B" "$HOST" "$R"
step "System packages"  ""                                   system_packages
step "Hostname"         ""                                   set_hostname
step "Node"             '[ -d "$NVM_DIR/versions/node" ]'    node_js
step "Bun"              'have bun'                           bun_js
step "Deno"             'have deno'                          deno_js
step "Rust"             'have rustc'                         rust
step "Go"               'have go'                            golang
step "GitHub CLI"       'have gh'                            github_cli
step "AWS CLI"          'have aws'                           aws_cli
step "Google Cloud CLI" 'have gcloud'                        gcloud_cli
step "Vercel CLI"       'have vercel'                        vercel_cli
step "Solana + Anchor"  'have solana'                        solana
step "Language servers" 'have typescript-language-server'    language_servers
step "Claude Code"      'have claude'                        claude_code
step "Nomad tools"      ""                                   nomad_tools
step "Your settings"    ""                                   your_settings
step "Shell + tmux"     ""                                   shell_and_tmux

took=$(( $(date +%s) - START ))
if [ -n "$FAILED" ]; then
  printf '\n  %s✗ Not quite: %s failed.%s\n' "$BAD" "$FAILED" "$R"
  printf '    %sFull log on the box: ~/.cache/nomad/setup.log · fix, then: make bootstrap%s\n\n' "$DIM" "$R"
  exit 1
fi
printf '\n  🏜️  %s%s%s is ready %s(%dm %02ds)%s\n' "$B" "$HOST" "$R" "$FAINT" $((took / 60)) $((took % 60)) "$R"
printf '     %sConnect:%s %s %s(or make ssh)%s\n' "$DIM" "$R" "${NOMAD_CONNECT:-mosh ubuntu@$HOST}" "$FAINT" "$R"
printf '     %sThen sign in to your CLIs:%s auth\n\n' "$DIM" "$R"
