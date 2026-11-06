# shellcheck shell=bash
# A team of agents: a lead you talk to, and members it hands work to. OFF until you add a
# member with `ai team add`.
#
# `ai team` starts the lead (a Claude account by default) with a brief appended to its
# system prompt: who the members are, what each is good at, and how to delegate. The lead
# does what it is best at itself and runs `ai delegate <member> "<task>"` for the rest:
# that runs the member headless in this folder (claude -p, codex exec, gemini -p, ...),
# prints its reply for the lead to read, and keeps the full log under $AI_TEAM_DIR/logs.
# Delegations run one at a time per folder, so two agents never edit the same files at once.
#
# Every member can lead a team of its own (`ai team add --of <member> ...`). When it gets a
# task it also gets a brief of its team, and its own `ai delegate` calls go to that team. A
# delegation knows the chain above it (AI_TEAM_CHAIN), so it never goes back up the chain,
# and it stops at AI_TEAM_MAX_DEPTH levels.
#
# A member is a Claude account (main, work), codex:<Codex account>, or an agent from `ai ls`.
# Delegating sends the task and the files in this folder to that member's provider, so a
# member is only in the team when you add it yourself (like Codex in failover).

AI_TEAM=$AI_CONFIG_DIR/team # member<TAB>what it is good at<TAB>headless command (empty = default)
AI_TEAM_LEAD=$AI_CONFIG_DIR/team-lead
AI_TEAMS=$AI_CONFIG_DIR/teams # the team of each member that leads one: teams/<member>, same format
AI_TEAM_DIR=$AI_STATE_DIR/team # logs/, journal, locks/
# how each agent runs headless, after its saved command (override by env, or per member)
AI_TEAM_CLAUDE_OPTS=${AI_TEAM_CLAUDE_OPTS:---permission-mode acceptEdits}
# A Claude member starts lean: only the tools it needs to code, no MCP servers, skills or
# commands. Measured on Claude Code 2.1: ~7.7k tokens before the task instead of ~24k with
# everything loaded. Empty = load everything, like a normal session.
AI_TEAM_CLAUDE_LEAN=${AI_TEAM_CLAUDE_LEAN---strict-mcp-config --disable-slash-commands --tools=Read,Edit,Write,Bash,Glob,Grep}
# Added to every delegated task, so a reply that goes back up stays short. Empty = none.
AI_TEAM_REPORT=${AI_TEAM_REPORT-When you are done, reply with a short report (at most 15 lines): whether it is done, the files you changed, how you checked it, and anything left open. Do not paste code or whole files: they are in the folder.}
AI_TEAM_HANDOFF=${AI_TEAM_HANDOFF:-1} # a member that stops at its usage limit hands its task to the next free member (0 = off)
AI_TEAM_HANDOFF_MAX=${AI_TEAM_HANDOFF_MAX:-4000} # the most of its reply passed on, in bytes (the end is kept)
AI_TEAM_CODEX_OPTS=${AI_TEAM_CODEX_OPTS:---sandbox workspace-write --skip-git-repo-check}
AI_TEAM_GEMINI_OPTS=${AI_TEAM_GEMINI_OPTS:---approval-mode auto_edit}
AI_TEAM_AGY_OPTS=${AI_TEAM_AGY_OPTS:---mode accept-edits --disable-slash-commands} # Antigravity CLI
AI_TEAM_WAIT=${AI_TEAM_WAIT:-3600} # the most a delegation waits for the folder, in seconds
AI_TEAM_MAX_DEPTH=${AI_TEAM_MAX_DEPTH:-3} # levels of delegation below the lead
AI_TEAM_WAIT_STEP=${AI_TEAM_WAIT_STEP:-540} # `ai team wait` returns after this long (an agent's shell call times out at 10m)
AI_TEAM_KEEP_DAYS=${AI_TEAM_KEEP_DAYS:-30} # finished delegation logs are deleted after this many days (0 = keep them)
# What a lead (and a member that leads a team) may run without asking. One --allowedTools per
# tool: failover keeps an option with one value, so a list after one --allowedTools would be cut.
TEAM_ALLOW=(--allowedTools "Bash(ai delegate:*)" --allowedTools "Bash(ai team wait:*)" --allowedTools "Bash(ai team log:*)")
# Set for a member while it works: AI_TEAM_AS (who it is, so `ai delegate` uses its team)
# and AI_TEAM_CHAIN (the members from the top down to it, space separated).

# a member: a Claude account, codex:<account>, or an agent from `ai ls` (an account first)
team_member_ok() {
  case $1 in
    codex:*) cdx_exists "${1#codex:}" ;;
    *) acct_exists "$1" || prov_has "$1" ;;
  esac
}
team_is_claude() {
  case $1 in codex:*) return 1 ;; esac
  acct_exists "$1"
}
# team_file [leader]: the members file of the lead's team (no leader) or of that member's team
team_file() { if [ -n "${1:-}" ]; then echo "$AI_TEAMS/$1"; else echo "$AI_TEAM"; fi; }
# team_has <member> [leader]
team_has() { [ -n "$(tsv_get "$(team_file "${2:-}")" "$1" 1)" ]; }
team_leads() { [ -s "$AI_TEAMS/$1" ]; } # does this member lead a team of its own
# the team the caller delegates to: its own when it is a member at work, else the lead's
team_mine() { team_file "${AI_TEAM_AS:-}"; }
# shellcheck disable=SC2086 # split the chain into words
team_depth() {
  set -- ${AI_TEAM_CHAIN:-}
  echo $#
}
team_lead() {
  local l
  l=$(head -n 1 "$AI_TEAM_LEAD" 2>/dev/null)
  if [ -n "$l" ] && team_member_ok "$l"; then echo "$l"; else echo main; fi
}

ai_team() {
  case ${1:-} in
    '') team_start ;;
    help | -h | --help) team_help ;;
    -*) team_start "$@" ;;
    ls | status) team_show ;;
    add | rm | brief)
      local sub=$1 of=''
      shift
      if [ "${1:-}" = --of ]; then
        of=${2:-}
        [ -n "$of" ] || die "usage: ai team $sub --of <member> ..."
        team_member_ok "$of" || die "no account or agent '$of'. see: cla ls, ai codex ls (written codex:<name>), ai ls"
        shift 2
      fi
      case $sub in
        add) team_add "$of" "$@" ;;
        rm) team_rm "$of" "$@" ;;
        brief) team_brief "$of" ;;
      esac
      ;;
    lead) shift; team_set_lead "$@" ;;
    log) team_log "${2:-}" ;;
    wait) shift; team_wait "$@" ;;
    setup) team_setup ;;
    discover) shift; team_discover "$@" ;;
    access) shift; team_access "$@" ;;
    *) die "usage: ai team [setup | discover | ls | add | rm | lead | access | log | wait | brief | help]   (no argument: start the lead)" ;;
  esac
}

team_help() {
  cat <<'EOF'
ai team setup                             set up the team by answering a few questions (the easy way)
ai team discover [member...]              the members say what they do best and the lead proposes who does
                                          what (roles and sub-teams); you say y before it changes anything
ai do "<task>"                            start the lead here with a task; it hands parts to the team itself
ai team                                   start the lead here with a brief of its team (extra args go to the lead)
ai team ls                                show the lead and the members
ai team add <member> "<good at>" [cmd]    add a member (or change it): a Claude account, codex:<name>, or an
                                          agent from `ai ls`; cmd = how to run it headless, when ai doesn't know
ai team rm <member>                       remove a member
ai team add --of <leader> <member> ...    give a member a team of its own (and rm --of, brief --of)
ai team lead <member>                     who leads (default: main). A Claude account, or codex:<name>
ai team access [add|rm <folder>]          folders outside this one that every member may read and edit
ai team log [n]                           the last n delegations (default 10)
ai team log --clean                       delete the logs of finished delegations and the journal now
ai team wait <log>...                     wait for background delegations and print their replies
ai team brief                             print the brief the lead gets (to paste into another setup)

ai delegate <member> "<task>"             run a member on a task in this folder and print its reply
ai delegate <member> - <<'EOF' ... EOF    the task from stdin
ai delegate -b <member> "<task>"          in the background; the log file ends with "# done (exit n)"

The lead does what it is best at and delegates the rest. A member with a team of its own does
the same with its part, up to AI_TEAM_MAX_DEPTH levels (default 3). Members edit files here
directly, one at a time per team. Delegating to codex:<name> or another agent sends the task and
this folder's files to that provider.
Logs are readable only by you, and kept AI_TEAM_KEEP_DAYS days (default 30, 0 = forever).
Headless options: AI_TEAM_CLAUDE_OPTS, AI_TEAM_CLAUDE_LEAN, AI_TEAM_CODEX_OPTS, AI_TEAM_AGY_OPTS,
AI_TEAM_GEMINI_OPTS. Tokens and hand-over: AI_TEAM_REPORT, AI_TEAM_HANDOFF, AI_TEAM_HANDOFF_MAX.
All the settings: README, "Settings".
EOF
}

# the provider a member's work goes to, for the note when it is added
team_provider() {
  case $1 in
    codex:*) echo "Codex (OpenAI)" ;;
    *)
      if acct_exists "$1"; then echo "Claude (account $1)"; else prov_get "$1" 3; fi
      ;;
  esac
}

team_add() {
  local of=$1 m=${2:-} role=${3:-} c=${4:-} was=added f whose=the
  f=$(team_file "$of")
  [ -n "$of" ] && whose="$of's"
  [ -n "$m" ] && [ -n "$role" ] || die "usage: ai team add [--of <leader>] <member> \"<what it is good at>\" [headless command]"
  team_member_ok "$m" || die "no account or agent '$m'. see: cla ls, ai codex ls (written codex:<name>), ai ls"
  [ "$m" != "$of" ] || die "$m can't be in its own team"
  one_line "$role" && one_line "$c" || die "the description and command must be one line without tabs"
  [ -n "$c" ] || team_default_cmd "$m" >/dev/null ||
    die "ai doesn't know how to run '$m' headless. give the command, it gets the task as its last argument:  ai team add $m \"$role\" \"<command>\""
  team_has "$m" "$of" && was=updated
  tsv_put "$f" "$m" "$role" "$c" || return 1
  echo "$was $m in $whose team: $role"
  team_is_claude "$m" || echo "note: a task delegated to $m, and the files it reads here, go to $(team_provider "$m")"
  if [ -n "$of" ]; then
    team_in_any "$of" || echo "note: $of is in no team yet, so nobody hands it work. add it: ai team add $of \"<what it is good at>\""
    case $of in
      codex:*)
        echo "note: Codex works in its workspace-write sandbox, which has no network and can't write ai's logs, so its \`ai delegate\` calls fail. to let it, run the team with:"
        printf '  AI_TEAM_CODEX_OPTS="--sandbox workspace-write --skip-git-repo-check -c sandbox_workspace_write.network_access=true -c sandbox_workspace_write.writable_roots=[\x27%s\x27]"\n' "$AI_STATE_DIR"
        ;;
      *) team_is_claude "$of" && [ -z "$(tsv_get "$(team_file "$(team_parent_of "$of")")" "$of" 3)" ] ||
        echo "note: $of gets its team's brief at the top of each task, and must be allowed to run \`ai delegate\` in its shell" ;;
    esac
  else
    [ -n "$(cat "$AI_TEAM_LEAD" 2>/dev/null)" ] || echo "the lead is $(team_lead). start the team here with: ai team"
  fi
}

team_rm() {
  local of=$1 m=${2:-} f whose=the
  f=$(team_file "$of")
  [ -n "$of" ] && whose="$of's"
  [ -n "$m" ] || die "usage: ai team rm [--of <leader>] <member>"
  team_has "$m" "$of" || die "'$m' is not in $whose team. see: ai team ls"
  tsv_put "$f" "$m" || return 1
  [ -n "$of" ] && [ ! -s "$f" ] && rm -f "$f"
  echo "removed $m from $whose team"
}

# is the member in the lead's team or in any member's team
team_in_any() {
  local f
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] && [ -n "$(tsv_get "$f" "$1" 1)" ] && return 0
  done
  return 1
}
# the leader of the first team the member is in ('' = the lead's team)
team_parent_of() {
  local f
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] && [ -n "$(tsv_get "$f" "$1" 1)" ] || continue
    [ "$f" = "$AI_TEAM" ] || echo "${f##*/}"
    return 0
  done
}

team_set_lead() {
  local m=${1:-}
  if [ -z "$m" ]; then
    echo "lead: $(team_lead)"
    return 0
  fi
  team_member_ok "$m" || die "no account '$m'. see: cla ls, or ai codex ls (written codex:<name>)"
  case $m in codex:*) ;; *) acct_exists "$m" || die "the lead must be a Claude account or codex:<name>" ;; esac
  mkdir -p "$AI_CONFIG_DIR" && echo "$m" >"$AI_TEAM_LEAD" && echo "lead: $m"
}

# after `cla mv` / `ai codex mv`: keep the member in the team and as the lead
team_rename() {
  local tmp f
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] && tmp=$(mktemp "$f.XXXXXX") || continue
    awk -F'	' -v OFS='	' -v a="$1" -v b="$2" '$1 == a { $1 = b } { print }' "$f" >"$tmp" && mv "$tmp" "$f"
  done
  [ -f "$AI_TEAMS/$1" ] && [ ! -e "$AI_TEAMS/$2" ] && mv "$AI_TEAMS/$1" "$AI_TEAMS/$2"
  [ "$(head -n 1 "$AI_TEAM_LEAD" 2>/dev/null)" = "$1" ] && echo "$2" >"$AI_TEAM_LEAD"
  return 0
}

# after `cla rm` / `ai codex rm` / `ai rm`: a name that no longer resolves (an account and an
# agent can share a name) leaves every team, its own team and the lead. After `cla rm`
# (account) it leaves even when an agent has the same name: the team meant the account, and
# the agent would send the work to another provider. Fails when it was in none.
team_forget() {
  local f hit=1
  if [ "${2:-}" = account ]; then acct_exists "$1" && return 1; else team_member_ok "$1" && return 1; fi
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] && [ -n "$(tsv_get "$f" "$1" 1)" ] || continue
    tsv_put "$f" "$1" && hit=0
    [ "$f" != "$AI_TEAM" ] && [ ! -s "$f" ] && rm -f "$f"
  done
  [ -f "$AI_TEAMS/$1" ] && rm -f "$AI_TEAMS/$1" && hit=0
  [ "$(head -n 1 "$AI_TEAM_LEAD" 2>/dev/null)" = "$1" ] && rm -f "$AI_TEAM_LEAD" && hit=0
  return "$hit"
}
# forget_member <name> [account]: team_forget and fo_forget, saying what was cleaned up
forget_member() {
  local what=
  team_forget "$1" "${2:-}" && what="the team"
  fo_forget "$1" "${2:-}" && what="${what:+$what and }the failover order"
  [ -z "$what" ] || echo "also removed $1 from $what"
}

team_show() {
  local f l
  echo "lead:    $(team_lead)   $(dim '(start the team here: ai team)')"
  if [ ! -s "$AI_TEAM" ]; then
    echo "members: none yet. add one: ai team add <member> \"<what it is good at>\""
    return 0
  fi
  echo "members:"
  TEAM_SHOWN=' '
  team_show_tree '' '  ' ''
  for f in "$AI_TEAMS"/*; do
    [ -s "$f" ] || continue
    l=${f##*/}
    case $TEAM_SHOWN in *" $l "*) continue ;; esac
    echo "team of $l $(dim '(not used: nobody above hands it work)'):"
    team_show_tree "$l" '  ' "$l"
  done
}
# team_show_tree <leader> <indent> <chain>: the members, and the members of their teams below them
team_show_tree() {
  local m r c left p=$2
  [ -n "$1" ] && p="$2└ "
  while IFS="$TAB" read -r m r c; do
    [ -n "$m" ] || continue
    if left=$(fo_limited "$m"); then
      printf '%s[1;36m%-14s[0m %-36s [33mlimited · %dh%02dm left[0m
' "$p" "$m" "$r" $((left / 3600)) $((left % 3600 / 60))
    elif team_member_ok "$m"; then
      printf '%s[1;36m%-14s[0m %-36s %s
' "$p" "$m" "$r" "$(dim "${c:-$(team_default_cmd "$m" 2>/dev/null)}")"
    else
      printf '%s[1;36m%-14s[0m %-36s [31mnot found (removed?)[0m
' "$p" "$m" "$r"
    fi
    team_leads "$m" || continue
    case " $3 " in *" $m "*)
      printf '%s  %s
' "$2" "$(dim "its team is shown above")"
      continue
      ;;
    esac
    TEAM_SHOWN="$TEAM_SHOWN$m "
    team_show_tree "$m" "$2  " "$3 $m"
  done <"$(team_file "$1")"
}

# cmd_insert <saved command> <words>: put words right after the CLI (after any VAR=value)
cmd_insert() {
  printf '%s\n' "$1" | INS=$2 awk '{
    for (i = 1; i <= NF; i++) if (!done && $i !~ /^[A-Za-z_][A-Za-z0-9_]*=/) { $i = $i " " ENVIRON["INS"]; done = 1 }
    print }'
}

# the headless command of a member: the one you gave, else by its CLI. The task goes last.
team_default_cmd() {
  local m=$1 c agent a
  case $m in
    codex:*)
      c=$(codex_cmd)
      agent=codex
      ;;
    *)
      if acct_exists "$m"; then
        c=$(claude_cmd)
        agent=claude
      else
        c=$(prov_get "$m" 2)
        agent=$(prov_agent "$m")
      fi
      ;;
  esac
  a=$(team_access_opts "$agent") # the extra folders of `ai team access`
  case $agent in
    claude) cmd_insert "$c" "${a:+$a }-p $AI_TEAM_CLAUDE_OPTS${AI_TEAM_CLAUDE_LEAN:+ $AI_TEAM_CLAUDE_LEAN}" ;;
    codex) cmd_insert "$c" "exec ${a:+$a }$AI_TEAM_CODEX_OPTS" ;;
    gemini | qwen) cmd_insert "$c" "${a:+$a }$AI_TEAM_GEMINI_OPTS -p" ;;
    agy) cmd_insert "$c" "${a:+$a }$AI_TEAM_AGY_OPTS -p" ;;
    opencode) cmd_insert "$c" "run" ;;
    *) return 1 ;;
  esac
}
team_cmd() { # <member> <members file>
  local c
  c=$(tsv_get "$2" "$1" 3)
  if [ -n "$c" ]; then echo "$c"; else team_default_cmd "$1"; fi
}

# team_run <member> <command> <args...>: run it with the member's account
team_run() {
  local m=$1
  shift
  case $m in
    codex:*) cdx_env "${m#codex:}" launch "$@" ;;
    *) if acct_exists "$m"; then acct_env "$m" launch "$@"; else launch "$@"; fi ;;
  esac
}

# team_brief [leader] [who gave it the task]: the brief the lead starts with, or the one a
# member that leads a team of its own gets with each task
team_brief() {
  local of=${1:-} from=${2:-the lead}
  if [ -z "$of" ]; then
    cat <<EOF
You are "$(team_lead)", the lead of a small team of AI coding agents working in this folder. Do yourself what you are best at and hand the rest to the member best suited for it with the \`ai delegate\` command. You stay responsible for the result: read what a member returns, check it (run the tests, read the diff) and fix or re-delegate when needed. Tell the user who did what.

Team members and what each is good at:
EOF
  else
    cat <<EOF
You are "$of", a member of a team of AI coding agents working in this folder, and you lead a team of your own. You were handed a task by "$from". Do yourself what you are best at and hand parts of it to the member of your team best suited for them with the \`ai delegate\` command. You stay responsible for your part: check what a member returns and fix or re-delegate when needed. Your final reply goes back to "$from" as a short report: what was done and by whom, the files that changed, how it was checked, and anything left open.

Your team members and what each is good at:
EOF
  fi
  team_brief_members "$of"
  cat <<BRIEF

How to delegate (the member runs here, headless, with its own tools, and its reply is printed):
  ai delegate <member> "<task>"           the task as one argument
  ai delegate <member> - <<'EOF'          a long task from stdin
  ...
  EOF
  ai delegate -b <member> "<task>"        in the background: prints its log file
  ai team wait <log>...                   wait for background ones and print their replies (exit 3: still working, run it again)
Rules:
- A member knows nothing of this conversation. Write the task like a ticket: the goal, the files involved, what "done" looks like, and what not to touch.
- Members edit files here directly. Delegations run one at a time per team (the next one waits), so send independent tasks together, but do not touch the same files yourself while a member has them.
- A delegation can take minutes: run it with a long timeout (up to 10 minutes), or with -b and then ai team wait.
- A member marked "leads a team" hands parts of its task on to its own members; you only talk to your own members. Give such a member only a big task with several parts: for one small job, pick a member that does it itself.
- A member at its usage limit is refused: pick another one. One that stops at its limit while working hands the task, and what it did so far, to the next free member by itself; the reply says who finished it.
- Past delegations: ai team log   (the full reply of each one is kept under $AI_TEAM_DIR/logs)
Save tokens (every member pays for what it reads and writes):
- Do a small change (a few lines) yourself; delegating it costs more than doing it. Delegate a big part that a member can finish on its own.
- Put what you already know in the task: the exact files and functions, the error, what you found. Then the member does not search for it again.
- Replies are short reports. Check them cheaply: run the tests and \`git diff --stat\`, then read only the changes that matter. Do not read again a whole file a member reported on, and do not redo a check a member that leads a team already did.
BRIEF
}
team_brief_members() {
  local m r sub
  while IFS="$TAB" read -r m r _; do
    [ -n "$m" ] || continue
    sub=
    team_leads "$m" && sub=" (leads a team: $(cut -f1 "$AI_TEAMS/$m" | paste -sd, - | sed 's/,/, /g'))"
    printf -- '- %s: %s%s
' "$m" "$r" "$sub"
  done <"$(team_file "$1")"
}

# Start the lead with its brief, the extra folders, and leave to run `ai delegate` without
# asking. TEAM_TASK (from `ai do`) is its first message.
team_start() {
  local lead brief d
  local -a pre=()
  [ -s "$AI_TEAM" ] || die "no team yet. set one up:  ai team setup"
  lead=$(team_lead)
  brief=$(team_brief '')
  while IFS= read -r d; do [ -n "$d" ] && pre+=(--add-dir "$d"); done <<EOF
$(team_access_dirs)
EOF
  PATH=$AI_HOME/bin:$PATH
  export AI_TEAM_LEADING=1 # a failover hand-over to Codex or another agent tells it so
  case $lead in
    # Codex has no system prompt option: the brief is its first message
    codex:*)
      run_codex "${lead#codex:}" "${pre[@]}" "$@" "$brief${TEAM_TASK:+

# Your task (from the user)
$TEAM_TASK}"
      ;;
    *)
      run_claude "$lead" "${pre[@]}" "${TEAM_ALLOW[@]}" --append-system-prompt "$brief" "$@" ${TEAM_TASK:+"$TEAM_TASK"}
      ;;
  esac
}

# a lock per folder and team: a member's own team never waits for the lock its leader holds
team_key() { printf '%s%s' "$(pwd -P)" "${AI_TEAM_CHAIN:+@$AI_TEAM_CHAIN}" | sed 's/[^A-Za-z0-9@]/-/g'; }
# one delegation at a time per folder and team (mkdir is atomic, and macOS has no flock)
team_lock() {
  local d waited=0 pid
  [ "${AI_TEAM_LOCK:-1}" = 0 ] && return 0
  d=$AI_TEAM_DIR/locks/$(team_key)
  mkdir -p "$AI_TEAM_DIR/locks" || return 1
  while ! mkdir "$d" 2>/dev/null; do
    pid=$(cat "$d/pid" 2>/dev/null)
    # its owner is gone, or died before it wrote its pid (that takes a moment, not minutes)
    if team_lock_stale "$d" "$pid"; then
      team_take_stale "$d"
      continue
    fi
    [ "$waited" -eq 0 ] && warn "another member is working in this folder; waiting for it (one at a time, so two agents never edit the same files at once)"
    if [ "$waited" -ge "$AI_TEAM_WAIT" ]; then
      warn "gave up after ${AI_TEAM_WAIT}s"
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo $$ >"$d/pid"
  TEAM_LOCK_DIR=$d
  trap 'team_unlock' EXIT
  trap 'team_unlock; exit 130' INT TERM
}
# team_lock_stale <lock> <its pid>: a dead owner, or no pid after a minute or two
team_lock_stale() {
  if [ -n "$2" ]; then
    ! kill -0 "$2" 2>/dev/null
  else
    [ ! -e "$1/pid" ] && [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
  fi
}
# team_take_stale <lock>: two waiters can find the same stale lock, and the first may already
# have made a new one in its place. So only the waiter that gets <lock>.takeover (mkdir is
# atomic) looks again and removes the lock, and only if it is still stale. The takeover holds
# its waiter's pid like a lock, so it is only dropped when that waiter is gone (not paused).
team_take_stale() {
  local g="$1.takeover"
  if ! mkdir "$g" 2>/dev/null; then
    team_lock_stale "$g" "$(cat "$g/pid" 2>/dev/null)" && rm -rf "$g"
    return 0
  fi
  echo $$ >"$g/pid"
  team_lock_stale "$1" "$(cat "$1/pid" 2>/dev/null)" && rm -rf "$1"
  rm -rf "$g"
}
team_unlock() {
  [ -n "${TEAM_LOCK_DIR:-}" ] && rm -rf "$TEAM_LOCK_DIR"
  TEAM_LOCK_DIR=
}

ai_delegate() {
  local bg='' m task c log left f by=${AI_TEAM_AS:-} chain=${AI_TEAM_CHAIN:-} whose=the rc tried title
  [ -n "$by" ] && whose="$by's"
  case ${1:-} in -b | --background) bg=1; shift ;; esac
  m=${1:-}
  [ $# -gt 0 ] && shift
  [ -n "$m" ] || die "usage: ai delegate [-b] <member> <task>   (or - to read the task from stdin)"
  f=$(team_mine)
  [ -z "$by" ] || [ -s "$f" ] || die "you ($by) have no team of your own: do the task yourself"
  team_has "$m" "$by" || die "'$m' is not in $whose team. see: ai team ls, or add it: ai team add ${by:+--of $by }$m \"<what it is good at>\""
  team_member_ok "$m" || die "team member '$m' is gone (its account or agent was removed). see: ai team ls"
  case " $chain " in *" $m "*) die "$m is already working on this task higher up ($chain): pick another member" ;; esac
  [ "$(team_depth)" -lt "$AI_TEAM_MAX_DEPTH" ] || die "this is $AI_TEAM_MAX_DEPTH levels down already (AI_TEAM_MAX_DEPTH): do the task yourself"
  if [ $# -eq 0 ] || [ "$*" = - ]; then
    [ -t 0 ] && die "no task given. write it as an argument, or pipe it in: ai delegate $m - <<'EOF' ... EOF"
    task=$(cat)
  else
    task=$*
  fi
  [ -n "$task" ] || die "the task is empty"
  c=$(team_cmd "$m" "$f") || die "ai doesn't know how to run '$m' headless. give the command: ai team add ${by:+--of $by }$m \"<good at>\" \"<command>\""
  if left=$(fo_limited "$m"); then
    die "$m is at its usage limit for another $((left / 3600))h$((left % 3600 / 60))m. pick another member (see: ai failover status)"
  fi
  team_private || return 1
  team_prune
  log=${AI_TEAM_LOG:-$AI_TEAM_DIR/logs/$(date +%Y%m%d-%H%M%S)-$(echo "$m" | tr : -)-$$.log}
  # only for this delegation: a member that delegates in turn writes its own log
  unset AI_TEAM_LOG
  if [ -n "$bg" ]; then
    # a fresh ai process, so the lock belongs to it and it outlives this shell
    (umask 077 && : >"$log") || return 1
    (AI_TEAM_LOG=$log nohup bash "$AI_HOME/bin/ai" delegate "$m" "$task" >/dev/null 2>&1 </dev/null &)
    echo "started $m in the background. its reply goes to $log (wait for it: ai team wait $log)"
    return 0
  fi
  # a member that stops at its usage limit hands the task on (team_work sets TEAM_NEXT); the
  # whole chain writes to one log, so `ai team wait` sees one delegation
  title=$(printf '%s' "$task" | head -n 1 | cut -c1-80)
  tried=" $m "
  while :; do
    TEAM_NEXT=
    team_work "$m" "$c" "$task" "$log" "$title" "$f" "$tried"
    rc=$?
    [ -n "$TEAM_NEXT" ] || return "$rc"
    task=$(team_handoff_task "$m" "$task" "$TEAM_REPLY")
    m=$TEAM_NEXT
    tried="$tried$m "
    c=$(team_cmd "$m" "$f") || {
      team_end "$log" "$rc"
      return "$rc"
    }
  done
}
# team_end <log> <exit code>: end a log that did not get its own end line (it waited for the
# folder too long, or the member that should take over can't run), so `ai team wait` stops
team_end() {
  (umask 077 && printf '# done (exit %s) in 0m00s\n' "$2" >>"$1")
}

# team_work <member> <command> <task> <log> [journal title] [members file] [tried]: run it,
# print its reply, keep the log and a journal line. When it stops at its usage limit and
# another member is free, sets TEAM_NEXT (and TEAM_REPLY, what it wrote) instead of ending the log.
team_work() {
  local m=$1 c=$2 task=$3 log=$4 title=${5:-} f=${6:-} tried=${7:-} start rc jrc secs by=${AI_TEAM_AS:-} chain at reply next=''
  local -a extra=()
  [ -n "$title" ] || title=$(printf '%s' "$3" | head -n 1 | cut -c1-80)
  [ -n "$f" ] || f=$(team_mine)
  chain=${AI_TEAM_CHAIN:+$AI_TEAM_CHAIN }$m
  # a member that leads a team (and is not at the bottom) gets its brief, and may delegate
  if team_leads "$m" && [ "$(AI_TEAM_CHAIN=$chain team_depth)" -lt "$AI_TEAM_MAX_DEPTH" ]; then
    if team_is_claude "$m" && [ -z "$(tsv_get "$f" "$m" 3)" ]; then
      extra=("${TEAM_ALLOW[@]}" --append-system-prompt "$(team_brief "$m" "${by:-$(team_lead)}")")
    else
      task="$(team_brief "$m" "${by:-$(team_lead)}")

# Your task (from ${by:-$(team_lead)})
$task"
    fi
  fi
  [ -n "$AI_TEAM_REPORT" ] && task="$task

$AI_TEAM_REPORT"
  team_lock || {
    team_end "$log" 1
    return 1
  }
  (umask 077 && : >>"$log") || return 1 # only here: the member itself runs with your umask
  printf 'ai: %s is working on it in %s  (log: %s)\n' "$m" "$PWD" "$log" >&2
  printf '# %s · %s · %s\n# task:\n%s\n# reply:\n' "$(date '+%Y-%m-%d %H:%M')" "$m" "$PWD" "$task" >>"$log"
  at=$(wc -c <"$log" | tr -d ' ') # where its reply starts: the task is never read as its reply
  start=$(date +%s)
  # the last stage fails when the member printed nothing (its reason, if any, went to the log)
  AI_TEAM_AS=$m AI_TEAM_CHAIN=$chain PATH=$AI_HOME/bin:$PATH \
    team_run "$m" "$c" "${extra[@]}" "$task" </dev/null 2>>"$log" | tee -a "$log" |
    awk '{ print; fflush() } END { exit NR == 0 }'
  local -a st=("${PIPESTATUS[@]}")
  rc=${st[0]}
  secs=$(($(date +%s) - start))
  team_unlock
  if [ "$rc" -ne 0 ]; then
    reply=$(tail -c +"$((at + 1))" "$log")
    # only its last lines: the CLIs print a limit error last, and a member that printed code or
    # output about "usage limits" while it worked is not mistaken for one at its limit
    if fo_hit_limit "$(printf '%s' "$reply" | tail -n 5)"; then
      mkdir -p "$AI_STATE_DIR/limited" && { has jq && fo_reset_at "$m" "$(printf '%s' "$reply" | tail -n 5)"; } >"$(fo_mark "$m")"
      warn "$m hit its usage limit and is skipped until it resets (see: ai failover status)"
      [ "$AI_TEAM_HANDOFF" = 0 ] || next=$(team_backup "$f" "$tried")
    fi
  fi
  jrc=$rc
  [ -n "$next" ] && jrc=handoff # not an end: `ai team wait` waits for the one that takes over
  if [ -n "$next" ]; then
    printf '# %s stopped at its usage limit after %dm%02ds: handed over to %s\n' "$m" $((secs / 60)) $((secs % 60)) "$next" >>"$log"
  else
    printf '# done (exit %s) in %dm%02ds\n' "$rc" $((secs / 60)) $((secs % 60)) >>"$log"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$m" "$PWD" "$jrc" "$secs" "$log" \
    "$title" "$by" >>"$AI_TEAM_DIR/journal"
  if [ "$rc" -eq 0 ] && [ "${st[2]}" -ne 0 ]; then
    printf 'ai: %s ended (%dm%02ds) without a reply. the end of its log:\n' "$m" $((secs / 60)) $((secs % 60)) >&2
    tail -c +"$((at + 1))" "$log" | tail -n 5 >&2
  elif [ "$rc" -eq 0 ]; then
    printf 'ai: %s is done (%dm%02ds)\n' "$m" $((secs / 60)) $((secs % 60)) >&2
  elif [ -n "$next" ]; then
    warn "handing the task to $next, with what $m did so far ($(team_provider "$next") gets it)"
    TEAM_NEXT=$next
    TEAM_REPLY=$reply
  else
    printf 'ai: %s failed (exit %s). the end of its log:\n' "$m" "$rc" >&2
    tail -n 5 "$log" >&2
  fi
  return "$rc"
}

# team_backup <members file> <tried>: the member to hand a task to when one stops at its
# limit: in failover order first, then in team order; not tried yet, not higher up the
# chain, not limited, and runnable headless
team_backup() {
  local a
  { fo_order 2>/dev/null; cut -f1 "$1"; } | awk 'NF && !seen[$0]++' | while IFS= read -r a; do
    [ -n "$(tsv_get "$1" "$a" 1)" ] || continue
    case "$2 ${AI_TEAM_CHAIN:-} " in *" $a "*) continue ;; esac
    team_member_ok "$a" || continue
    fo_limited "$a" >/dev/null && continue
    team_cmd "$a" "$1" >/dev/null || continue
    echo "$a"
    break
  done
}

# team_handoff_task <member> <its task> <what it wrote>: the task for the member taking over
team_handoff_task() {
  local r
  # the end of it, from a line start (never half a line or half a character)
  [ -z "$3" ] || r=$(AI_FO_HANDOFF_MAX=$AI_TEAM_HANDOFF_MAX fo_cut "$3")
  printf '%s\n' "\"$1\" started this task and stopped at its usage limit. You take it over. It may already have changed files here: look at \`git status\` and \`git diff\` first, keep what is done, and finish the rest.

# The task
$2"
  [ -z "$r" ] || printf '\n# What "%s" wrote before it stopped (the end)\n%s\n' "$1" "$r"
}

# Logs hold whole tasks and replies (often code), so the team folder is yours alone:
# folders 700, files 600. A folder made by an older ai with looser modes is fixed once.
team_private() {
  local d=$AI_TEAM_DIR
  mkdir -p "$AI_STATE_DIR" || return 1
  (umask 077 && mkdir -p "$d/logs" "$d/locks" && : >>"$d/journal") || return 1
  # all private already: the three folders, the journal and every log
  case $(ls -ld "$d" "$d/logs" "$d/locks" | cut -c1-10 | sort -u) in
    drwx------) [ -z "$(find "$d/journal" "$d/logs" -type f \( -perm -040 -o -perm -020 -o -perm -010 -o -perm -004 -o -perm -002 -o -perm -001 \) 2>/dev/null | head -n 1)" ] && return 0 ;;
  esac
  chmod 700 "$d" "$d/logs" "$d/locks" && chmod 600 "$d/journal" &&
    find "$d/logs" -type f -exec chmod 600 {} +
}

# team_done <log>: the delegation has ended: its last line is the exact one team_work writes
# (a task or a reply can hold a line that starts with "# done"), or, when something the
# member left running wrote after it, the journal already has its line.
team_done() {
  [ -f "$1" ] || return 1
  tail -n 1 "$1" | grep -q '^# done (exit [0-9]*) in [0-9]*m[0-9]*s$' && return 0
  # a member that handed the task over has a journal line too, with "handoff" for its exit code
  [ -f "$AI_TEAM_DIR/journal" ] && awk -F'\t' -v l="$1" '$6 == l && $4 ~ /^[0-9]+$/ { f = 1 } END { exit !f }' "$AI_TEAM_DIR/journal"
}

# team_prune [days]: delete the logs of finished delegations older than that (default
# AI_TEAM_KEEP_DAYS; 0 keeps them). A log that has not ended (team_done) stays.
team_prune() {
  local days=${1-$AI_TEAM_KEEP_DAYS}
  case $days in '' | *[!0-9]*) warn "AI_TEAM_KEEP_DAYS must be a number of days"; return 0 ;; esac
  [ "$days" -gt 0 ] || [ $# -gt 0 ] || return 0
  [ -d "$AI_TEAM_DIR/logs" ] || return 0
  if [ "$days" -gt 0 ]; then set -- -mtime +"$((days - 1))"; else set --; fi
  local f
  find "$AI_TEAM_DIR/logs" -type f -name '*.log' "$@" | while IFS= read -r f; do
    team_done "$f" && rm -f "$f"
  done
  return 0
}

# ai team log --clean: delete every finished log now and empty the journal
team_clean() {
  local n f
  n=$(find "$AI_TEAM_DIR/logs" -type f -name '*.log' 2>/dev/null | while IFS= read -r f; do team_done "$f" && echo; done | wc -l | tr -d ' ')
  confirm "delete $n finished delegation logs and the journal (ai team log)?" || return 1
  # the journal first: a delegation ending meanwhile then keeps its journal line
  [ -f "$AI_TEAM_DIR/journal" ] && : >"$AI_TEAM_DIR/journal"
  team_prune 0
  echo "deleted $n logs and emptied the journal (running delegations keep theirs)"
}

team_log() {
  local n=${1:-10} t m d rc s l task by
  [ "$n" = --clean ] && {
    team_clean
    return
  }
  case $n in '' | *[!0-9]*) die "usage: ai team log [n | --clean]" ;; esac
  [ -s "$AI_TEAM_DIR/journal" ] || {
    echo "no delegations yet"
    return 0
  }
  tail -n "$n" "$AI_TEAM_DIR/journal" | while IFS="$TAB" read -r t m d rc s l task by; do
    [ -f "$l" ] || l="$l (deleted)"
    case $rc in
      0) rc=$(printf '\033[32mok\033[0m') ;;
      handoff) rc=$(printf '\033[33mhanded over\033[0m') ;;
      *) rc=$(printf '\033[31mexit %s\033[0m' "$rc") ;;
    esac
    printf '%s  \033[1;36m%-14s\033[0m %s  %dm%02ds  %s\n      %s\n' "$t" "$m" "$rc" $((s / 60)) $((s % 60)) "$task" "$(dim "${by:+from $by · }$d · $l")"
  done
}

# team_wait <log>...: wait until background delegations end, then print each reply. Gives up
# after AI_TEAM_WAIT_STEP seconds with exit 3, so an agent's shell call never times out on it.
team_wait() {
  local f waited=0 todo
  [ $# -gt 0 ] || die "usage: ai team wait <log>...   (the files ai delegate -b printed)"
  for f in "$@"; do [ -f "$f" ] || die "no log $f"; done
  while :; do
    todo=0
    for f in "$@"; do team_done "$f" || todo=$((todo + 1)); done
    [ "$todo" -eq 0 ] && break
    if [ "$waited" -ge "$AI_TEAM_WAIT_STEP" ]; then
      echo "$todo still working after ${waited}s. run ai team wait again"
      return 3
    fi
    sleep 2
    waited=$((waited + 2))
  done
  for f in "$@"; do
    printf '=== %s\n' "$(head -n 1 "$f" | sed 's/^# //')"
    # after a hand-over, only the reply of the member that finished
    awk 'NR == FNR { if ($0 == "# reply:") n = FNR; next }
      n && FNR > n { print }
      END { if (!n) print "(no reply: it never started; the log says why)" }' "$f" "$f"
  done
}
