#!/usr/bin/env bash
# Self-test. Runs everything against a throwaway HOME with a fake `claude`;
# never touches your real config.
#   bash tests/run.sh
#   /bin/bash tests/run.sh      # on macOS: also check with the built-in bash 3.2
here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ai-hub-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

unset CLAUDE_CONFIG_DIR CODEX_HOME GEMINI_CLI_HOME XDG_CONFIG_HOME XDG_STATE_HOME \
  AI_CONFIG_DIR AI_STATE_DIR AI_PROVIDERS CLA_ROOT AI_FO_COOLDOWN
export HOME=$tmp/home AI_NO_FZF=1 AI_YES=1
mkdir -p "$HOME/.claude" "$tmp/bin" "$tmp/work"
echo '{}' >"$HOME/.claude/settings.json"
TAB=$(printf '\t')
P=$HOME/.config/ai-hub/providers

# fake claude: logs "<config folder>|<args>"; account "a" ends on a usage limit
cat >"$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
printf '%s|%s\n' "$(basename "$cfg")" "$*" >>"$HOME/claude.log"
if [ "$(basename "$cfg")" = a ]; then
  sleep 1
  mkdir -p "$cfg/projects/-work"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"type":"assistant","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Claude AI usage limit reached|1700000000"}]}}' \
    >"$cfg/projects/-work/sess-123.jsonl"
fi
exit 0
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() {
  printf '  FAIL  %s\n' "$1"
  fails=$((fails + 1))
}
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}
ai() { bash "$here/bin/ai" "$@"; }
cla() { bash "$here/bin/cla" "$@"; }

echo "names"
(
  . "$here/lib/common.sh"
  for n in '' . .. .trash a/b 'a b' ../x 'x;y'; do
    if valid_name "$n"; then echo "FAIL accepts '$n'"; fi
  done
  for n in work work-2.a A_b; do
    valid_name "$n" || echo "FAIL rejects '$n'"
  done
) >"$tmp/names.out"
check "only safe names are accepted" test ! -s "$tmp/names.out"

echo "claude accounts"
touch "$HOME/keep-me"
check "cla rm .. is refused" eval '! cla rm ..'
check "home folder is untouched" test -f "$HOME/keep-me"
check "cla rm ../x is refused" eval '! cla rm ../x'
check "cla add .trash is refused" eval '! cla add .trash'
cla add work >/dev/null 2>&1
check "cla add creates the account" test -d "$HOME/.claude-accounts/work"
check "settings are shared by a link" test -L "$HOME/.claude-accounts/work/settings.json"
check "cla add twice is refused" eval '! cla add work'
check "reserved name is refused" eval '! cla add main'
check "cla ls lists it" sh -c 'bash "$1/bin/cla" ls | grep -q work' _ "$here"
cla mv work job >/dev/null 2>&1
check "cla mv renames" test -d "$HOME/.claude-accounts/job"
cla rm job >/dev/null 2>&1
check "cla rm moves to the trash" sh -c 'ls "$1/.claude-accounts/.trash" | grep -q "^job-"' _ "$HOME"
check "cla rm removes it from the list" test ! -e "$HOME/.claude-accounts/job"
: >"$HOME/claude.log"
cla main --x >/dev/null 2>&1
check "cla main starts claude with args" grep -q '^.claude|--x$' "$HOME/claude.log"

echo "agents"
ai add foo "echo hello" "Foo" >/dev/null 2>&1
check "ai add writes the line" grep -q "^foo${TAB}echo hello${TAB}Foo\$" "$P"
check "ai add refuses tabs" eval "! ai add bar \"a${TAB}b\""
check "ai add refuses bad names" eval '! ai add ../x echo'
ai edit foo "echo bye" >/dev/null 2>&1
check "ai edit keeps the label" grep -q "^foo${TAB}echo bye${TAB}Foo\$" "$P"
ai rm foo >/dev/null 2>&1
check "ai rm removes it" eval "! grep -q '^foo' \"$P\""
check "picker menu quits on q" sh -c 'printf "q\n" | bash "$1/bin/ai"' _ "$here"

if command -v jq >/dev/null 2>&1; then
  echo "usage"
  mkdir -p "$HOME/.claude-accounts/b"
  echo '{"rate_limits":{"five_hour":{"used_percentage":42.7,"resets_at":4102444800}}}' |
    CLAUDE_CONFIG_DIR="$HOME/.claude-accounts/b" bash "$here/scripts/statusline-usage.sh"
  check "status line saves usage" jq -e '.rate_limits.five_hour.used_percentage == 42.7' "$HOME/.claude-accounts/b/usage/usage.json"
  check "picker shows the usage" sh -c 'printf "q\n" | bash "$1/bin/cla" 2>&1 | grep -q "42%"' _ "$here"
  check "status line passes input on" sh -c 'echo "{}" | bash "$1/scripts/statusline-usage.sh" cat | grep -q "{}"' _ "$here"

  echo "shared trust"
  d=$(cd "$tmp/work" && pwd -P)
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$d" >"$HOME/.claude.json"
  mkdir -p "$HOME/.claude-accounts/t" "$HOME/.codex" "$HOME/.gemini"
  echo '{}' >"$HOME/.claude-accounts/t/.claude.json"
  : >"$HOME/.codex/config.toml"
  printf '{"%s":"DO_NOT_TRUST"}\n' "$d" >"$HOME/.gemini/trustedFolders.json"
  (cd "$tmp/work" && cla t) >/dev/null 2>&1
  check "off by default: nothing changed" jq -e '.projects == null' "$HOME/.claude-accounts/t/.claude.json"
  ai trust on >/dev/null 2>&1
  (cd "$tmp/work" && cla t) >/dev/null 2>&1
  check "account now trusts the folder" jq -e --arg d "$d" '.projects[$d].hasTrustDialogAccepted == true' "$HOME/.claude-accounts/t/.claude.json"
  check "codex now trusts the folder" grep -qF "[projects.\"$d\"]" "$HOME/.codex/config.toml"
  check "gemini DO_NOT_TRUST is kept" jq -e --arg d "$d" '.[$d] == "DO_NOT_TRUST"' "$HOME/.gemini/trustedFolders.json"
  check "a backup was made" test -f "$HOME/.claude-accounts/t/.claude.json.ai-hub.bak"
  (cd "$tmp/work" && cla t) >/dev/null 2>&1
  check "codex section is not added twice" test "$(grep -cF "[projects.\"$d\"]" "$HOME/.codex/config.toml")" = 1
  echo 'not json' >"$HOME/.claude-accounts/t/.claude.json"
  mkdir -p "$tmp/work2"
  d2=$(cd "$tmp/work2" && pwd -P)
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$d2" >"$HOME/.claude.json"
  (cd "$tmp/work2" && cla t) >/dev/null 2>&1
  check "invalid JSON is left unchanged" grep -qx 'not json' "$HOME/.claude-accounts/t/.claude.json"
  ai trust off >/dev/null 2>&1
  rm -rf "$HOME/.claude-accounts/t"

  echo "failover"
  mkdir -p "$HOME/.claude-accounts/a"
  ai failover on >/dev/null 2>&1
  ai failover order a b >/dev/null 2>&1
  check "order is saved" test "$(head -n 2 "$HOME/.config/ai-hub/failover-order" | tr '\n' ' ')" = "a b "
  : >"$HOME/claude.log"
  (cd "$tmp/work" && printf 'y\n' | bash "$here/bin/cla" a) >/dev/null 2>&1
  check "a is marked limited" test -f "$HOME/.local/state/ai-hub/limited/a"
  check "the session is copied to b" test -f "$HOME/.claude-accounts/b/projects/-work/sess-123.jsonl"
  check "b resumes the session" grep -q '^b|--resume sess-123 ' "$HOME/claude.log"
  check "status shows the limit" sh -c 'bash "$1/bin/ai" failover status | grep -q limited' _ "$here"
  check "clear refuses bad names" eval '! ai failover clear ../x'
  ai failover clear a >/dev/null 2>&1
  check "clear removes the limit" test ! -f "$HOME/.local/state/ai-hub/limited/a"
  : >"$HOME/claude.log"
  (cd "$tmp/work" && printf 'n\n' | bash "$here/bin/cla" a) >/dev/null 2>&1
  check "answering n stays put" eval "! grep -q '^b|' \"$HOME/claude.log\""
  ai failover off >/dev/null 2>&1
else
  echo "(jq not installed: skipped usage, trust and failover tests)"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "all passed"
else
  echo "$fails failed"
  exit 1
fi
