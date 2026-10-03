# Standup (the daily briefing agent)

A scheduled, high-discretion agent that reviews your active projects and, only when
it is genuinely worth it, nudges you with the next thing to do, **after** taking in
any fresh human context you share. The reframe that keeps this sane: **a two-way
daily standup with the AI, not an autonomous dev team.** You share what changed in
the human world; it reports a tight briefing with rare, magical nudges, never a
flood of mediocre tasks. (Invoked as `/standup`; formerly "nomad-planner".)

## Methodology: phase it, validate the base first

Core principle: **prove the hard part cheaply before building the system.** Each
phase is independently useful, you can stop at any of them, and you build the next
only once the previous earns it. Instant feedback beats building a whole pipeline
and discovering the foundation, the quality of the nudges, is bad.

### Phase 0 , validate the discretion (zero infrastructure)
The discretion + context intake is a Claude Code **skill** (`standup`) you run **by
hand** as `/standup` a few mornings against your active projects. Judge one thing:
are the nudges magical or noise? Tune. No cron, no Telegram, no PM tool.

### Phase 1 , the daily nudge
A cron job (early morning) runs the skill headless (`claude -p`) and posts the
briefing to a private **Telegram** bot. You wake to it. Still no PM tool, no
execution. **Likely the whole product for a long time.**

### Phase 2 (optional) , persistent backlog
Nudges become tracked/approvable items behind a **thin adapter**: **GitHub Issues**
first (free, repo-native), swappable to **Linear** (or a third tool) later with no
change to the planning logic.

### Phase 3 (the ultimate goal, maybe much later) , execution
An agent works an approved task on a branch and opens a **PR (never auto-merge)**.
Only once Phases 0-2 have a **track record of consistently good tasks**. Highest
risk, most optional.

## Context intake: the human-in-the-loop part

The agent can't know what happened in your meetings, pivots, or priority changes,
you were the one in the room. So the standup is **two-way**, via a single
append-only **context log** (`~/dev/_nomad/context.md`) the skill reads on every
run. Fresh human context **outranks** code/git inference: if you said "we abandoned
X," it stops proposing X.

The log gets filled two ways, which also solves the "the 6am cron can't ask me"
problem:

- **Interactive** (when you run `/standup` yourself): it opens by asking "anything
  new I should know?" You voice-rant via Wispr; it's saved and applied to this run.
  Only fires when there's a human to answer (skipped in headless cron runs).
- **Async, anytime** (for the unattended cron, and whenever): a tiny `note` command
  on the box. `mosh` in, run `note`, speak your meeting update, it appends to the
  log. The next standup incorporates it. (Repo: `bin/note` -> box `~/.local/bin/note`.)
  Slicker later: make the Phase 1 Telegram bot **bidirectional**, text it after a
  meeting and it appends to the log, turning the bot into your standup channel.

Durable shifts (a real pivot) can later be distilled into a project's `CLAUDE.md`
so they persist without re-reading the whole log; Phase 0 just reads the recent log.

## The discretion design (the heart)

- **Default to zero.** Proposing nothing is the normal, correct outcome most days.
- **Active projects only** (~7d git activity); ignore dormant folders.
- **Score each candidate 1-5** on "would I act on this today?"; surface only 4-5s;
  **hard cap ~2/day**.
- **Cite the concrete signal** for every nudge (TODO/FIXME, failing test,
  half-finished PR, stated goal, or a line from the context log). No signal -> none.
- **Dedup** against a small history file.
- **Never contradict fresh context.**
- **Briefing always posts; nudges rarely.** A quiet "nothing urgent" is a success.

## Mechanics (confirmed)

- Runs on the box via **cron + `claude -p`** (headless), NOT cloud Routines.
- Bounded via `timeout` + prompt stop-conditions + **read-only, scoped
  `--allowedTools`** (no `--max-turns` in the CLI).
- Cost via `--output-format json`. Telegram via a bot + Bot API `curl`.

## Packaging (ship it, generically)

Part of the **shareable Nomad bundle**, not a one-off:
- `skills/standup/SKILL.md` is **generic** (configurable dev root, active-window,
  caps, log paths; no hardcoded project names). Installs to the box's
  `~/.claude/skills/standup/`, exposed as `/standup`.
- `bin/note` installs to `~/.local/bin/note` on the box.
- Phase 1's cron + Telegram ship as documented, reproducible steps (bot token +
  chat id are the user's own, never in the repo).

## Status

- Phase 0: `skills/standup/SKILL.md` + `bin/note` written and installed on the box.
  Context log at `~/dev/_nomad/context.md`. Test with `/standup` (and `note`).
- Phases 1-3 not built; pursue in order, only as each earns it.
