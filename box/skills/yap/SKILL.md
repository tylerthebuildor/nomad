---
name: yap
description: Control yap, which reads your replies aloud on the user's phone. Use when the user asks to turn speech, voice, read-aloud or yap on or off, to stop or silence the current reply, to check whether yap is on or a phone is listening, to test it, or to change how much it reads (length, code blocks, speed). Triggers on "yap", "read it to me", "stop talking", "be quiet", "turn the voice off".
---

# yap: replies read aloud on the phone

This box has no speaker. A Stop hook turns each finished reply into a short,
speakable message and adds it to a feed; the user's phone (Termux) listens to
the feed over the tailnet and speaks it with Android's voice. You control it
from here with the `yap` command:

| The user wants | Run |
|---|---|
| it on / off | `yap on` · `yap off` (instant, every session) |
| to flip it | `yap toggle` |
| this reply to stop | `yap stop` |
| to know if it works | `yap status` (on/off and how many phones are listening) |
| to hear a test line | `yap test` |
| why something was not spoken | `yap log 20` |

Settings live in `~/.config/nomad/yap.env` (create it if missing, shell syntax):
`MAX_CHARS=1400` (shorter = less talking), `SPEAK_CODE=0` (1 reads code blocks
aloud), `RATE=1.0` (phone speech speed, 0.5 to 2.0; set on the phone).
Changes apply to the next reply.

If `yap status` shows 0 phones listening, the phone side is not running: the
user starts it in Termux with `yap listen nomad` (the phone setup does this on
its own when Termux opens), and it needs the Termux:API app. Do not try to fix
the phone from here; tell the user.
