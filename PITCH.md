# Nomad pitch

## In one breath

> A completely locked-down cloud computer you reach only from your phone. A
> hardened EC2 box, Tailscale as the single way in, and a terminal on your phone.
> That is all you need to be a nomad and build entire businesses on the go.

## Tagline options

- Leave the laptop. Build from anywhere.
- Your whole dev machine, in the cloud, lived in from your phone.
- The laptop was the leash. Cut it.

## One-liner

Nomad turns a single hardened AWS box into the only computer you need: sealed off
from the public internet, reachable only through Tailscale, driven from a terminal
on your phone. Work from anywhere, carry nothing.

## The pitch (refined from the napkin version)

You do not need to carry a laptop to build software anymore. Most of the work is
prompting an agent, and you can do that from your phone. What is missing is the
machine: your environment, your credentials, your tools. Nomad puts that machine
in the cloud and locks it down so hard that the only way in is your phone.

It is three pieces and nothing else:

1. A hardened EC2 instance with zero open ports to the public internet.
2. Tailscale as the single, private path in, gated by a hardware passkey.
3. A terminal app on your phone (Termux on Android, Blink on iOS).

That is the whole thing. No laptop to carry, open, and tether. No VPN appliance,
no open SSH port, no dashboard. Just you, your phone, and a full development
machine you can drive from a train, a beach, or another continent. Enough to
build and run an entire business on the go.

## Honest framing (keep the claims true)

- Not "unhackable" or "1,000% secure." The honest line is stronger and more
  credible: no realistic way in without millions of dollars or thousands of
  hours.
- It is laptop-parity security plus a hardened perimeter, not magic. The win is
  deleting the public attack surface, not inventing new cryptography.
- It is a personal setup shared as open source, not a managed service. You run
  your own box on your own AWS and Tailscale accounts.
