# 🔑 auth services

Each file here teaches `auth` (box/bin/auth) how to sign in to one CLI from a phone.
`auth`, its status board, and Claude's `auth` skill discover them automatically,
so adding a service is adding one file. Files starting with `_` are shared code.

## The contract

A service is a bash file, `auth/<name>.sh`, that sets three variables and
defines two functions:

```bash
SVC_NAME="Example"                 # shown on the card and the board
SVC_LASTS="~1 day"                 # how long a sign-in lasts, for humans
SVC_SIGNED_OUT='token expired|401' # regex of error text meaning "signed out";
                                   # Claude matches failures against it

svc_status() {  # print who you are signed in as (one short line), then:
  # return 0 signed in · 1 signed out · 2 not set up (e.g. CLI missing)
}

svc_login() {   # sign in, using one of the shared flows below
}
```

`svc_login` sets `AUTH_WHO` (shown under the title, usually the account from
config) and calls one of the two flows in `_flows.sh`. Every CLI's headless
sign-in is one of these shapes:

| Flow | The CLI... | Examples |
|---|---|---|
| `auth_paste_flow <url-regex> [hint] -- cmd...` | prints a long link, then waits for a code pasted back | gcloud, `aws login`, claude |
| `auth_device_flow <url-regex> <code-regex> -- cmd...` | prints a link and a short code, then finishes by itself once you approve | gh, vercel, `aws sso login` |

Both hide the CLI's output and show a phone-sized card, with a short link
(`http://nomad:8085`, tailnet only, only while signing in) that redirects to the
CLI's link. If the CLI fails, its last lines are shown. `hint` is a query
parameter appended to the link (gcloud uses `login_hint=...` to preselect the
account).

## Settings

Per-person values (accounts, modes) go in `config/auth.env` (gitignored; see
`config/auth.env.example`), installed to `~/.config/nomad/auth.env`. Name them
`AUTH_<SERVICE>_<THING>` and add them, with a comment, to the example file.

## Adding one

1. Run the CLI's headless sign-in once and note what it prints: the link, and a
   code or a "paste the code" prompt. That tells you which flow it is.
2. Copy the closest existing service, adjust the regexes and command.
3. `auth <name>` to try it, `auth` to see it on the board. `make bootstrap`
   installs it on the box.
