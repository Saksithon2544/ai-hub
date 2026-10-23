#!/usr/bin/env bash
# Claude Code status line command that saves plan usage for `ai`.
#
# Claude Code pipes JSON to the status line on every refresh; on Pro/Max plans it includes
# rate_limits (5-hour and weekly use, reset times). This saves that to
# $CLAUDE_CONFIG_DIR/usage/usage.json (default ~/.claude), one file per account, then passes
# the same JSON on to your own status line command, if you give one.
#
# In ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh"}
#   "statusLine": {"type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh my-statusline --flag"}

input=$(cat)
if command -v jq >/dev/null 2>&1; then
  rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
  if [ -n "$rl" ]; then
    dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage
    if mkdir -p "$dir" && tmp=$(mktemp "$dir/.usage.XXXXXX"); then
      if jq -n --argjson rl "$rl" '{saved_at: (now | floor), rate_limits: $rl}' >"$tmp"; then
        mv "$tmp" "$dir/usage.json"
      else
        rm -f "$tmp"
      fi
    fi
  fi
fi
if [ $# -gt 0 ]; then
  printf '%s' "$input" | "$@"
fi
exit 0
