#!/usr/bin/env bash
# ccwatch installer.
#
#   curl -fsSL https://raw.githubusercontent.com/klemengit/ccwatch/main/install.sh | bash
#
# or, from a clone:  ./install.sh
#
# Installs the `ccwatch` and `ccwatch-hook` scripts and registers the hook in
# your Claude Code settings.json (idempotent — safe to run repeatedly).
#
# Env overrides:
#   CCWATCH_BIN        install dir for the scripts   (default: ~/.local/bin)
#   CLAUDE_SETTINGS    settings.json to edit         (default: ~/.claude/settings.json)
#   CCWATCH_REPO_RAW   raw base URL for curl install (default: GitHub main)
set -euo pipefail

REPO_RAW="${CCWATCH_REPO_RAW:-https://raw.githubusercontent.com/klemengit/ccwatch/main}"
BIN_DIR="${CCWATCH_BIN:-$HOME/.local/bin}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK_TIMEOUT=5
EVENTS=(SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop Notification SessionEnd SubagentStart SubagentStop)

die() { echo "ccwatch install: $*" >&2; exit 1; }
info() { echo "  $*"; }

command -v jq   >/dev/null || die "requires 'jq' (e.g. sudo apt install jq)."
command -v curl >/dev/null || die "requires 'curl'."

# Locate the source: prefer files next to this script (clone), else download.
SELF_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() { # $1 = repo-relative path, $2 = destination
  if [[ -n "$SELF_DIR" && -f "$SELF_DIR/$1" ]]; then
    cp "$SELF_DIR/$1" "$2"
  else
    curl -fsSL "$REPO_RAW/$1" -o "$2" || die "failed to download $1"
  fi
}

echo "Installing ccwatch…"
mkdir -p "$BIN_DIR"
fetch bin/ccwatch      "$BIN_DIR/ccwatch"
fetch bin/ccwatch-hook "$BIN_DIR/ccwatch-hook"
chmod +x "$BIN_DIR/ccwatch" "$BIN_DIR/ccwatch-hook"
info "scripts -> $BIN_DIR/{ccwatch,ccwatch-hook}"

HOOK_CMD="$BIN_DIR/ccwatch-hook"

# Register the hook in settings.json (create the file if absent, back it up).
mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' >"$SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON; aborting."
cp "$SETTINGS" "$SETTINGS.ccwatch.bak"

tmp="$(mktemp)"
jq \
  --arg cmd "$HOOK_CMD" \
  --argjson to "$HOOK_TIMEOUT" \
  --argjson events "$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -s .)" '
  reduce $events[] as $e (.;
    .hooks[$e] = ((.hooks[$e] // [])
      | if any(.[]?; (.hooks // [])[]?.command == $cmd) then .
        else . + [{hooks: [{type: "command", command: $cmd, timeout: $to}]}] end))
' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
info "hooks registered in $SETTINGS (backup: $SETTINGS.ccwatch.bak)"

echo "Done."
echo
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "⚠  $BIN_DIR is not on your PATH. Add this to your shell rc:"
     echo "     export PATH=\"$BIN_DIR:\$PATH\"" ; echo ;;
esac
echo "Next:"
echo "  1. Restart your Claude Code sessions so they pick up the new hooks."
echo "  2. Run 'ccwatch' in a spare terminal/zellij tab to see them."
