# shellcheck shell=bash
# Failover between your Claude accounts. OFF until you run `ai failover on`. Needs jq.
#
# How it works: when a session stops on a usage limit, exit Claude (/exit or ctrl-c twice).
# ai looks at the session's transcript; if its last reply is a usage-limit error, it marks
# that account as limited, copies the session to the next free account in your order and
# resumes it there with `claude --resume <id>`.
#
# Only between your own Claude accounts: a conversation is never sent to another provider.
# Uses only documented Claude Code behaviour (CLAUDE_CONFIG_DIR, transcripts, --resume),
# no plugins or hooks.

AI_FO_FLAG=$AI_CONFIG_DIR/failover
AI_FO_ORDER=$AI_CONFIG_DIR/failover-order
AI_FO_COOLDOWN=${AI_FO_COOLDOWN:-18000}
AI_FO_PROMPT=${AI_FO_PROMPT:-"The previous account hit its usage limit and this session moved to another account. Continue exactly where you left off."}

fo_on() { [ -e "$AI_FO_FLAG" ] && has jq; }
fo_mark() { echo "$AI_STATE_DIR/limited/$1"; }

ai_failover() {
  case ${1:-status} in
    on)
      has jq || die "failover needs jq (brew install jq / apt install jq)"
      mkdir -p "$AI_CONFIG_DIR" && : >"$AI_FO_FLAG"
      fo_show
      ;;
    off) rm -f "$AI_FO_FLAG" && fo_show ;;
    status | ls) fo_show ;;
    order) shift; fo_set_order "$@" ;;
    clear) fo_clear "${2:-}" ;;
    *) die "usage: ai failover [on | off | status | order <account>... | clear [account]]" ;;
  esac
}

# accounts in failover order: the saved order first, then any others (main first)
fo_order() {
  local a seen=" "
  if [ -r "$AI_FO_ORDER" ]; then
    while IFS= read -r a; do
      acct_exists "$a" || continue
      case $seen in *" $a "*) continue ;; esac
      seen="$seen$a "
      echo "$a"
    done <"$AI_FO_ORDER"
  fi
  for a in $(acct_list); do
    case $seen in *" $a "*) ;; *) echo "$a" ;; esac
  done
}

# seconds until a limited account is tried again; fails when it is free
fo_limited() {
  local f t left
  f=$(fo_mark "$1")
  [ -f "$f" ] || return 1
  t=$(date -r "$f" +%s 2>/dev/null) || return 1
  left=$((t + AI_FO_COOLDOWN - $(date +%s)))
  [ "$left" -gt 0 ] && echo "$left"
}

fo_show() {
  local a i=0 left
  if fo_on; then echo "failover: on   (top is tried first)"; else echo "failover: off  (turn on: ai failover on)"; fi
  for a in $(fo_order); do
    i=$((i + 1))
    if left=$(fo_limited "$a"); then
      printf '  %2d  %-12s \033[33mlimited · %dh%02dm left\033[0m\n' "$i" "$a" $((left / 3600)) $((left % 3600 / 60))
    else
      printf '  %2d  %s\n' "$i" "$a"
    fi
  done
}

fo_set_order() {
  local a tmp
  [ $# -gt 0 ] || die "usage: ai failover order <account>...   (names from: cla ls)"
  for a in "$@"; do acct_exists "$a" || die "no account '$a'. see: cla ls"; done
  mkdir -p "$AI_CONFIG_DIR" || return 1
  tmp=$(mktemp "$AI_FO_ORDER.XXXXXX") || return 1
  { printf '%s\n' "$@"; fo_order; } | awk '!seen[$0]++' >"$tmp" && mv "$tmp" "$AI_FO_ORDER"
  fo_show
}

fo_clear() {
  if [ -n "$1" ]; then
    acct_exists "$1" || die "no account '$1'. see: cla ls"
    rm -f "$(fo_mark "$1")"
    echo "cleared the limit of $1"
  else
    rm -f "$AI_STATE_DIR/limited/"* 2>/dev/null
    echo "cleared every limit"
  fi
}

# after `cla mv`: keep the account's place in the order and its limit
fo_rename() {
  local tmp
  if [ -r "$AI_FO_ORDER" ] && tmp=$(mktemp "$AI_FO_ORDER.XXXXXX"); then
    awk -v a="$1" -v b="$2" '$0 == a { $0 = b } { print }' "$AI_FO_ORDER" >"$tmp" && mv "$tmp" "$AI_FO_ORDER"
  fi
  [ -f "$(fo_mark "$1")" ] && mv "$(fo_mark "$1")" "$(fo_mark "$2")"
  return 0
}

# next account to try: not tried in this run ($1 = " a b "), not cooling down
fo_next() {
  local a
  for a in $(fo_order); do
    case $1 in *" $a "*) continue ;; esac
    fo_limited "$a" >/dev/null && continue
    echo "$a"
    return 0
  done
  return 1
}

# newest session transcript an account wrote since <marker file>
# (projects/<folder>/<session>.jsonl; subagent files deeper down are ignored)
fo_transcript() {
  local f
  find "$(acct_dir "$1")/projects" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' -newer "$2" 2>/dev/null |
    while IFS= read -r f; do printf '%s\t%s\n' "$(date -r "$f" +%s)" "$f"; done |
    sort -n | tail -n 1 | cut -f2-
}

# did the session end on a usage-limit error? (its last reply is an API error about a limit)
fo_hit_limit() {
  tail -n 50 "$1" | jq -Rc 'fromjson? | select(.type == "assistant")' 2>/dev/null | tail -n 1 |
    jq -r 'select(.isApiErrorMessage == true) | .message.content
      | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end' 2>/dev/null |
    grep -qi 'limit'
}

# fo_run <account> [claude args]: run, and move on to the next account at each limit
fo_run() {
  local a=$1 tried marker t sid dest rc ans next
  shift
  tried=" $a "
  mkdir -p "$AI_STATE_DIR/limited" || return 1
  while :; do
    marker=$(mktemp "$AI_STATE_DIR/run.XXXXXX") || return 1
    acct_env "$a" launch "$(claude_cmd)" "$@"
    rc=$?
    t=$(fo_transcript "$a" "$marker")
    rm -f "$marker"
    if [ -z "$t" ] || ! fo_hit_limit "$t"; then return "$rc"; fi

    touch "$(fo_mark "$a")"
    if ! next=$(fo_next "$tried"); then
      warn "$a hit its usage limit and no other account is free right now (see: ai failover status)"
      return 1
    fi
    printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Continue this session on \033[1m%s\033[0m? [Y/n] ' "$a" "$next" >&2
    ans=
    read -r ans
    case $ans in n | N | no | NO) return 1 ;; esac

    # sessions live per config folder: copy it (and its subagent folder) to the next account
    dest=$(acct_dir "$next")/projects/$(basename "$(dirname "$t")")
    mkdir -p "$dest" || return 1
    if [ ! "$t" -ef "$dest/$(basename "$t")" ]; then
      cp -p "$t" "$dest/" || {
        warn "could not copy the session to $next"
        return 1
      }
      [ -d "${t%.jsonl}" ] && cp -Rp "${t%.jsonl}" "$dest/"
    fi
    sid=$(basename "$t" .jsonl)
    set -- --resume "$sid" "$AI_FO_PROMPT"
    a=$next
    tried="$tried$a "
  done
}
