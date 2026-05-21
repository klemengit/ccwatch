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

There's also an optional GNOME tray mode, **`ccwatch-tray`**, that puts one
colour-coded indicator per session in the top bar (with click-to-focus on the
host terminal). See [Tray mode](#tray-mode-gnome) below.

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

## Tray mode (GNOME)

`ccwatch-tray` is an optional second renderer of the same state files. Instead
of a TUI table it spawns **one [AyatanaAppIndicator](https://github.com/AyatanaIndicators/libayatana-appindicator) per session** in the
GNOME top bar:

- a coloured disc — 🟢 idle / 🔵 working / 🟡 waiting input / ⚪ stale —
- a short project-name label next to the disc, and
- a menu with **Focus terminal** and **Copy cwd**.

Subagents appear with a `↳` prefix on the label, same as in the TUI.

### Requirements

```sh
sudo apt install python3-gi python3-gi-cairo \
                 gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1
```

For click-to-focus on **Wayland** (the GNOME default), install the
[`activate-window-by-title`](https://github.com/lucaswerkmeister/activate-window-by-title)
GNOME Shell extension and enable it. The extension exposes a D-Bus method that
runs inside the compositor and so isn't blocked by Wayland's focus-stealing
prevention. Without it the menu items still work except for **Focus terminal**,
which will show a one-time notification telling you to install the extension.
On X11, no extension is needed.

### Run it

```sh
ccwatch-tray
```

To start it automatically with your session, drop a file at
`~/.config/autostart/ccwatch-tray.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=ccwatch tray
Exec=ccwatch-tray
X-GNOME-Autostart-enabled=true
```

### How the focus targeting works

On every hook event, `ccwatch-hook` sets the host terminal's title via the
OSC 2 escape sequence to `[ccw:<short-id>] Claude · <project> · <state>`
(best-effort; silently skipped if it has no controlling tty). The tag
`ccw:<short-id>` is stored in the session's JSON and used as a substring match
for `activate-window-by-title`, so the user's shell prompt or terminal-specific
title decorations don't break focus.

The title is only rewritten for top-level sessions, never for background
subagents — those don't have their own terminal window.

### Zellij caveat

If your Claude Code session runs inside a **zellij** pane, click-to-focus
doesn't work: zellij captures the OSC 2 escape and uses it as the *pane title
within zellij*, so the outer terminal window's title doesn't contain our
`ccw:<id>` tag and `activate-window-by-title` has nothing to match. Zellij's
own CLI has no "focus pane by id" verb (as of 0.43.x) either, so we can't
route focus through zellij. The hook still stores `zellij_session` and
`zellij_pane_id` in the JSON, and clicking the indicator pops up a
notification with those identifiers so you can switch panes by hand. For
true click-to-focus, run Claude in plain terminal windows (one per session)
instead of zellij panes.

## Limitations

- **Interrupts aren't detected.** Claude Code fires no hook on Ctrl-C, so an
  interrupted session stays on its last state until your next action; after
  `STALE_SECS` it greys out. (Lower `STALE_SECS` if you want that sooner.)
- A single tool call longer than `STALE_SECS` will briefly show `(stale)` even
  though it's genuinely working.
- **Background subagent completion is unreliable.** Claude Code doesn't always
  fire `SubagentStop` for background subagents (issue #33049), so a finished
  `↳` row may linger until it goes stale (`STALE_SECS`) and is GC'd (`GC_SECS`).
- **Tray:** terminal titles are rewritten by the hook so the tray can find
  them. If your shell prompt also sets `PROMPT_COMMAND`/`precmd` titles, the
  hook's title wins on each Claude event but your prompt may overwrite it
  between events — focus still works because we match by the `ccw:<id>`
  substring, but the visible title may flicker.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/klemengit/ccwatch/main/uninstall.sh | bash
```

or run `./uninstall.sh` from a clone. It strips the ccwatch hooks from
`settings.json` (leaving everything else intact) and removes the scripts.

## License

MIT
