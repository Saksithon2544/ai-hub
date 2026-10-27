# shellcheck shell=bash
# The agent list: $AI_PROVIDERS, one agent per line as "name<TAB>command<TAB>label".
# The command runs like a shell alias, so quotes and VAR=value prefixes work, e.g.
#   work<TAB>CODEX_HOME=~/.codex-work codex<TAB>Codex (work)

AI_KNOWN="claude codex gemini qwen opencode kimi"

prov_label() {
  case $1 in
    claude) echo "Claude Code" ;;
    codex) echo "Codex CLI" ;;
    gemini) echo "Gemini CLI" ;;
    qwen) echo "Qwen Code" ;;
    opencode) echo "OpenCode" ;;
    kimi) echo "Kimi Code" ;;
    *) echo "$1" ;;
  esac
}

# first run: list the known agents that are installed
prov_seed() {
  [ -e "$AI_PROVIDERS" ] && return 0
  mkdir -p "$(dirname "$AI_PROVIDERS")" || return 1
  local n
  for n in $AI_KNOWN; do
    has "$n" && printf '%s\t%s\t%s\n' "$n" "$n" "$(prov_label "$n")"
  done >"$AI_PROVIDERS"
}
# ai scan: add the known agents installed since (the list is only seeded on first run)
ai_scan() {
  local n found=
  prov_seed
  for n in $AI_KNOWN; do
    if has "$n" && ! prov_has "$n"; then
      prov_put "$n" "$n" "$(prov_label "$n")" && echo "added $n" && found=1
    fi
  done
  [ -n "$found" ] || echo "nothing new. installed agents are already listed (see: ai ls)"
}
prov_names() {
  prov_seed
  cut -f1 "$AI_PROVIDERS"
}
# prov_get <name> <field: 1 = name, 2 = command, 3 = label>
prov_get() {
  prov_seed
  tsv_get "$AI_PROVIDERS" "$1" "$2"
}
prov_has() { [ -n "$1" ] && [ -n "$(prov_get "$1" 1)" ]; }
# the CLI a provider runs: first word after any VAR=value, without its folder
prov_agent() {
  prov_get "$1" 2 | awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/) { n = split($i, p, "/"); print p[n]; exit } }'
}

# prov_put <name> [command label]: add, or replace in place (keeps line order). No command = delete.
prov_put() {
  prov_seed
  tsv_put "$AI_PROVIDERS" "$@"
}

# a field must be one line without tabs (the file is tab separated)
one_line() {
  case $1 in *"$TAB"* | *'
'*) return 1 ;; esac
  return 0
}

ai_ls() {
  local n c l
  prov_seed
  while IFS="$TAB" read -r n c l; do
    [ -n "$n" ] && printf '\033[1;36m%-10s\033[0m %-40s \033[2m%s\033[0m\n' "$n" "$c" "$l"
  done <"$AI_PROVIDERS"
}

ai_add() {
  local n=${1:-} c=${2:-} l=${3:-}
  [ -n "$n" ] && [ -n "$c" ] || die "usage: ai add <name> <command> [label]"
  need_name "$n"
  one_line "$c" && one_line "$l" || die "command and label must be one line without tabs"
  prov_has "$n" && die "'$n' already exists. change it with: ai edit $n <command>"
  prov_put "$n" "$c" "${l:-$(prov_label "$n")}" && echo "added $n -> $c"
}

ai_edit() {
  local n=${1:-} c=${2:-} l=${3:-}
  [ -n "$n" ] && [ -n "$c" ] || die "usage: ai edit <name> <command> [label]"
  prov_has "$n" || die "no agent '$n'. see: ai ls"
  one_line "$c" && one_line "$l" || die "command and label must be one line without tabs"
  prov_put "$n" "$c" "${l:-$(prov_get "$n" 3)}" && echo "saved $n -> $c"
}

ai_rm() {
  local n=${1:-}
  prov_has "$n" || die "no agent '$n'. see: ai ls"
  confirm "remove '$n' from the agent list?" || return 1
  prov_put "$n" && echo "removed $n (add it back with: ai add $n <command>)"
}
