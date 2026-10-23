# shellcheck shell=bash
# Shared helpers: paths, name checks, confirmation, safe JSON edits.

AI_VERSION=0.1.0
AI_CONFIG_DIR=${AI_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-hub}
AI_STATE_DIR=${AI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ai-hub}
AI_PROVIDERS=${AI_PROVIDERS:-$AI_CONFIG_DIR/providers}
CLA_ROOT=${CLA_ROOT:-$HOME/.claude-accounts}
# The Claude config dir of the "main" account, as it was when ai started.
AI_MAIN_CFG=${CLAUDE_CONFIG_DIR:-}
TAB=$(printf '\t')

has() { command -v "$1" >/dev/null 2>&1; }
warn() { printf 'ai: %s\n' "$*" >&2; }
die() {
  warn "$@"
  exit 1
}
dim() { printf '\033[2m%s\033[0m' "$1"; }
rep() {
  local s='' i=0
  while [ "$i" -lt "$2" ]; do
    s=$s$1
    i=$((i + 1))
  done
  printf '%s' "$s"
}

# Names become folder names, so only safe ones are allowed: letters, digits, . _ -
# Never empty and never starting with "." (this blocks ".", ".." and ".trash").
valid_name() {
  case $1 in '' | .* | *[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}
need_name() {
  valid_name "$1" || die "invalid name '$1': use letters, digits, . _ - (not starting with .)"
}

# Ask y/N. AI_YES=1 answers yes (for scripts and tests).
confirm() {
  [ "${AI_YES:-}" = 1 ] && return 0
  local a
  printf '%s [y/N] ' "$1" >&2
  read -r a || return 1
  case $a in y | Y | yes | YES) return 0 ;; esac
  return 1
}

# json_edit <file> <jq args...>: change one JSON file safely.
#  - skips files that are missing or not valid JSON
#  - keeps a one-time backup <file>.ai-hub.bak
#  - only replaces the file when the result is valid, non-empty JSON
#  - writes back in place, so permissions and symlinks stay as they were
json_edit() {
  local f=$1 tmp
  shift
  [ -f "$f" ] && has jq || return 0
  jq -e . "$f" >/dev/null 2>&1 || {
    warn "skipped $f: not valid JSON"
    return 0
  }
  tmp=$(mktemp "${TMPDIR:-/tmp}/ai-hub.XXXXXX") || return 1
  if jq "$@" "$f" >"$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    [ -e "$f.ai-hub.bak" ] || cp -p "$f" "$f.ai-hub.bak"
    cat "$tmp" >"$f"
  else
    warn "could not update $f; left it unchanged"
  fi
  rm -f "$tmp"
}

# launch <saved command> [args]: run a saved command like a shell alias, with extra args.
# On macOS caffeinate keeps the machine awake while the agent runs.
launch() {
  local c=$1
  shift
  [ -n "$c" ] || {
    warn "no command to run"
    return 1
  }
  if has caffeinate; then
    caffeinate -i bash -c "$c"' "$@"' ai "$@"
  else
    bash -c "$c"' "$@"' ai "$@"
  fi
}
