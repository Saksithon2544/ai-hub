# shellcheck shell=bash
# Shared folder trust. OFF until you run `ai trust on`.
#
# Before an agent starts in a folder: if any agent (or any of your Claude accounts)
# already trusts that exact folder, mark it trusted in the others too, so they stop asking.
#  - only the exact folder; parent folders never count
#  - a choice an agent already has for the folder (e.g. Gemini "DO_NOT_TRUST",
#    Codex trust_level = "untrusted") is never changed
#  - JSON files are edited with json_edit (validated, backed up once, edited in place)
#
# Why off by default: trusting a folder lets an agent load that folder's own settings,
# hooks and MCP servers. Sharing trust means a repo you trusted once is trusted everywhere.

AI_TRUST_FLAG=$AI_CONFIG_DIR/trust-share
AI_TRUST_AGENTS="claude codex gemini qwen"

trust_on() { [ -e "$AI_TRUST_FLAG" ] && has jq; }

ai_trust() {
  case ${1:-status} in
    on)
      has jq || die "shared trust needs jq (brew install jq / apt install jq)"
      mkdir -p "$AI_CONFIG_DIR" && : >"$AI_TRUST_FLAG" && echo "shared folder trust: on"
      ;;
    off) rm -f "$AI_TRUST_FLAG" && echo "shared folder trust: off" ;;
    status) if trust_on; then echo "shared folder trust: on"; else echo "shared folder trust: off"; fi ;;
    *) die "usage: ai trust [on|off|status]" ;;
  esac
}

trust_share() {
  trust_on || return 0
  local d n hit=
  d=$(cd "$1" 2>/dev/null && pwd -P) || return 0 # agents store the resolved path
  case $d in *'"'* | *'\'* | *"$TAB"* | *'
'*) return 0 ;; esac # keep JSON/TOML quoting simple: skip odd paths
  for n in $AI_TRUST_AGENTS; do
    if "trust_${n}_has" "$d"; then
      hit=1
      break
    fi
  done
  [ -n "$hit" ] || return 0
  # every _add is a no-op where the folder is already trusted or has its own choice
  for n in $AI_TRUST_AGENTS; do "trust_${n}_add" "$d"; done
}

# ── Claude Code: .projects[<dir>].hasTrustDialogAccepted in each account's .claude.json
trust_claude_files() {
  local a f
  for a in $(acct_list); do
    f=$(acct_json "$a")
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}
trust_claude_file_has() {
  jq -e --arg d "$2" '.projects[$d].hasTrustDialogAccepted == true' "$1" >/dev/null 2>&1
}
trust_claude_has() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && trust_claude_file_has "$f" "$1" && return 0
  done <<EOF
$(trust_claude_files)
EOF
  return 1
}
trust_claude_add() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    trust_claude_file_has "$f" "$1" ||
      json_edit "$f" --arg d "$1" '.projects[$d].hasTrustDialogAccepted = true'
  done <<EOF
$(trust_claude_files)
EOF
}

# ── Codex: [projects."<dir>"] trust_level = "trusted" in config.toml
trust_codex_file() { echo "${CODEX_HOME:-$HOME/.codex}/config.toml"; }
trust_codex_level() {
  awk -v h="[projects.\"$1\"]" '
    $0 == h { s = 1; next }
    /^[[:space:]]*\[/ { s = 0 }
    s && /^[[:space:]]*trust_level[[:space:]]*=/ { v = $0; sub(/^[^=]*=/, "", v); gsub(/["[:space:]]/, "", v); print v; exit }' \
    "$(trust_codex_file)" 2>/dev/null
}
trust_codex_has() { [ "$(trust_codex_level "$1")" = trusted ]; }
trust_codex_add() {
  local f
  f=$(trust_codex_file)
  [ -f "$f" ] || return 0                         # Codex not set up
  grep -qF "[projects.\"$1\"]" "$f" && return 0   # any existing choice wins
  printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$1" >>"$f"
}

# ── Gemini / Qwen: trustedFolders.json {"<dir>": "TRUST_FOLDER" | "DO_NOT_TRUST" | ...}
trust_gem_file() {
  case $1 in
    gemini) echo "${GEMINI_CLI_HOME:-$HOME}/.gemini/trustedFolders.json" ;;
    qwen) echo "$HOME/.qwen/trustedFolders.json" ;;
  esac
}
trust_gem_has() {
  jq -e --arg d "$2" '.[$d] == "TRUST_FOLDER"' "$(trust_gem_file "$1")" >/dev/null 2>&1
}
trust_gem_add() {
  local f
  f=$(trust_gem_file "$1")
  [ -f "$f" ] || return 0
  jq -e --arg d "$2" 'has($d)' "$f" >/dev/null 2>&1 && return 0 # any existing choice wins
  json_edit "$f" --arg d "$2" '.[$d] = "TRUST_FOLDER"'
}
trust_gemini_has() { trust_gem_has gemini "$1"; }
trust_gemini_add() { trust_gem_add gemini "$1"; }
trust_qwen_has() { trust_gem_has qwen "$1"; }
trust_qwen_add() { trust_gem_add qwen "$1"; }
