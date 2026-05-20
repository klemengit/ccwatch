#!/usr/bin/env bash
# ccwatch uninstaller. Removes the ccwatch hook from settings.json and deletes
# the installed scripts. Leaves the runtime registry dir alone (it self-cleans).
set -euo pipefail

BIN_DIR="${CCWATCH_BIN:-$HOME/.local/bin}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK_CMD="$BIN_DIR/ccwatch-hook"
EVENTS=(SessionStart UserPromptSubmit PostToolUse Stop Notification SessionEnd)

command -v jq >/dev/null || { echo "uninstall: requires 'jq'." >&2; exit 1; }

if [[ -f "$SETTINGS" ]] && jq -e . "$SETTINGS" >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.ccwatch.bak"
  tmp="$(mktemp)"
  jq \
    --arg cmd "$HOOK_CMD" \
    --argjson events "$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -s .)" '
    reduce $events[] as $e (.;
      if (.hooks[$e]?) then
          .hooks[$e] |= ( map(.hooks |= map(select(.command != $cmd)))
                          | map(select((.hooks // []) | length > 0)) )
        | (if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end)
      else . end)
    | (if (.hooks? // {}) == {} then del(.hooks) else . end)
  ' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
  echo "Removed ccwatch hooks from $SETTINGS (backup: $SETTINGS.ccwatch.bak)"
else
  echo "No valid $SETTINGS found; skipping hook removal."
fi

rm -f "$BIN_DIR/ccwatch" "$BIN_DIR/ccwatch-hook"
echo "Removed $BIN_DIR/{ccwatch,ccwatch-hook}"
echo "Done. (Runtime registry, if any, will self-clean.)"
