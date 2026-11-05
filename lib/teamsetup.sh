# shellcheck shell=bash
# The easy way into a team: `ai team setup` asks a few questions and sets everything up,
# `ai do "<task>"` gives the team a task, and `ai team access` lists the folders outside
# this one that every member may use.

AI_TEAM_ACCESS=$AI_CONFIG_DIR/team-access # one folder per line
# what a member can be good at, offered in `ai team setup`
TEAM_ROLES='new features and large refactors
writing and running tests
docs and small fixes
code review: finding bugs and risks
reading a big codebase and research'

# ---- extra folders -------------------------------------------------------------------

# the saved folders that still exist
team_access_dirs() {
  local d
  [ -r "$AI_TEAM_ACCESS" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] && [ -d "$d" ] && echo "$d"; done <"$AI_TEAM_ACCESS"
}
# team_access_opts <agent>: the folders as options of that CLI, quoted for a saved command
team_access_opts() {
  local d out=''
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $1 in
      claude) out="$out $(printf '%q' "$d")" ;;
      codex) out="$out --add-dir $(printf '%q' "$d")" ;;
      gemini | qwen) out="$out --include-directories $(printf '%q' "$d")" ;;
    esac
  done <<LIST
$(team_access_dirs)
LIST
  [ -n "$out" ] || return 0
  # claude takes many folders after one --add-dir; -p, which comes next, ends the list
  case $1 in claude) echo "--add-dir$out" ;; *) echo "${out# }" ;; esac
}

team_access() {
  case ${1:-} in
    '' | ls) team_access_show ;;
    add) [ -n "${2:-}" ] || die "usage: ai team access add <folder>"; team_access_add "$2" || exit 1 ;;
    rm) [ -n "${2:-}" ] || die "usage: ai team access rm <folder>"; team_access_rm "$2" ;;
    *) die "usage: ai team access [add <folder> | rm <folder>]" ;;
  esac
}
team_access_show() {
  local d n=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$n" -eq 0 ] && echo "the team may also read and edit:"
    echo "  $d"
    n=$((n + 1))
  done <<LIST
$(team_access_dirs)
LIST
  [ "$n" -gt 0 ] || echo "no extra folders: the team works only in the folder you start it in. add one: ai team access add <folder>"
}
# expand ~ and make the folder absolute and real
team_abs_dir() {
  local p=$1
  # shellcheck disable=SC2088 # a typed "~" is matched on purpose, then replaced by $HOME
  case $p in "~") p=$HOME ;; "~/"*) p=$HOME/${p#\~/} ;; esac
  (cd -P -- "$p" 2>/dev/null && pwd -P)
}
team_access_add() {
  local d home
  d=$(team_abs_dir "$1") || { warn "no folder $1"; return 1; }
  home=$(cd -P -- "$HOME" && pwd -P)
  case $d in
    / | "$home") warn "$d would let the team change almost everything on this computer. pick a smaller folder"; return 1 ;;
  esac
  one_line "$d" || { warn "that folder name has a tab or a line break"; return 1; }
  if [ -r "$AI_TEAM_ACCESS" ] && grep -qxF -- "$d" "$AI_TEAM_ACCESS"; then
    echo "already allowed: $d"
    return 0
  fi
  mkdir -p "$AI_CONFIG_DIR" && echo "$d" >>"$AI_TEAM_ACCESS" || return 1
  echo "allowed: $d  (every team member may read and edit it)"
}
team_access_rm() {
  local d tmp
  d=$(team_abs_dir "$1") || d=$1
  [ -r "$AI_TEAM_ACCESS" ] && grep -qxF -- "$d" "$AI_TEAM_ACCESS" || die "$1 is not in the list. see: ai team access"
  tmp=$(mktemp "$AI_TEAM_ACCESS.XXXXXX") || return 1
  grep -vxF -- "$d" "$AI_TEAM_ACCESS" >"$tmp"
  mv "$tmp" "$AI_TEAM_ACCESS" && echo "removed: $d"
}

# ---- ai do ---------------------------------------------------------------------------

ai_do() {
  local task=$*
  if [ ! -s "$AI_TEAM" ]; then
    echo "you have no team yet. let's set one up first."
    TEAM_SETUP_NO_START=1 team_setup || return 1
    [ -s "$AI_TEAM" ] || die "no team was set up"
  fi
  [ -n "$task" ] || task=$(setup_ask "What should the team do?")
  [ -n "$task" ] || die "usage: ai do \"<what the team should do>\""
  TEAM_TASK=$task team_start
}

# ---- ai team setup -------------------------------------------------------------------

# ask <question> [default]: one answer; Enter takes the default
setup_ask() {
  local a
  printf '%s ' "$1" >&2
  [ -n "${2:-}" ] && printf '[%s] ' "$2" >&2
  IFS= read -r a || a=
  echo "${a:-${2:-}}"
}
# setup_yes <question>: yes unless the answer is n
setup_yes() {
  case $(setup_ask "$1 [Y/n]") in n | N | no | NO) return 1 ;; esac
  return 0
}
# the agents and accounts that can join, one per line: name<TAB>what it is
team_candidates() {
  local n a
  acct_list | while IFS= read -r n; do printf '%s\tClaude (account %s)\n' "$n" "$n"; done
  has codex && cdx_list | while IFS= read -r n; do printf 'codex:%s\tCodex (account %s)\n' "$n" "$n"; done
  prov_names | while IFS= read -r n; do
    a=$(prov_agent "$n")
    case $a in claude | codex) continue ;; esac
    team_default_cmd "$n" >/dev/null 2>&1 && printf '%s\t%s\n' "$n" "$(prov_get "$n" 3)"
  done
}
# setup_menu <list>: show name<TAB>what lines numbered
setup_menu() {
  local i=0 n w
  while IFS="$TAB" read -r n w; do
    [ -n "$n" ] || continue
    i=$((i + 1))
    printf '  %2d) %-16s %s\n' "$i" "$n" "$(dim "$w")" >&2
  done <<LIST
$1
LIST
}
# pick <list> <answer>: the names the numbers in the answer stand for (one per line)
setup_pick() {
  local k
  for k in $(printf '%s' "$2" | tr ',' ' '); do
    case $k in '' | *[!0-9]*) continue ;; esac
    printf '%s\n' "$1" | sed -n "${k}p" | cut -f1
  done | awk 'NF && !seen[$0]++'
}
# setup_role <member>: what it is good at, from the list or in your own words
setup_role() {
  local a r
  printf '  what is %s good at?\n' "$1" >&2
  printf '%s\n' "$TEAM_ROLES" | awk '{ printf "    %d) %s\n", NR, $0 }' >&2
  a=$(setup_ask "    a number, or your own words:" 1)
  case $a in
    *[!0-9]*) r=$a ;;
    *) r=$(printf '%s\n' "$TEAM_ROLES" | sed -n "${a}p") ;;
  esac
  echo "${r:-general coding}"
}
# without: the list without the given names
setup_without() {
  local list=$1
  shift
  printf '%s\n' "$list" | awk -F'\t' -v skip=" $* " 'NF && index(skip, " " $1 " ") == 0'
}

team_setup() {
  local all leads lead others chosen m role sub picked d task mine
  echo "Let's set up your AI team. Answer a few questions; Enter takes the answer in [brackets]."
  echo
  if [ -s "$AI_TEAM" ]; then
    team_show
    if ! setup_yes "Keep this team and add to it? (n starts a new one; the old one is kept as a .bak)"; then
      mv "$AI_TEAM" "$AI_TEAM.bak"
      if [ -d "$AI_TEAMS" ]; then rm -rf "$AI_TEAMS.bak" && mv "$AI_TEAMS" "$AI_TEAMS.bak"; fi
    fi
    echo
  fi
  all=$(team_candidates)

  # 1. the lead
  leads=$(printf '%s\n' "$all" | awk -F'\t' '$2 ~ /^(Claude|Codex) /')
  echo "1) Who leads the team? You talk to the lead; it hands work to the others."
  setup_menu "$leads"
  lead=$(setup_pick "$leads" "$(setup_ask "  number:" "$(printf '%s\n' "$leads" | cut -f1 | grep -nx "$(team_lead)" | cut -d: -f1)")" | head -n 1)
  [ -n "$lead" ] || lead=$(team_lead)
  team_set_lead "$lead" >/dev/null && echo "  lead: $lead"
  echo

  # 2. members
  others=$(setup_without "$all" "$lead")
  if [ -z "$others" ]; then
    echo "There is no other account or agent to join the team yet. Add one first, e.g.: cla add work, ai codex add work, or install gemini and run ai scan"
    return 1
  fi
  echo "2) Who works with $lead? Give the numbers, e.g. 1 3"
  setup_menu "$others"
  chosen=$(setup_pick "$others" "$(setup_ask "  numbers:")")
  for m in $chosen; do
    role=$(setup_role "$m")
    team_add '' "$m" "$role" | sed 's/^/  /'
  done
  [ -s "$AI_TEAM" ] || { echo "  no members picked, so there is no team yet."; return 1; }
  echo

  # 3. teams of their own
  echo "3) Should a member lead a small team of its own? (most teams don't need this)"
  while :; do
    mine=$(printf '%s\n' "$all" | awk -F'\t' 'NR == FNR { m[$1]; next } $1 in m' <(cut -f1 "$AI_TEAM") -)
    setup_menu "$mine"
    sub=$(setup_pick "$mine" "$(setup_ask "  number (Enter: no):")" | head -n 1)
    [ -n "$sub" ] || break
    others=$(setup_without "$all" "$sub" "$lead")
    echo "  who works for $sub? numbers, e.g. 2 4"
    setup_menu "$others"
    picked=$(setup_pick "$others" "$(setup_ask "  numbers:")")
    for m in $picked; do
      role=$(setup_role "$m")
      team_add "$sub" "$m" "$role" | sed 's/^/  /'
    done
    echo "  another one?"
  done
  echo

  # 4. extra folders
  echo "4) Folders outside the one you work in that the team may read and edit (e.g. ~/Documents/specs)."
  team_access_show | sed 's/^/  /'
  while :; do
    d=$(setup_ask "  folder (Enter: done):")
    [ -n "$d" ] || break
    team_access_add "$d" | sed 's/^/  /'
  done
  echo

  echo "Your team:"
  team_show
  echo
  echo "From now on, run this in the folder you want to work in:"
  echo "  ai do \"<what you want done>\""
  echo "Change the team any time with: ai team setup"
  [ -z "${TEAM_SETUP_NO_START:-}" ] || return 0
  echo
  task=$(setup_ask "What should the team do now? (Enter: nothing yet)")
  [ -z "$task" ] || TEAM_TASK=$task team_start
}
