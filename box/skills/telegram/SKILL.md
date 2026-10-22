---
name: telegram
description: Message the user on Telegram, send them files, and read what they sent. Use when the user asks to "send me", "text me", "ping me", "telegram me" something (a note, a to-do list, a plan, a markdown file), to "check my Telegram", "check my messages", "anything new on Telegram?", or to pick up a file or to-do list they sent from their phone; and, sparingly, on your own when a long job finishes, you are blocked on their input, or something failed that they need to know about now.
---

# telegram: the user's Telegram, from this box

The `tg` command talks to one chat only, the user's own DM with their bot. It
cannot message anyone else, and it ignores messages from anyone else.

If it says `not set up yet`, the user has not connected a bot. Tell them to run
`tg setup` in a terminal on the box (it walks them through @BotFather, takes a
minute, and needs their phone); do not try to set it up yourself.

| The user wants | Run |
|---|---|
| a message | `tg send "text"` (markdown to-dos `- [ ]` / `- [x]` show as ☐ / ☑) |
| a file, e.g. a plan | `tg send --file plan.md -c "the plan"` (several files: list them all) |
| what they sent you | `tg inbox` (newest first, default 10; `tg inbox 30`, `tg inbox --all`) |

## Reading the inbox

`tg inbox` fetches on demand and keeps everything locally. Newest comes first;
`●` marks messages new since the last check, shown in full; `○` ones were seen
before and are shortened. Files and photos they sent are saved under
`~/inbox/telegram/` with the path printed: read them from there.

Favor the most recent messages: when they say "check my Telegram", what they
just sent is usually what they mean. Older ones are context, not a to-do list,
unless they say otherwise. Telegram only holds unread messages for 24 hours, but
anything already fetched stays in the local history.

## Sending

Keep messages short and lead with the outcome. Long content (a plan, notes,
a report) goes as a markdown file with `--file`, not as a wall of text.

Pinging on your own is fine only when it is worth a phone buzz: a long or
background job finished and they are likely away, you are blocked on their
decision, or something failed that cannot report itself. Never for routine
progress, and never while they are clearly active in the session. If unsure,
do not ping.

Examples: `tg send "Deploy finished ✅, smoke tests green."` ·
`tg send "Blocked: the migration needs the DB password."`
