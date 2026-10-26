# shellcheck shell=bash
# Failover between your Claude accounts, and on to Codex if you add it. OFF until you run
# `ai failover on`. Needs jq.
#
# How it works: when a session stops on a usage limit, exit Claude (/exit or ctrl-c twice).
# ai looks at the session's transcript; if its last reply is a usage-limit error, it marks
# that account as limited, copies the session to the next free account in your order and
# resumes it there with `claude --resume <id>`.
#
# A Codex account (codex:<name>) is only in the order when you put it there. Codex can't
# open a Claude session, so it gets the conversation so far as its first message: that
# sends the conversation to another provider (OpenAI), so it is asked every time (default
# no). Codex can't report its own limit, so the chain ends at Codex.
# Uses only documented behaviour (CLAUDE_CONFIG_DIR, transcripts, --resume, CODEX_HOME),
# no plugins or hooks.

AI_FO_FLAG=$AI_CONFIG_DIR/failover
AI_FO_ORDER=$AI_CONFIG_DIR/failover-order
AI_FO_COOLDOWN=${AI_FO_COOLDOWN:-18000}
AI_FO_PROMPT=${AI_FO_PROMPT:-"The previous account hit its usage limit and this session moved to another account. Continue exactly where you left off."}
AI_FO_CODEX_PROMPT=${AI_FO_CODEX_PROMPT:-"You are taking over a coding task from Claude Code, which stopped at its usage limit. Below is the conversation so far (oldest first; a long one is cut at the start). Work in this folder and continue exactly where it left off."}
# the most of the conversation handed to Codex, in bytes (the end is kept)
AI_FO_HANDOFF_MAX=${AI_FO_HANDOFF_MAX:-60000}

fo_on() { [ -e "$AI_FO_FLAG" ] && has jq; }
fo_mark() { echo "$AI_STATE_DIR/limited/$1"; }
# a failover member: a Claude account name, or codex:<Codex account>
fo_member_ok() {
  case $1 in
    codex:*) cdx_exists "${1#codex:}" ;;
    *) acct_exists "$1" ;;
  esac
}

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
    *) die "usage: ai failover [on | off | status | order <member>... | clear [member]]   (member: a Claude account, or codex:<name>)" ;;
  esac
}

# members in failover order: the saved order first, then any other Claude accounts (main
# first). Codex accounts are only in it when you put them in the saved order.
fo_order() {
  local a seen=" "
  if [ -r "$AI_FO_ORDER" ]; then
    while IFS= read -r a; do
      fo_member_ok "$a" || continue
      case $seen in *" $a "*) continue ;; esac
      seen="$seen$a "
      echo "$a"
    done <"$AI_FO_ORDER"
  fi
  for a in $(acct_list); do
    case $seen in *" $a "*) ;; *) echo "$a" ;; esac
  done
}

# seconds until a limited account is tried again; fails when it is free.
# The mark holds the reset time (epoch) when it was known; else AI_FO_COOLDOWN from its age.
fo_limited() {
  local f t left
  f=$(fo_mark "$1")
  [ -f "$f" ] || return 1
  t=$(head -n 1 "$f" 2>/dev/null)
  case $t in
    '' | *[!0-9]*)
      t=$(date -r "$f" +%s 2>/dev/null) || return 1
      t=$((t + AI_FO_COOLDOWN))
      ;;
  esac
  left=$((t - $(date +%s)))
  [ "$left" -gt 0 ] && echo "$left"
}

# fo_reset_at <account> <error text>: when the limit resets (epoch), if known:
# the time in the error ("...usage limit reached|<epoch>"), else the latest reset of a
# window at 100% in the saved plan usage (usage/usage.json, see usage.sh).
# Only a time in the next 8 days counts.
fo_reset_at() {
  local now f t
  now=$(date +%s)
  f=$(acct_dir "$1")/usage/usage.json
  for t in "$(printf '%s' "$2" | sed -n 's/.*|\([0-9]\{10\}\).*/\1/p' | head -n 1)" \
    "$([ -r "$f" ] && jq -r '[.rate_limits[]? | select((.used_percentage // 0) >= 100) | .resets_at // empty | floor] | max // empty' "$f" 2>/dev/null)"; do
    case $t in '' | *[!0-9]*) continue ;; esac
    if [ "$t" -gt "$now" ] && [ "$t" -lt $((now + 691200)) ]; then
      echo "$t"
      return 0
    fi
  done
  return 1
}

fo_show() {
  local a i=0 left
  if fo_on; then echo "failover: on   (top is tried first)"; else echo "failover: off  (turn on: ai failover on)"; fi
  for a in $(fo_order); do
    i=$((i + 1))
    if left=$(fo_limited "$a"); then
      printf '  %2d  %-12s \033[33mlimited · %dh%02dm left\033[0m\n' "$i" "$a" $((left / 3600)) $((left % 3600 / 60))
    else
      case $a in
        codex:*) printf '  %2d  %-12s %s\n' "$i" "$a" "$(dim 'Codex: gets the conversation so far, the chain ends here')" ;;
        *) printf '  %2d  %s\n' "$i" "$a" ;;
      esac
    fi
  done
}

fo_set_order() {
  local a tmp
  [ $# -gt 0 ] || die "usage: ai failover order <member>...   (Claude accounts from: cla ls; Codex as codex:<name> from: ai codex ls)"
  for a in "$@"; do
    fo_member_ok "$a" || die "no account '$a'. see: cla ls, or ai codex ls (written codex:<name>)"
  done
  mkdir -p "$AI_CONFIG_DIR" || return 1
  tmp=$(mktemp "$AI_FO_ORDER.XXXXXX") || return 1
  { printf '%s\n' "$@"; fo_order; } | awk '!seen[$0]++' >"$tmp" && mv "$tmp" "$AI_FO_ORDER"
  fo_show
}

fo_clear() {
  if [ -n "$1" ]; then
    fo_member_ok "$1" || die "no account '$1'. see: ai failover status"
    rm -f "$(fo_mark "$1")"
    echo "cleared the limit of $1"
  else
    rm -f "$AI_STATE_DIR/limited/"* 2>/dev/null
    echo "cleared every limit"
  fi
}

# after `cla mv` / `ai codex mv`: keep the member's place in the order and its limit
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

# the "/projects/<folder>" prefixes Claude Code keeps this directory's sessions under:
# the path with every character other than a letter or digit turned into "-"; a name
# longer than 200 is cut there and gets "-<hash>". Real and logical path both count.
fo_project_keys() {
  local p
  for p in "$(pwd -P)" "$PWD"; do
    p=$(printf '%s' "$p" | sed 's/[^A-Za-z0-9]/-/g')
    if [ "${#p}" -le 200 ]; then echo "/projects/$p/"; else echo "/projects/$(printf '%.200s' "$p")-"; fi
  done | sort -u
}

# newest session transcript an account wrote in this directory since <marker file>
# (projects/<folder>/<session>.jsonl; subagent files deeper down are ignored).
# Only this directory's folder: another window on the same account is never picked up.
fo_transcript() {
  local f k keys=
  for k in $(fo_project_keys); do keys="$keys -e $k"; done
  # shellcheck disable=SC2086 # $keys is "-e <key>..." and the keys have no spaces
  find "$(acct_dir "$1")/projects" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' -newer "$2" 2>/dev/null |
    grep -F $keys |
    while IFS= read -r f; do printf '%s\t%s\n' "$(date -r "$f" +%s)" "$f"; done |
    sort -n | tail -n 1 | cut -f2-
}

# the text of the session's last reply, when that reply is an API error
fo_error_text() {
  tail -n 50 "$1" | jq -Rc 'fromjson? | select(.type == "assistant")' 2>/dev/null | tail -n 1 |
    jq -r 'select(.isApiErrorMessage == true) | .message.content
      | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end' 2>/dev/null
}

# is <error text> about a plan limit? ("Claude AI usage limit reached", "5-hour limit
# reached", "You've hit your limit"); a short rate limit (429) or a context limit is not.
fo_hit_limit() {
  printf '%s' "$1" | grep -Eqi 'usage limit|hit your limit|(hour|weekly|session|opus|sonnet) limit reached'
}

# fo_keep_args [claude args]: the args a moved session starts with, in FO_ARGS. Drops what
# picks or starts a session (--resume/-r [id], --continue/-c, --session-id <id>,
# --fork-session, --print/-p) and a prompt (it was already sent); keeps the other options.
# A value is kept after the options below, or written as --option=value.
fo_keep_args() {
  FO_ARGS=()
  while [ $# -gt 0 ]; do
    case $1 in
      -r | --resume) case ${2:-} in -* | '') ;; *) shift ;; esac ;;
      --session-id) shift ;;
      -c | --continue | --fork-session | -p | --print | --resume=* | --session-id=*) ;;
      --model | --fallback-model | --permission-mode | --settings | --setting-sources | \
        --agent | --agents | --add-dir | --mcp-config | --allowedTools | --allowed-tools | \
        --disallowedTools | --disallowed-tools | --tools | --plugin-dir | --betas | \
        --append-system-prompt | --system-prompt | --output-format | --input-format)
        FO_ARGS[${#FO_ARGS[@]}]=$1
        if [ $# -gt 1 ]; then
          shift
          FO_ARGS[${#FO_ARGS[@]}]=$1
        fi
        ;;
      -*) FO_ARGS[${#FO_ARGS[@]}]=$1 ;;
    esac
    shift
  done
}

# the conversation in a transcript as text for another agent: what you and Claude wrote
# (no tool calls or results, no API errors), oldest first, cut to its last
# AI_FO_HANDOFF_MAX bytes at a line start
fo_handoff() {
  local h
  h=$(jq -Rr 'fromjson? | select((.type == "user" or .type == "assistant")
      and .isApiErrorMessage != true and .isMeta != true)
    | (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end) as $t
    | select($t != "") | "### \(.type)\n\($t)\n"' "$1" 2>/dev/null) || return 1
  if [ "$(printf '%s' "$h" | wc -c)" -gt "$AI_FO_HANDOFF_MAX" ]; then
    printf '%s' "$h" | tail -c "$AI_FO_HANDOFF_MAX" | sed 1d
  else
    printf '%s\n' "$h"
  fi
}

# fo_to_codex <codex account> <transcript>: start Codex in this folder with the conversation
# so far as its first message
fo_to_codex() {
  local h
  h=$(fo_handoff "$2") && [ -n "$h" ] || {
    warn "could not read the session to hand it to Codex"
    return 1
  }
  cdx_env "$1" launch "$(codex_cmd)" "$AI_FO_CODEX_PROMPT

$h"
}

# fo_run <account> [claude args]: run, and move on to the next account at each limit
fo_run() {
  local a=$1 tried marker t msg sid dest rc ans next
  local -a FO_ARGS
  shift
  tried=" $a "
  mkdir -p "$AI_STATE_DIR/limited" || return 1
  while :; do
    marker=$(mktemp "$AI_STATE_DIR/run.XXXXXX") || return 1
    acct_env "$a" launch "$(claude_cmd)" "$@"
    rc=$?
    t=$(fo_transcript "$a" "$marker")
    rm -f "$marker"
    [ -n "$t" ] || return "$rc"
    msg=$(fo_error_text "$t")
    fo_hit_limit "$msg" || return "$rc"

    # the mark holds the reset time when known; empty means AI_FO_COOLDOWN from now
    fo_reset_at "$a" "$msg" >"$(fo_mark "$a")"
    if ! next=$(fo_next "$tried"); then
      warn "$a hit its usage limit and no other account is free right now (see: ai failover status)"
      return 1
    fi
    # default No: moving a conversation to another account (e.g. work -> personal) is a real
    # choice, and handing it to Codex sends it to another provider
    case $next in
      codex:*) printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Hand this session to \033[1mCodex (%s)\033[0m?\nThe conversation so far is sent to Codex (OpenAI) as its first message. [y/N] ' "$a" "${next#codex:}" >&2 ;;
      *) printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Continue this session on \033[1m%s\033[0m? [y/N] ' "$a" "$next" >&2 ;;
    esac
    ans=
    read -r ans
    case $ans in y | Y | yes | YES) ;; *) return 1 ;; esac
    case $next in codex:*) fo_to_codex "${next#codex:}" "$t"; return ;; esac

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
    fo_keep_args "$@"
    set -- ${FO_ARGS[@]+"${FO_ARGS[@]}"} --resume "$sid" "$AI_FO_PROMPT"
    a=$next
    tried="$tried$a "
  done
}
