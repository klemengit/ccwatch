# ccwatch

A tiny live dashboard for tracking **multiple Claude Code instances** at once.

If you run Claude Code in several terminal/zellij tabs (one per project), `ccwatch`
gives you a single pane showing each session, its current state, how long it's
been in that state, and its directory:

```
 ccwatch — Claude Code instances  (14:22:07, refresh 2s)

  PROJECT            STATE            AGE    DIR
  alpha              ⏳ working       42s    ~/projects/alpha
  beta               🔔 waiting input 10s    ~/projects/beta
  gamma              💤 idle          1m     ~/work/gamma
  ↳ alpha            ⏳ working       8s     ~/projects/alpha
  eta                ⏳ working       2m     ~/old/eta (stale)
```

It's pure Bash + `jq`. No daemon, no config — Claude Code's own hooks write a
small state file per session, and `ccwatch` renders them.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/klemengit/ccwatch/main/install.sh | bash
```

This installs `ccwatch` and `ccwatch-hook` into `~/.local/bin` and registers the
hook in `~/.claude/settings.json` (idempotent; your existing settings and other
hooks are preserved, and a `.ccwatch.bak` backup is written).

Requirements: `bash`, `jq`, `curl`.

Then **restart any running Claude Code sessions** so they pick up the hooks, and
run the dashboard in a spare tab:

```sh
ccwatch
```

## Usage

```
ccwatch            # live dashboard (Ctrl-C to quit)
ccwatch --once     # print one frame and exit (good for scripts/status bars)
ccwatch --help
ccwatch --version
```

### States

| State              | Meaning                                              |
|--------------------|------------------------------------------------------|
| ⏳ `working`        | Claude is processing your prompt / running tools.    |
| 🔔 `waiting input` | Blocked on you — a tool-permission approval or an answer to a question / elicitation form. |
| 💤 `idle`           | Not doing anything — finished, or freshly started.   |
| *(dim)* `(stale)`  | No activity for a while — may be interrupted.        |

> Note: a multiple-choice question (the `AskUserQuestion` tool) is detected via
> its `PreToolUse`/`PostToolUse` events. Tool-permission prompts use the
> `PermissionRequest`/`Notification` hooks.

Background **subagents** (Agent/Task tool) run under their own session id, so
they appear as separate rows prefixed with `↳`. Your top-level session still
shows its own state (e.g. `idle`) and stays promptable while the `↳` subagent
runs.

**AGE** is *time in the current state* (it does not reset on the per-tool
heartbeat). A row goes `(stale)` and greys out after `STALE_SECS` without any
activity, but **stays visible** — an open session is never removed just for
being idle. A top-level session is dropped only when its Claude process is gone:
a clean exit removes it via `SessionEnd`, and a hard kill is caught because
`ccwatch` records each session's process id and checks whether it's still alive.
`GC_SECS` time-based cleanup now only applies to subagent (`↳`) rows and to
legacy state files written before this feature (which carry no PID).

### Configuration (env vars)

| Variable          | Default                                   | Purpose                                  |
|-------------------|-------------------------------------------|------------------------------------------|
| `WATCH_INTERVAL`  | `2`                                       | Refresh interval (seconds).              |
| `STALE_SECS`      | `60`                                      | Idle time before a row greys out.        |
| `GC_SECS`         | `1800`                                    | Idle time before a row is removed (subagent rows / legacy no-PID files only). |
| `CCWATCH_DIR`     | `$XDG_RUNTIME_DIR/claude-instances`       | Where session state files live.          |

Example: `STALE_SECS=25 WATCH_INTERVAL=1 ccwatch`

## How it works

`install.sh` adds `ccwatch-hook` to these Claude Code hook events:

- `SessionStart` / `Stop` → `idle`
- `UserPromptSubmit` / `PostToolUse` / `PreToolUse` → `working` (PostToolUse is the heartbeat)
- `PreToolUse`(AskUserQuestion) / `PermissionRequest` / `Notification`(permission_prompt, elicitation_dialog) → `waiting input`
- `Notification`(idle_prompt) → `idle`
- `SessionEnd` → removes the session
- `SubagentStart`/`SubagentStop` → tracks background subagents as `↳` rows
  (removed on completion; stale/GC clean them up if `SubagentStop` doesn't
  fire — see Limitations)

Each event writes `$CCWATCH_DIR/<session_id>.json` with the state, two
timestamps — `updated` (last activity, drives staleness) and `since` (when the
state last changed, drives AGE) — and `pid`, the owning Claude Code process id
(found by walking up the hook's process ancestry to the `claude` process).
`ccwatch` renders those files and uses `pid` to tell open sessions from dead
ones.

The **PROJECT** label is the name of the session's enclosing git repository
(so any subdirectory of the same repo shows the same name); outside a repo it
falls back to the working directory's basename.

## Limitations

- **Interrupts aren't detected.** Claude Code fires no hook on Ctrl-C, so an
  interrupted session stays on its last state until your next action; after
  `STALE_SECS` it greys out. (Lower `STALE_SECS` if you want that sooner.)
- A single tool call longer than `STALE_SECS` will briefly show `(stale)` even
  though it's genuinely working.
- **Background subagent completion is unreliable.** Claude Code doesn't always
  fire `SubagentStop` for background subagents (issue #33049), so a finished
  `↳` row may linger until it goes stale (`STALE_SECS`) and is GC'd (`GC_SECS`).

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/klemengit/ccwatch/main/uninstall.sh | bash
```

or run `./uninstall.sh` from a clone. It strips the ccwatch hooks from
`settings.json` (leaving everything else intact) and removes the scripts.

## License

MIT
