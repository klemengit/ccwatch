# ccwatch

A tiny live dashboard for tracking **multiple Claude Code instances** at once.

If you run Claude Code in several terminal/zellij tabs (one per project), `ccwatch`
gives you a single pane showing each session, its current state, how long it's
been in that state, and its directory:

```
 ccwatch — Claude Code instances  (14:22:07, refresh 2s)

  PROJECT            STATE            AGE    DIR
  epsilon            🟢 running       4s     ~/src/epsilon
  alpha              ⏳ working       42s    ~/projects/alpha
  beta               🔔 needs perm    10s    ~/projects/beta
  gamma              ✅ done          17s    ~/work/gamma
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
| 🟢 `running`        | Session just started.                                |
| ⏳ `working`        | Claude is processing your prompt / running tools.    |
| 🔔 `needs perm`     | Blocked waiting for you to approve a tool.           |
| ✅ `done`           | Claude finished responding.                          |
| ✅ `waiting_input`  | Idle at the prompt, waiting for your next message.   |
| *(dim)* `(stale)`  | No activity for a while — may be interrupted or idle.|

**AGE** is *time in the current state* (it does not reset on the per-tool
heartbeat). A row goes `(stale)` and greys out after `STALE_SECS` without any
activity, and is removed entirely after `GC_SECS` (e.g. a hard-killed session).

### Configuration (env vars)

| Variable          | Default                                   | Purpose                                  |
|-------------------|-------------------------------------------|------------------------------------------|
| `WATCH_INTERVAL`  | `2`                                       | Refresh interval (seconds).              |
| `STALE_SECS`      | `60`                                      | Idle time before a row greys out.        |
| `GC_SECS`         | `1800`                                    | Idle time before a row is removed.       |
| `CCWATCH_DIR`     | `$XDG_RUNTIME_DIR/claude-instances`       | Where session state files live.          |

Example: `STALE_SECS=25 WATCH_INTERVAL=1 ccwatch`

## How it works

`install.sh` adds `ccwatch-hook` to these Claude Code hook events:

- `SessionStart` → `running`
- `UserPromptSubmit` / `PostToolUse` → `working` (PostToolUse is the heartbeat)
- `Notification` → `needs perm` / `waiting_input`
- `Stop` → `done`
- `SessionEnd` → removes the session

Each event writes `~$CCWATCH_DIR/<session_id>.json` with the state plus two
timestamps: `updated` (last activity, drives staleness) and `since` (when the
state last changed, drives AGE). `ccwatch` just renders those files.

## Limitations

- **Interrupts aren't detected.** Claude Code fires no hook on Ctrl-C, so an
  interrupted session stays on its last state until your next action; after
  `STALE_SECS` it greys out. (Lower `STALE_SECS` if you want that sooner.)
- A single tool call longer than `STALE_SECS` will briefly show `(stale)` even
  though it's genuinely working.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/klemengit/ccwatch/main/uninstall.sh | bash
```

or run `./uninstall.sh` from a clone. It strips the ccwatch hooks from
`settings.json` (leaving everything else intact) and removes the scripts.

## License

MIT
