---
name: auth
description: Sign the user back in to a CLI on this headless box when a command fails because they are signed out or a session expired, for gcloud / Google Cloud client libraries, AWS CLI, GitHub CLI (gh), Vercel CLI, or Claude Code. Typical errors include "Reauthentication required", "invalid_grant", "DefaultCredentialsError", "ExpiredToken", "Token has expired", "Unable to locate credentials", "Bad credentials", "HTTP 401", "not logged in", "vercel login", or UNAUTHENTICATED. Also use before a task that needs one of these CLIs, and whenever the user asks to log in or sign in to one of them. The box has an `auth` command for this; never run the CLIs' own login commands (gcloud auth login, aws login, aws sso login, gh auth login, vercel login, claude auth login) yourself.
---

# auth: signing in on the box

The box has no browser, and the user is usually on their phone. The `auth`
command (in `~/.local/bin`) signs in to each CLI with a small card showing a short
link (`http://nomad:8085`, tailnet only) that the user opens on their phone. Some
services then need a code pasted back, others finish by themselves. Signing in
needs the human, so never try to complete it yourself, and never run a CLI's own
login command: `auth` wraps them in a phone-friendly flow.

## 1. Which service, and is it really signed out?

`auth --list` shows every service, how long its sign-ins last, and a regex of the
error text that means "signed out". Match the failure against it. Then confirm:

```sh
auth <service> --check   # exit 0 signed in, 1 signed out; prints who
```

If it is signed in, the failure is something else (wrong account or project,
missing permission, API not enabled): look there instead. `auth --status` shows
all services at once.

## 2. Open the sign-in on the user's screen

If you are inside tmux (`$TMUX` is set), open it as a full-screen popup over the
user's session. It blocks until they finish, so use a long timeout (e.g. 600000
ms) and first tell them in one line that a sign-in is coming:

```sh
tmux display-popup -E -B -w 100% -h 100% "auth <service>"
```

Use exactly those flags: `-B` (no border) and full size keep it readable on a
phone. Tell the user to open the short link shown on the card in their phone's
browser and sign in; for gcloud, AWS (login mode) and Claude Code they then paste
the code into the popup. It shows the result and closes. Re-run the check from
step 1, then carry on with the original task.

If `$TMUX` is not set or the popup fails, ask the user to run `auth <service>`
themselves (inside tmux, **ctrl-b then A** opens the board), and wait for them.

## 3. If it still fails

- `auth <service> -f` forces a fresh sign-in even when it looks signed in.
- The status shows "(expected ...)": they are signed in as a different account
  than the one in `~/.config/nomad/auth.env`. Say so; do not loop on sign-in.
- AWS in `keys` mode, or gh / Claude Code using a token variable, have nothing to
  sign in to: the card says so. Report it; the fix is new keys or a new token.
- Persistent 403s after a good sign-in are permissions, not sign-in: report which
  account and what permission, do not loop.
