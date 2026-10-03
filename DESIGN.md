# Nomad

A personal cloud development box. The whole point: do everything I do on my
laptop, from my phone, anywhere in the world, without carrying a computer.

Codename **Nomad** because it describes the user, not the tech. A digital nomad's
workstation that lives in AWS and is driven from a phone.

Status: **in daily use.** `make up` goes from a fresh clone to a ready box (a
t4g.large in its own zero-inbound VPC, encrypted disk, Terraform state in S3),
joins your tailnet, and installs the dev environment. See the README for how to
use it; this document is the original design and reasoning.

---

## Goal

Take my current laptop development setup (which is mostly prompting Claude Code
against my real credentials and environment) and move it to an always-on AWS box
that I reach from my Android phone, and also from my laptop when I want it.

The productivity unlock is not the box, it is being free of the laptop: work from
the phone in the in-between moments, anywhere, no physical machine to carry, open,
and tether.

## Non-goals

- Not a product or a service. It is a personal tool I use to build my other
  projects. (It may later be open-sourced as a "here is how I do it" repo, but
  never maintained as a service.)
- Not Kubernetes, not containers. It is a single computer, so it is a VM.
- Not enterprise credential hygiene. See the security model: the goal is
  laptop-parity, not stricter-than-my-laptop.

---

## Principles

Ranked, so they break ties when we build:

1. **Phone experience first.** I (and any future user) must genuinely *want* to
   work from the phone because it feels amazing, not merely tolerate it. Any
   choice that trades away mobile UX needs a very good reason.
2. **Secure.** Laptop-parity creds plus a hardened perimeter. Non-negotiable,
   but we avoid paying for it in UX wherever we can.
3. **Simple and easy to reason about.** Few moving parts, for both setup and for
   understanding the security. Easy for me now, easy for a future open-source
   user to stand up and trust.

The whole thing should stay pitchable in one breath: a locked-down EC2 instance,
Tailscale as the only way in, and a terminal on your phone. That is all you need
to be a nomad. (See PITCH.md.)

---

## Security model

Guiding principle: **clone my MacBook's trust model onto the box, then make the
perimeter as good or better than my laptop's.** I have already accepted that the
agent has full access to my machine and that some credentials sit in plaintext
dotfiles. The job is not to invent a stricter posture for the cloud, it is to
match the laptop and harden the one axis where a cloud box is genuinely worse.

Reasonable threat bar: not defending against nation-states. Acceptable if there
is no way to exploit it without millions of dollars or thousands of hours.

### Box-level (AWS infrastructure)

- Use a plain **EC2 instance**, which is a hardware-isolated VM on the Nitro
  hypervisor, single-tenant on its own kernel and memory. This is not a container
  sharing a kernel with other tenants, so "container-to-container exfil" does not
  apply. Cross-tenant VM escape is the multi-million-dollar exploit class we are
  fine ruling out.
- The only third-party code on the instance is whatever the agent installs
  (npm packages, etc.), which is identical to the laptop today.

### Laptop vs cloud box, axis by axis

- **Always-on and reachable**: the one real downgrade vs a laptop that sleeps and
  goes off-network. This is the entire security problem, and the Tailscale
  perimeter neutralizes it. Close this and the rest is gravy.
- **Disk at rest**: laptop has FileVault, cloud equivalent is EBS encryption
  (a toggle, on by default). Optional flex: customer-managed KMS key so not even
  AWS staff can read the volume.
- **Physical theft**: laptop can be grabbed, the box cannot. Point for the cloud.
- **Outbound exposure**: identical to the laptop (it reaches npm, crates, git,
  the Anthropic API).

Net: the box can be equal or better than the MacBook on every axis except
"always reachable," which is exactly what the perimeter over-engineers.

### Perimeter (the network door)

- **Zero public inbound.** Security group denies all inbound from the internet,
  port 22 included. Nothing to scan or brute-force.
- **Outbound stays open.** "Shut off from the internet" means inbound-locked, not
  air-gapped. The box must reach out to install packages and call Claude.
- **Tailscale (WireGuard) is the single path in.** Both phone and laptop are
  peers on the tailnet. The instance connects outbound to Tailscale, so it needs
  no open inbound ports, same zero-exposure property as it would have with SSM.
- **Tailnet lock is the load-bearing control** against rogue devices: adding any
  new device requires a cryptographic signature from an already-trusted device, so
  even a fully phished Tailscale account cannot enroll a machine that reaches the
  box.
- **Passkey on the IdP login (Google), kept.** It is NOT a per-connection factor
  and NOT a second SSH key, so it is not the redundant "two creds on one phone"
  layer (we already dropped the separate SSH key for Tailscale SSH). It is account
  MFA: set once, re-auth is rare (long session expiry), so daily friction is ~zero
  and no convenience is actually traded. Its real jobs are securing the account
  and enabling recovery, for example revoking a lost/stolen phone by logging in
  from another device. Keep it on a YubiKey or the laptop too, not solely the
  phone, so a lost phone does not also lose the recovery path.
- No SSM Session Manager as a standing second path. One door only. Emergency
  recovery, if the tailnet ever fully breaks, is the AWS console (temporarily
  enabling access for that one event, then turning it back off).

### Access path

- **Tailscale SSH**, not hardware-backed key files. Tailscale brokers SSH auth
  using verified identity, so there is no enclave key to provision and the setup
  is identical on Android and iOS. This also strengthens portability.
- **mosh** over the tailnet for the link: UDP-based, survives wifi-to-cellular
  roaming and dropped signal, and echoes keystrokes locally so typing feels
  instant on a laggy mobile connection.
- **tmux** for a persistent server-side session you reattach to every time.
- **Plain `ssh` (still over Tailscale SSH) stays available for port forwarding.**
  mosh cannot forward ports, so the rare one-time CLI login needing a localhost
  browser callback uses an `ssh -L` session instead. No separate SSH key needed.
- **Client is disposable by design.** The box only speaks SSH/mosh/tmux and does
  not care what connects. The "swappable plugin" is the terminal app itself:
  **Termux** on Android now (ships with mosh and tmux), **Blink** on iOS later.
  Switching phones is "install the other app, re-add the device to the tailnet."
  Nothing to build, portability is free.

### Credentials

- Laptop-parity handling. Same secrets, same plaintext-where-the-laptop-is
  plaintext, just in a different location. No per-credential scoping crusade.
- **Nothing personal goes through Terraform or the repo.** Terraform does not
  need my package-manager / GitHub / SSH / cargo creds, and the repo never
  contains them: not encrypted, not gitignored, just absent. No SOPS.
- **Credentials are seeded manually**, one-time and ad hoc, over the tailnet
  after the box is up. They change rarely and unpredictably (a new cred on local
  I want on the box, or one created on the box I want locally), and laptop and
  box may intentionally hold *different* keys (for example separate GitHub SSH
  keys both authorized on my profile). Doing it by hand for a while is the point:
  it reveals whether any sync tooling is even worth building later.
- The one provisioning secret is an **ephemeral, single-use Tailscale auth key**
  passed to cloud-init at `make up` time (via a gitignored tfvar or env var, not
  committed) so the box can join the tailnet on first boot. It is burned after.
- The agent threat (prompt injection exfiltrating creds) is real but is the same
  risk already accepted on the laptop. Knowingly accepted for a personal tool.

### Local dev servers

Free win over the mesh: a dev server on the box at port N is reachable from the
phone and laptop at `nomad:N` (Tailscale MagicDNS gives the box a stable
hostname), completely private, never exposed to the public internet.

### Push notifications (deferred to a later build)

Principle: **send a doorbell, not a letter.** Payloads are content-free ("Claude
needs you", "build finished"), never the actual output. Open the terminal over
the tailnet to see the real content, so the relay never carries secrets and its
subscription security matters much less.

When we add it: a hosted relay is fine given doorbell-only payloads. **Pushover**
(one-time ~$5, private, trivial API, near-zero management) or **ntfy.sh** (free,
unguessable topic plus optional auth). Wired to Claude Code's notification hook.

---

## Architecture summary

- **Compute**: EC2, ARM (AWS Graviton), 24/7. **Start small and cheap** while
  on-ramping to this way of working: **t4g.large** (2 vCPU / 8 GB burstable,
  ~$49/mo) or **t4g.medium** (4 GB, ~$24/mo) for even leaner. Burstable runs on
  CPU credits, ideal for light prompting; sustained heavy compiles can throttle,
  which is the cue to scale. **Scale up to m7g.xlarge / m7g.2xlarge (or m8g)**
  later in a ~1 minute stop/start once builds warrant it. ARM throughout matches
  laptop and phone, no toolchain tax for Rust / Solana / Anchor / Node.
- **Storage**: gp3 EBS, **start ~100 GB**, encrypted. Grows live with no
  downtime, so size up only when needed.
- **Scaling**: instance type change is a ~1 minute stop/start with EBS data
  preserved; volume grow is fully live. Stay within the ARM family when resizing.
- **Network in**: Tailscale only, zero public inbound, tailnet lock, passkey IdP.
- **Access**: Tailscale SSH + mosh + tmux, from Termux (Android) today.
- **Network out**: open, for package installs and the Anthropic API.

Rough cost at 24/7: starter ~$57/mo (t4g.large + 100 GB gp3), or ~$32/mo with a
t4g.medium. Scaled up later, ~$120/mo (m7g.xlarge) to ~$235/mo (m7g.2xlarge) plus
storage; a 1-year Compute Savings Plan trims ~30 to 40% off compute once it is
permanently always-on. Plan: start on t4g, scale when builds drag.

---

## Dev environment (bootstrap)

The box reproduces my current dev setup, which closely tracks my **VibeStack**
(`vibestack/` and vibestack.md), specifically its optional developer-environment
setup. The cloud-init bootstrap installs the tools; logging into them is manual
(see below), matching the credentials decision. Finalize the exact list by reading
VibeStack when we build (my local has drifted from it a bit).

To install (mirror VibeStack developer-environment):

- Languages/runtimes: Rust, Go, Node/TypeScript, plus the Solana/Anchor toolchain.
- CLIs I use heavily: Vercel CLI, AWS CLI, GitHub CLI, plus git/tmux/etc.
- Shell + dotfiles, tmux config, mosh.

### CLI authentication (headless logins)

The real hurdle is logging into CLIs on a headless box with no browser. It is a
solved problem: the browser auth always happens on the **phone**, never on the
box, so the box needs no GUI. Two patterns cover nearly everything:

- **Device-code flow**: the CLI prints a URL + short code, you open the URL on the
  phone, approve, and the CLI polls until done.
- **Token / key paste**: generate a token in the web dashboard on the phone and
  paste it into the CLI or an env var.

Per tool:

- **GitHub CLI**: `gh auth login` device flow. Headless, clean.
- **AWS CLI**: static access keys via `aws configure` (pure paste) or
  `aws configure sso` device flow.
- **Vercel CLI**: a `VERCEL_TOKEN` from the dashboard is cleanest; the email login
  also works since the click happens on the phone.
- **npm / cargo**: paste automation/API tokens into `.npmrc` / cargo credentials.
- **Solana/Anchor**: keypair files, copied over or generated on the box.

Escape hatch for any stubborn CLI that only does a localhost browser callback: run
it inside a **plain `ssh -L` port-forward** session (over Tailscale SSH, no extra
key) and open the forwarded `localhost:PORT` URL on the phone. mosh cannot forward
ports, so use `ssh` for that one-time step.

These are one-time logins done over the tailnet at setup, then persisted, so they
are not daily friction and not part of the bootstrap script (manual, per the
credentials decision).

---

## Reproducibility / infrastructure as code

Goal: the box, the Tailscale setup, all config, as simple reproducible code, with
**GitHub as the single source of truth** (private repo to start). One command to
stand it all up. If the box is ever compromised or I just want a fresh one, tear
down and recreate easily. Also a record for future-me and for friends who ask.
Eventually an open-source "clone my setup" repo: `git clone && make up` with your
own AWS and Tailscale account.

Two layers, one repo:

1. **Provisioning (Terraform)**: VPC/subnet, security group (no public inbound),
   EC2 (Graviton), EBS, and no instance role for now (the box carries zero AWS
   credentials, best blast radius). Declarative, destroy-and-recreate, widely
   understood, good for open-sourcing. Terraform **state in an S3 backend** so any
   machine or a GitHub Action can manage it, not just the laptop.
2. **Configuration (cloud-init bootstrap)**: a first-boot script that installs
   Tailscale, Claude Code, languages, tmux/mosh, shell, dotfiles. Simpler and
   more readable than Ansible for a single box, and it doubles as documentation
   of exactly what is installed. Graduate to Ansible only if it gets hairy; Nix is
   the ultimate-reproducibility option if ever wanted.

Secrets: **none in the repo.** Terraform and the bootstrap do not need my
personal credentials, so they are never committed (not even SOPS-encrypted). The
only provisioning secret is an ephemeral single-use Tailscale auth key, supplied
at apply time via a gitignored tfvar or env var so the box can join the tailnet.
All personal credentials (npm, GitHub, SSH, cargo, etc.) are seeded by hand over
the tailnet after the box is up, kept manual on purpose until a real need for
sync tooling emerges.

Payoff: a `Makefile` with `make up` / `make down` / `make ssh`, one command from
zero to a running Nomad box. Future GitHub Action runs `terraform plan` on PR and
`apply` on merge to main (AWS creds via OIDC), so "what is in main is what is
running" becomes literally true.

Planned repo layout:

```
nomad/
  terraform/          # AWS infra: SG, EC2 (Graviton), EBS, IAM, S3 state backend
  bootstrap/          # cloud-init + setup.sh: tailscale, claude, langs, tmux, mosh
  dotfiles/           # shell, tmux.conf, etc.
  Makefile            # make up / down / ssh / scale
  README.md           # the one-command story
  .github/workflows/  # terraform plan/apply via OIDC (phase 2)
```

---

## Decisions locked

- Name / codename: **Nomad**.
- Cloud: **AWS**, single-tenant **EC2** VM, **ARM (Graviton)**, **24/7**. Start
  small/cheap (**t4g.large/medium**), scale to **m7g/m8g** later via a ~1 min
  stop/start. **Fresh and isolated**, not reusing existing AWS instances.
- Disk: **gp3 EBS, encrypted**, start ~100 GB, live-growable.
- Perimeter: **Tailscale only**, zero public inbound, **tailnet lock**,
  **passkey-protected IdP login**. No SSM standing path.
- Access: **Tailscale SSH + mosh + tmux**, **Termux** on Android, client is
  disposable, iOS via Blink later for free.
- Credentials: **laptop-parity**, no scoping crusade. **Nothing in the repo, no
  SOPS, seeded manually** over the tailnet. Only provisioning secret is an
  ephemeral Tailscale auth key at apply time.
- Dev servers: private over the mesh via MagicDNS (`nomad:N`).
- Push notifications: **deferred**, doorbell-only when added.
- Reproducibility: **Terraform + cloud-init + dotfiles**, **GitHub source of
  truth**, S3 state, one-command `make up`, open-sourceable later.
- Region: **us-east-1** (or **us-west-2** if West Coast); avoid us-west-1.
  Pending final approval.
- Access auth: **Tailscale SSH + tailnet lock + account passkey**. Passkey is
  account MFA (rare, ~zero daily friction), tailnet lock is the anti-rogue-device
  control. Plain `ssh -L` kept available for port-forwarded one-time logins.
- Dev environment: bootstrap mirrors **VibeStack** developer-environment; CLI
  logins are headless (device-code or token paste) and done manually post-boot.

## Open items

- [ ] Final approval on region (recommend us-east-1, or us-west-2 if West Coast).
- [ ] Read VibeStack developer-environment to pin the exact bootstrap tool list.
- [ ] Tailscale auth-key flow: confirm single-use key passed to cloud-init at
      `make up`.
- [ ] Push relay choice (Pushover vs ntfy) when we un-defer it.
- [ ] GitOps phase 2: GitHub Actions terraform apply via OIDC (later).
- [ ] Maybe-later: a credential sync helper between laptop and box, only if the
      manual flow proves annoying.

Resolved: starting size (small t4g, scale later), secrets (manual, no SOPS, no
repo), reuse (start clean).
