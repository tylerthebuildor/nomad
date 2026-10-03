# Security

Nomad is a dev box whose whole design is "one door": no public ports, access only
over your Tailscale network. Reports that could weaken that are very welcome.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through GitHub:
**Security → Report a vulnerability** on this repository. Include what you found,
how to reproduce it, and what it lets someone do. You will get a reply within a
few days.

## Scope

In scope: anything in this repo, for example Terraform that opens a port, a
script that leaks a credential or token, the short sign-in link (`auth`) being
reachable from outside your tailnet, or tailnet lock / key handling in
`bootstrap/tailscale.sh`.

Out of scope: vulnerabilities in AWS, Tailscale, or the CLIs Nomad installs
(report those to their projects), and setups that remove Nomad's protections on
purpose (for example opening the security group).

## What Nomad never does

- Commit secrets: personal settings live in `config/*.env` (gitignored), and
  every pull request runs a secret scan over the whole history.
- Store the Tailscale API token or tailnet lock recovery secrets: the token lives
  in memory for one `make up`; recovery secrets are shown once, for you to save.
