---
name: standup
description: A two-way daily standup with your projects. First takes any fresh human context you share (meetings, pivots, priority changes) or reads it from the standup context log, then reviews your active git projects and prints a concise briefing with at most a couple of genuinely high-value "next task" nudges (usually zero). Read-only except the context/history logs. Invoke manually as /standup (Phase 0) or headless via `claude -p` on a schedule (Phase 1).
---

# Standup

A **two-way daily standup** between the developer and their projects: the developer
shares what changed in the human world, then the agent reports a tight briefing with
rare, high-value nudges. HIGH-DISCRETION: most mornings the right output is a short
status and **zero** new tasks. A rare, magical "oh yeah, that's exactly what I need
next" beats a pile of mediocre tasks. **Bias hard toward silence.**

## Configuration (defaults; honor any overrides the user states)

- `DEV_ROOT`: `~/dev`
- `ACTIVE_WINDOW_DAYS`: `7`
- `MAX_NUDGES`: `2` (hard cap across ALL projects combined)
- `CONTEXT_LOG`: `~/dev/_nomad/context.md` (human context the code cannot know)
- `HISTORY_FILE`: `~/dev/_nomad/standup-history.jsonl` (prior nudges, for dedup)
- Ignore under `DEV_ROOT`: `_secrets`, `_nomad`, `skills`, `nomad`, `_archive`,
  `archive`, and anything that is not a git repo.

## Step 1 , CONTEXT INTAKE (the human-in-the-loop part)

The agent cannot know what happened in the developer's meetings, pivots, or priority
changes. So before anything else:

- **Read `CONTEXT_LOG`** (recent entries, ~last 14 days), things the developer told
  you that git/code cannot reveal.
- **If running interactively** (a human can reply right now): ask, in one line,
  "Anything new I should know before today's briefing, meetings, pivots, priority or
  scope changes? (or say 'nothing')". WAIT for the reply. If they share anything,
  append it to `CONTEXT_LOG` as a timestamped entry, then continue.
- **If running headless/scheduled** (invoked via `claude -p`, nobody to answer): do
  NOT ask, just use what is already in `CONTEXT_LOG`.

**Fresh human context OUTRANKS code/git inference.** If the log says a direction was
abandoned, reprioritized, or handed off, do NOT propose tasks that contradict it,
and DO reflect the new priority. The most recent entries (especially since the last
run) carry the most weight.

## Step 2 , find active projects

List git repos directly under `DEV_ROOT` whose latest commit is within
`ACTIVE_WINDOW_DAYS`, excluding the ignore list. If none are active, still produce
the briefing (state = quiet) with zero nudges. Context from Step 1 may also make a
git-quiet project relevant (e.g. "starting X tomorrow").

## Step 3 , gather signals per active project (READ ONLY, never modify anything)

Concrete evidence of what is in-flight and what is next: recent `git log` (~last 10
commits) and uncommitted/staged changes; `TODO`/`FIXME`/`XXX` in recently-changed
files; a stated plan in `README.md`/`CLAUDE.md`/`TODO.md`/roadmap; failing or missing
tests for recently-changed code; open PRs / recently closed issues if `gh` is
available. Record what you observe; you will cite it.

## Step 4 , dedup

Read `HISTORY_FILE`. Never repeat a prior nudge or anything recent commits show is
done. If the developer acted on a past nudge, note it as progress, do not re-nudge.

## Step 5 , generate candidates, then cull HARD

Score each 1-5: "Would the developer act on this **today** and thank me?" Keep ONLY
4s and 5s, then:
- **Default to zero** if nothing scores 4+. Common and correct.
- **Hard cap `MAX_NUDGES`.**
- **Every nudge MUST cite a concrete signal** (file+line, failing test, commit,
  stated goal, or a specific line from the context log). No citation -> drop it.
- **Exclude generic filler** ("add tests", "improve docs", "refactor X") unless a
  specific cited trigger makes it the obvious next step.
- **Never contradict fresh context** from Step 1.

## Step 6 , write the briefing (concise, glance-over-coffee, not a report)

- If you took in new context this run, open with a one-line "Heard: <gist>" so the
  developer sees it was applied.
- One line per active project: name + current state + what changed recently.
- A **Nudges** section: 0 to `MAX_NUDGES` items, each = the task (one line) + the
  cited signal + why it is the next step. If zero: "Nothing urgent, all active
  projects are in a good state."

## Step 7 , record

Append each surfaced nudge to `HISTORY_FILE` as one JSON line
(`{"date","project","task","signal"}`); create the file/dir if needed.

## Guardrails

- **Read-only** on all project code: no edits, commits, pushes, or builds. Writes
  are limited to `CONTEXT_LOG` and `HISTORY_FILE`.
- **No network side effects** this phase: print the briefing to stdout. Later phases
  add a Telegram / PM-tool sink.
- **Bounded**: a few signal-reads per active project; sample recently-changed areas
  of large repos rather than exploring exhaustively.
- **A quiet, accurate briefing with zero nudges is a SUCCESS, not a failure.**
