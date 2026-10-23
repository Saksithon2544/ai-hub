# shellcheck shell=bash
# The picker: fzf when installed (and AI_NO_FZF is unset), else a numbered menu.
# Each row is "<id><TAB><shown text>"; id is c:<claude account> or p:<provider>.

row_claude() {
  local a=$1 e p5 r5 p7 r7 age
  e=$(acct_email "$a")
  IFS='|' read -r p5 r5 p7 r7 age <<EOF
$(claude_usage "$(acct_dir "$a")")
EOF
  if [ -n "$e" ]; then
    e=$(printf '%-28.28s' "$e")
  else
    e=$(printf '\033[31m%-28s\033[0m' 'not logged in')
  fi
  printf 'c:%s\t\033[1;36m%-10s\033[0m %s %s  %s%s\n' "$a" "$a" "$e" \
    "$(bar 5h "$p5" "$r5")" "$(bar 7d "$p7" "$r7")" "$(age_note "$age")"
}

row_prov() {
  local n=$1 l usage w1 p1 r1 w2 p2 r2
  l=$(prov_get "$n" 3)
  case $(prov_agent "$n") in
    codex)
      IFS='|' read -r w1 p1 r1 w2 p2 r2 <<EOF
$(codex_usage "$(prov_codex_home "$n")")
EOF
      usage="$(bar "${w1:-5h}" "$p1" "$r1")  $(bar "${w2:-7d}" "$p2" "$r2")"
      ;;
    *) usage=$(dim 'no usage data') ;;
  esac
  printf 'p:%s\t\033[1;36m%-10s\033[0m %-28.28s %s\n' "$n" "$n" "${l:-$n}" "$usage"
}

# ai_rows [claude]: every agent, the claude provider expanded into its accounts.
# With "claude": only the Claude accounts.
ai_rows() {
  local n a
  if [ "${1:-}" = claude ]; then
    for a in $(acct_list); do row_claude "$a"; done
    return
  fi
  for n in $(prov_names); do
    if [ "$n" = claude ]; then
      for a in $(acct_list); do row_claude "$a"; done
    else
      row_prov "$n"
    fi
  done
}

# choose <title> <rows>: prints the chosen id; fails on cancel
choose() {
  local title=$1 rows=$2 line
  [ -n "$rows" ] || {
    warn "nothing to pick yet. add an agent: ai add <name> <command>"
    return 1
  }
  if has fzf && [ -z "${AI_NO_FZF:-}" ]; then
    line=$(printf '%s\n' "$rows" | fzf --ansi --delimiter="$TAB" --with-nth=2.. --height=40% \
      --reverse --border=rounded --header="$title  ·  enter start  ·  esc quit" --prompt='› ') || return 1
  else
    line=$(menu "$title" "$rows") || return 1
  fi
  printf '%s\n' "${line%%"$TAB"*}"
}

# numbered menu, drawn on stderr, answer read from stdin
menu() {
  local title=$1 i=0 line ans
  local -a rows
  while IFS= read -r line; do
    [ -n "$line" ] && rows[${#rows[@]}]=$line
  done <<EOF
$2
EOF
  {
    printf '\n  \033[1m%s\033[0m\n\n' "$title"
    for line in "${rows[@]}"; do
      i=$((i + 1))
      printf '  \033[2m%2d\033[0m  %s\n' "$i" "${line#*"$TAB"}"
    done
    printf '\n  number to start · q to quit: '
  } >&2
  read -r ans || return 1
  case $ans in
    '' | q | Q) return 1 ;;
    *[!0-9]*)
      warn "not a number: $ans"
      return 1
      ;;
  esac
  if [ "$ans" -lt 1 ] || [ "$ans" -gt "${#rows[@]}" ]; then
    warn "no row $ans"
    return 1
  fi
  printf '%s\n' "${rows[$((ans - 1))]}"
}

# pick_and_run <all|claude> [args]: pick a row and start it in this folder
pick_and_run() {
  local mode=$1 id title="AI agents"
  shift
  [ "$mode" = claude ] && title="Claude accounts"
  id=$(choose "$title" "$(ai_rows "$mode")") || return 0
  run_id "$id" "$@"
}

run_id() {
  local id=$1 n
  shift
  case $id in
    c:*) run_claude "${id#c:}" "$@" ;;
    p:*)
      n=${id#p:}
      trust_share "$PWD"
      launch "$(prov_get "$n" 2)" "$@"
      ;;
  esac
}
