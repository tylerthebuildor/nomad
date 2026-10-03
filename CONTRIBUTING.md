# Contributing

Thanks for helping. Nomad is opinionated and phone-first, so the bar for a change
is: does it make the box safer, or using it from a phone nicer?

## Making a change

1. Branch from `main` and open a pull request; every change needs the owner's
   review and passing checks before it merges (the rules for `main` are in
   `.github/rulesets/main.json`).
2. Run the checks first. They are the same ones CI runs:

   ```sh
   make check   # secret scan, shellcheck, terraform fmt/validate, actionlint
   ```

   Needs `gitleaks`, `shellcheck`, `terraform` and `actionlint`
   (`brew install gitleaks shellcheck terraform actionlint`).
3. Test on a real box when you touch the setup: use your own AWS account and a
   separate name so nothing collides, then tear it down:

   ```sh
   make up PROJECT=yourtest REGION=us-west-2
   make down PROJECT=yourtest REGION=us-west-2
   ```

## Style

- Shell scripts are bash, and the ones that run on your computer stay compatible
  with bash 3.2 (macOS).
- Output is one line per step (✓ – ! ✗), sized for a ~50-column phone screen;
  use the colors and helpers in `lib/ui.sh`.
- A prompt that does anything you cannot undo treats "no answer" as **no**.
- Never commit secrets or personal details (keys, tokens, account IDs, emails,
  tailnet names). Personal settings go in `config/*.env`, which is gitignored.
- New sign-in services are one file in `auth/` (see `auth/README.md`).
