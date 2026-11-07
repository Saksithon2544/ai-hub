# shellcheck shell=bash
# Failover between your Claude accounts, and on to Codex if you add it. OFF until you run
# `ai failover on`. Needs jq.
#
# How it works: when a session stops on a usage limit, exit Claude (/exit or ctrl-c twice).
# ai looks at the session's transcript; if its last reply is a usage-limit error, it marks
# that account as limited, copies the session to the next free account in your order and
# resumes it there with `claude --resume <id>`.
#
# A Codex account (codex:<name>) or another agent from `ai ls` (e.g. agy) is only in the order
# when you put it there. It can't open a Claude session, so it gets the conversation so far as
# its first message: that sends the conversation to another provider, so it is asked every
# time (default no). When Codex stops, its session file says whether it hit its limit, so the
# chain goes on after it; another agent can't say that, so the chain ends at it.
# Uses only documented behaviour (CLAUDE_CONFIG_DIR, transcripts, --resume, CODEX_HOME),
# no plugins or hooks.

AI_FO_FLAG=$AI_CONFIG_DIR/failover
AI_FO_ORDER=$AI_CONFIG_DIR/failover-order
AI_FO_COOLDOWN=${AI_FO_COOLDOWN:-18000}
AI_FO_PROMPT=${AI_FO_PROMPT:-"The previous account hit its usage limit and this session moved to another account. Continue exactly where you left off."}
AI_FO_CODEX_PROMPT=${AI_FO_CODEX_PROMPT:-"You are taking over a coding task from another AI coding agent, which stopped at its usage limit. Below is the conversation so far (oldest first; a long one is cut at the start). Work in this folder and continue exactly where it left off."}
# the most of the conversation handed to Codex or another agent, in bytes (the end is kept)
AI_FO_HANDOFF_MAX=${AI_FO_HANDOFF_MAX:-60000}

fo_on() { [ -e "$AI_FO_FLAG" ] && has jq; }
fo_mark() { echo "$AI_STATE_DIR/limited/$1"; }
# a failover member: a Claude account name, codex:<Codex account>, or an agent from `ai ls`
fo_member_ok() {
  case $1 in
    codex:*) cdx_exists "${1#codex:}" ;;
    *) acct_exists "$1" || fo_is_agent "$1" ;;
  esac
}
# an agent from `ai ls` that can take a session over: one ai knows how to start with a first
# message and keep open (agy, gemini, qwen: -i). Claude and Codex are named by account here;
# another CLI might read the conversation as a folder or a file name, so it can't be in the order.
fo_is_agent() {
  case $1 in codex:*) return 1 ;; esac
  acct_exists "$1" && return 1
  prov_has "$1" || return 1
  case $(prov_agent "$1") in agy | gemini | qwen) return 0 ;; esac
  return 1
}
# a member that is not a Claude account: it gets the conversation as text
fo_other() {
  case $1 in codex:*) return 0 ;; esac
  fo_is_agent "$1"
}
fo_provider() {
  case $1 in
    codex:*) echo "Codex, OpenAI" ;;
    *) prov_get "$1" 3 ;;
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
    *) die "usage: ai failover [on | off | status | order <member>... | clear [member]]   (member: a Claude account, codex:<name>, or an agent from ai ls)" ;;
  esac
}

# members in failover order: the saved order first, then any other Claude accounts (main
# first). Codex accounts and other agents are only in it when you put them in the saved order.
fo_order() {
  local a seen=" " saved='' rest=''
  if [ -r "$AI_FO_ORDER" ]; then
    while IFS= read -r a; do
      fo_member_ok "$a" || continue
      case $seen in *" $a "*) continue ;; esac
      seen="$seen$a "
      saved="$saved $a"
    done <"$AI_FO_ORDER"
  fi
  for a in $(acct_list); do
    case $seen in *" $a "*) ;; *) rest="$rest $a" ;; esac
  done
  # the Claude accounts you did not name go before the first Codex account or agent, so they
  # are all tried before the conversation leaves your Claude accounts
  for a in $saved; do
    if [ -n "$rest" ] && fo_other "$a"; then
      printf '%s\n' $rest
      rest=
    fi
    echo "$a"
  done
  [ -z "$rest" ] || printf '%s\n' $rest
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
        codex:*) printf '  %2d  %-12s %s\n' "$i" "$a" "$(dim 'Codex: gets the conversation so far')" ;;
        *) if fo_is_agent "$a"; then
          printf '  %2d  %-12s %s\n' "$i" "$a" "$(dim "$(fo_provider "$a"): gets the conversation so far, the chain ends here")"
        else printf '  %2d  %s\n' "$i" "$a"; fi ;;
      esac
    fi
  done
}

fo_set_order() {
  local a tmp
  [ $# -gt 0 ] || die "usage: ai failover order <member>...   (Claude accounts from: cla ls; Codex as codex:<name> from: ai codex ls; other agents from: ai ls)"
  for a in "$@"; do
    fo_member_ok "$a" || die "'$a' can't be in the order: a Claude account (cla ls), codex:<name> (ai codex ls), or agy, gemini or qwen from ai ls"
  done
  mkdir -p "$AI_CONFIG_DIR" || return 1
  tmp=$(mktemp "$AI_FO_ORDER.XXXXXX") || return 1
  # only what you named: other Claude accounts, also ones added later, are placed by fo_order
  printf '%s\n' "$@" | awk '!seen[$0]++' >"$tmp" && mv "$tmp" "$AI_FO_ORDER"
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

# after `cla rm` / `ai codex rm` / `ai rm`: a member that no longer resolves leaves the order,
# and its limit goes. After `cla rm` (account) it leaves even when an agent has the same name:
# the order meant the account, and an agent would send the conversation to another provider.
# Fails when it was not in the order.
fo_forget() {
  local tmp
  if [ "${2:-}" = account ]; then acct_exists "$1" && return 1; else fo_member_ok "$1" && return 1; fi
  rm -f "$(fo_mark "$1")"
  grep -qxF -- "$1" "$AI_FO_ORDER" 2>/dev/null && tmp=$(mktemp "$AI_FO_ORDER.XXXXXX") || return 1
  awk -v a="$1" '$0 != a' "$AI_FO_ORDER" >"$tmp" && mv "$tmp" "$AI_FO_ORDER"
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
# Only this directory's folder: another window on the same account is never picked up, and
# neither is a headless run (a team delegation, `claude -p`: entrypoint "sdk-cli").
fo_transcript() {
  local f k keys=
  for k in $(fo_project_keys); do keys="$keys -e $k"; done
  # shellcheck disable=SC2086 # $keys is "-e <key>..." and the keys have no spaces
  find "$(acct_dir "$1")/projects" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' -newer "$2" 2>/dev/null |
    grep -F $keys |
    while IFS= read -r f; do
      [ "$(head -n 20 "$f" | jq -Rr 'fromjson? | .entrypoint // empty' 2>/dev/null | head -n 1)" = sdk-cli ] && continue
      printf '%s\t%s\n' "$(date -r "$f" +%s)" "$f"
    done |
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
  fo_cut "$h"
}
# fo_cut <text>: cut to its last AI_FO_HANDOFF_MAX bytes, at a line start
fo_cut() {
  local c
  if [ "$(printf '%s' "$1" | wc -c)" -gt "$AI_FO_HANDOFF_MAX" ]; then
    c=$(printf '%s' "$1" | tail -c "$AI_FO_HANDOFF_MAX" | sed 1d)
    # no line start in it (one huge line): keep the cut as it is
    [ -n "$c" ] || c=$(printf '%s' "$1" | tail -c "$AI_FO_HANDOFF_MAX")
    printf '%s\n' "$c"
  else
    printf '%s\n' "$1"
  fi
}

# fo_takeover <conversation>: the first message of a member that takes over as text
fo_takeover() {
  local p="$AI_FO_CODEX_PROMPT"
  [ -n "${AI_TEAM_LEADING:-}" ] && p="$p You lead a team of AI agents here: run \`ai team brief\` to see it and how to hand work to it."
  printf '%s\n\n%s' "$p" "$1"
}
# fo_start_other <member> <conversation>: start Codex or another agent in this folder with
# the conversation so far as its first message
fo_start_other() {
  local p
  p=$(fo_takeover "$2")
  case $1 in
    codex:*) cdx_env "${1#codex:}" launch "$(codex_cmd)" "$p" ;;
    *) launch "$(prov_get "$1" 2)" -i "$p" ;; # fo_is_agent: they all keep a first prompt open with -i
  esac
}

# fo_ask <member that stopped> <next> [fresh]: ask before moving on (default no). fresh: the
# next one is a Claude account that starts a new session with the conversation as text
fo_ask() {
  local ans
  if fo_other "$2"; then
    printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Hand this session to \033[1m%s\033[0m (%s)?\nThe conversation so far is sent to it as its first message. [y/N] ' "$1" "$2" "$(fo_provider "$2")" >&2
  elif [ -n "${3:-}" ]; then
    printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Start \033[1m%s\033[0m with the conversation so far as its first message? [y/N] ' "$1" "$2" >&2
  else
    printf '\n\033[38;5;173m%s hit its usage limit.\033[0m Continue this session on \033[1m%s\033[0m? [y/N] ' "$1" "$2" >&2
  fi
  read -r ans
  case $ans in y | Y | yes | YES) return 0 ;; esac
  return 1
}

# Codex keeps each session in $CODEX_HOME/sessions/.../rollout-*.jsonl: the folder it ran in
# (session_meta), the messages, and its plan usage after each turn (token_count).
# fo_codex_session <codex account> <marker file>: its newest session in this folder since then
fo_codex_session() {
  local f d
  find "$(cdx_dir "$1")/sessions" -type f -name 'rollout-*.jsonl' -newer "$2" 2>/dev/null |
    while IFS= read -r f; do
      # the folder it ran in; a headless run (`codex exec`, e.g. a team delegation) is skipped
      d=$(head -n 5 "$f" | jq -Rr 'fromjson? | select(.type == "session_meta") | .payload
        | select(.source != "exec" and .originator != "codex_exec") | .cwd // empty' 2>/dev/null | head -n 1)
      [ "$d" = "$(pwd -P)" ] || [ "$d" = "$PWD" ] || continue
      printf '%s\t%s\n' "$(date -r "$f" +%s)" "$f"
    done | sort -n | tail -n 1 | cut -f2-
}
# its last plan usage, as JSON
fo_codex_limits() {
  jq -Rc 'fromjson? | select(.payload.type? == "token_count") | .payload.rate_limits // empty' "$1" 2>/dev/null | tail -n 1
}
# did the session stop at a plan limit: a window at 100%, Codex says one was reached, or its
# last error is about the limit
fo_codex_limited() {
  fo_codex_limits "$1" | jq -e '.rate_limit_reached_type != null or ([.primary, .secondary | .used_percent? // 0] | max) >= 100' >/dev/null 2>&1 && return 0
  fo_hit_limit "$(jq -Rr 'fromjson? | select(.payload.type? == "error") | .payload.message // empty' "$1" 2>/dev/null | tail -n 1)"
}
# when it resets (epoch), if known: the latest reset of a window at 100%
fo_codex_reset() {
  local t
  t=$(fo_codex_limits "$1" | jq -r '[.primary, .secondary | select(. != null and (.used_percent // 0) >= 100) | .resets_at // empty | floor] | max // empty' 2>/dev/null)
  case $t in '' | *[!0-9]*) return 1 ;; esac
  [ "$t" -gt "$(date +%s)" ] && echo "$t"
}
# the conversation in a Codex session as text, without the hand-over (it is already in the
# text) and without what Codex adds itself (<environment_context>, AGENTS.md and the like)
fo_codex_convo() {
  jq -Rrs --arg h "$(printf '%s' "$AI_FO_CODEX_PROMPT" | cut -c1-60)" '[split("\n")[] | fromjson?
    | select(.type == "response_item" and .payload.type == "message"
      and (.payload.role == "user" or .payload.role == "assistant"))
    | {r: .payload.role, t: ([.payload.content[]? | .text? // empty] | join("\n"))}
    | select(.t != "" and (.t | startswith($h) | not)
      and (.r == "assistant" or (.t | test("^(<(environment_context|user_instructions|permissions)|# AGENTS.md)") | not)))]
    | .[] | "### \(if .r == "assistant" then "codex" else "user" end)\n\(.t)\n"' "$1" 2>/dev/null
}

# fo_chain <member> <conversation>: hand the session to Codex or another agent; when Codex
# stops at its limit, on to the next member. FO_TRIED: the ones tried before (" a b "), and
# FO_CARRY: the Claude options of the session, for a Claude account after Codex.
fo_chain() {
  local m=$1 h=$2 tried="${FO_TRIED:- }$1 " marker s next rc
  FO_TRIED=
  while :; do
    marker=$(mktemp "$AI_STATE_DIR/run.XXXXXX") || return 1
    fo_start_other "$m" "$h"
    rc=$?
    s=
    case $m in codex:*) s=$(fo_codex_session "${m#codex:}" "$marker") ;; esac
    rm -f "$marker"
    # only Codex says when it stopped at its limit: after another agent the chain ends
    [ -n "$s" ] && fo_codex_limited "$s" || return "$rc"
    fo_codex_reset "$s" >"$(fo_mark "$m")"
    if ! next=$(fo_next "$tried"); then
      warn "$m hit its usage limit and no other account is free right now (see: ai failover status)"
      return 1
    fi
    fo_ask "$m" "$next" fresh || return 1
    h=$(fo_cut "$h
$(fo_codex_convo "$s")")
    if ! fo_other "$next"; then
      # a Claude account after Codex: a new session with the session's options (the team brief,
      # its tools, --model...), and the conversation as its first message
      FO_TRIED=$tried
      fo_run "$next" ${FO_CARRY[@]+"${FO_CARRY[@]}"} "$(fo_takeover "$h")"
      return
    fi
    m=$next
    tried="$tried$m "
  done
}

# fo_run <account> [claude args]: run, and move on to the next account at each limit
fo_run() {
  local a=$1 tried marker t msg sid dest rc next h
  local -a FO_ARGS
  shift
  # a global, not an env prefix: an env var would reach the agents this starts
  tried="${FO_TRIED:- }$a "
  FO_TRIED=
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
    # choice, and handing it to Codex or another agent sends it to another provider
    fo_ask "$a" "$next" || return 1
    if fo_other "$next"; then
      h=$(fo_handoff "$t") && [ -n "$h" ] || {
        warn "could not read the session to hand it over"
        return 1
      }
      fo_keep_args "$@"
      FO_CARRY=(${FO_ARGS[@]+"${FO_ARGS[@]}"})
      FO_TRIED=$tried
      fo_chain "$next" "$h"
      return
    fi

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
