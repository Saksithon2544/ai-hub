# shellcheck shell=bash
# ai team discover: the members say what they do best, and the lead splits the work.
#
# Every candidate (the members of every team, or the ones you name) is asked about itself at
# the same time, headless, in an empty folder: its model, what it does best and worst, and
# whether it is fast or thorough. ai adds what it knows itself: the provider and how much of
# its plan is used. The lead reads all of it and answers with a team: each member's role, who
# leads a sub-team, and who takes over from the lead at its usage limit (the failover order).
# You see it and say y before anything changes (the old team and order are kept as .bak).
# It runs only when you ask, so everyday tasks cost nothing extra.

AI_TEAM_DISCOVER_MAX=${AI_TEAM_DISCOVER_MAX:-1500} # the most of each answer the lead reads, in bytes

TEAM_INTERVIEW="You are being interviewed to join a team of AI coding agents. Answer about yourself only, in at most 8 short lines of plain text, without using any tool:
model: the model you run as (name and version, if you know it)
best at: the 3 kinds of coding work you do best
weak at: the work to avoid giving you
style: fast and cheap, or slow and thorough"

# the members of every team, the lead's team first, each once (the lead itself left out)
team_all_members() {
  local f l
  l=$(team_lead)
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] && cut -f1 "$f"
  done | awk -v l="$l" 'NF && $0 != l && !seen[$0]++'
}
# the command a member was given in any team (empty = ai's default)
team_saved_cmd() {
  local f c
  for f in "$AI_TEAM" "$AI_TEAMS"/*; do
    [ -f "$f" ] || continue
    c=$(tsv_get "$f" "$1" 3)
    [ -n "$c" ] && echo "$c" && return 0
  done
  return 0
}
# what ai knows about a member: the provider and how much of its plan is used
team_facts() {
  local u
  case $1 in
    codex:*)
      u=$(codex_usage "$(cdx_dir "${1#codex:}")" | awk -F'|' '{
        if ($2 != "") printf "%s window %s%% used", $1, $2
        if ($5 != "") printf ", %s window %s%% used", $4, $5 }')
      printf 'Codex CLI (OpenAI), account %s%s' "${1#codex:}" "${u:+; plan: $u}"
      ;;
    *)
      if acct_exists "$1"; then
        u=$(claude_usage "$(acct_dir "$1")" | awk -F'|' '{
          if ($1 != "") printf "5-hour window %s%% used", $1
          if ($3 != "") printf ", weekly %s%% used", $3 }')
        printf 'Claude Code (Anthropic), account %s%s' "$1" "${u:+; plan: $u}"
      else
        printf '%s, agent %s' "$(prov_get "$1" 3)" "$1"
      fi
      ;;
  esac
}

team_discover() {
  local lead dir tmpd m c i=0 pid f facts answers answered=' ' prompt out roles why order mem par role top=' ' clean=''
  local -a ms=() pids=() leads=()
  lead=$(team_lead)
  if [ $# -gt 0 ]; then
    for m in "$@"; do
      [ "$m" != "$lead" ] || die "$m is the lead: name the members only"
      team_member_ok "$m" || die "no account or agent '$m'. see: cla ls, ai codex ls (written codex:<name>), ai ls"
      ms+=("$m")
    done
  else
    while IFS= read -r m; do [ -n "$m" ] && ms+=("$m"); done <<EOF
$(team_all_members)
EOF
  fi
  [ "${#ms[@]}" -gt 0 ] || die "no members to ask. add some (ai team add ...) or name them: ai team discover <member>..."
  team_private || return 1
  dir=$(mktemp -d "$AI_TEAM_DIR/discover.XXXXXX") || return 1
  # shellcheck disable=SC2064 # the paths now: the function's locals are gone when it exits
  trap "rm -rf '$dir'" EXIT
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/ai-discover.XXXXXX") || return 1 # an empty folder: nothing to read
  # shellcheck disable=SC2064
  trap "rm -rf '$dir' '$tmpd'" EXIT
  # ctrl-c: background jobs ignore SIGINT, so stop the interviews with TERM to the whole group
  trap 'trap "" TERM; kill -TERM 0 2>/dev/null; exit 130' INT TERM

  echo "asking ${#ms[@]} members what they do best (at the same time)..."
  for m in "${ms[@]}"; do
    i=$((i + 1))
    if fo_limited "$m" >/dev/null; then
      echo "  $m is at its usage limit: left out" >&2
      continue
    fi
    c=$(team_saved_cmd "$m")
    [ -n "$c" ] || c=$(team_default_cmd "$m") || {
      echo "  ai doesn't know how to run $m headless: left out" >&2
      continue
    }
    printf '%s\n' "$m" >"$dir/$i.name"
    (cd "$tmpd" && team_run "$m" "$c" "$TEAM_INTERVIEW" </dev/null >"$dir/$i.out" 2>"$dir/$i.err") &
    pids+=($!)
  done
  for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid"; done

  answers=
  for f in "$dir"/*.name; do
    [ -f "$f" ] || continue
    m=$(cat "$f")
    out=$(head -c "$AI_TEAM_DISCOVER_MAX" "${f%.name}.out")
    if [ -z "$out" ]; then
      echo "  $m gave no answer: left out (see why: the end of its error output below)" >&2
      tail -n 3 "${f%.name}.err" | sed 's/^/    /' >&2
      continue
    fi
    printf '  %s answered\n' "$m"
    answered="$answered$m "
    facts=$(team_facts "$m")
    answers="$answers
## $m
facts (from ai-hub): $facts
its own answer:
$out
"
    team_is_claude "$m" && leads+=("$m")
  done
  [ -n "$answers" ] || die "no member answered"

  prompt="You are \"$lead\", the lead of a team of AI coding agents, and you decide who does what. Below, for each member: the facts ai-hub knows (its provider, how much of its plan is used) and its own answer about itself. Give each member the role it does best, so the team does the best work for the fewest tokens.

Rules:
- You are not in the list: do not assign yourself.
- Put every member worth having in your own team (parent \"-\"). A member may also be in one sub-team, under a leader.
- A sub-team leader must be one of: ${leads[*]:-none (so make no sub-teams)}. It must also be in your own team. Make a sub-team only when its leader would get big multi-part work; no deeper than that.
- Weigh the plan: a member with much of its plan used, or a small plan, gets small jobs.
- Members that run the same model should get different areas, not the same role.
- A role is one line of at most 80 characters that says what work to give the member.
- Also choose who takes over from you, in order, when you hit your usage limit (the first takes over first): the members best able to lead, with the most plan left. Claude accounts take the conversation over in full; the others only get it as text, so put them after the Claude accounts.

Answer in exactly this format and nothing else:
ROLES
<member>|<parent>|<role>
END
ORDER
<member> <member> ...
END
WHY
<at most 6 short lines: why this split>
$answers"

  echo "the lead ($lead) is splitting the work..."
  c=$(team_default_cmd "$lead") || die "ai doesn't know how to run the lead $lead headless"
  out=$(cd "$tmpd" && team_run "$lead" "$c" "$prompt" </dev/null 2>"$dir/lead.err")
  roles=$(printf '%s\n' "$out" | sed -n '/^ROLES[[:space:]]*$/,/^END[[:space:]]*$/p' | sed '1d;$d' | tr -d '`\r')
  why=$(printf '%s\n' "$out" | sed -n '/^WHY[[:space:]]*$/,$p' | sed '1d' | head -n 8 | tr -d '\000-\011\013-\037\177')
  order=$(printf '%s\n' "$out" | sed -n '/^ORDER[[:space:]]*$/,/^END[[:space:]]*$/p' | sed '1d;$d' | tr -d '`\r,>' | tr -s ' \t\n' '\n\n\n')
  [ -n "$roles" ] || {
    warn "the lead's answer had no ROLES block:"
    printf '%s\n' "$out" | tail -n 10 >&2
    return 1
  }

  # the lead's lines, trimmed and checked: member|parent|role, the parent "-" for its own team.
  # The text comes from a model: names must resolve, and control characters are dropped, so a
  # role can't redraw the screen before you answer.
  while IFS='|' read -r mem par role; do
    mem=$(printf '%s' "$mem" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    par=$(printf '%s' "$par" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    role=$(printf '%s' "$role" | tr -d '\000-\037\177' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-120)
    [ -n "$mem" ] || continue
    if ! team_member_ok "$mem" || [ "$mem" = "$lead" ] || [ -z "$role" ]; then
      warn "skipped a line the lead got wrong: $mem|$par|$role"
      continue
    fi
    [ -n "$par" ] || par=-
    clean="$clean$mem|$par|$role
"
  done <<EOF
$roles
EOF

  [ -n "$clean" ] || die "the lead's answer placed nobody; nothing changed"

  # The new team starts as the current one without the members that answered: the lead places
  # those again (and leaves out the ones it doesn't want). Members that were not asked, or did
  # not answer, keep their place and their command.
  mkdir -p "$dir/new/teams" || return 1
  if [ -f "$AI_TEAM" ]; then cp -p "$AI_TEAM" "$dir/new/team"; else : >"$dir/new/team"; fi
  for f in "$AI_TEAMS"/*; do [ -f "$f" ] && cp -p "$f" "$dir/new/teams/"; done
  for m in $answered; do
    for f in "$dir/new/team" "$dir/new/teams"/*; do [ -f "$f" ] && tsv_put "$f" "$m"; done
  done
  # first the lead's own team...
  while IFS='|' read -r mem par role; do
    [ "$par" = - ] && [ -n "$mem" ] || continue
    tsv_put "$dir/new/team" "$mem" "$role" "$(team_saved_cmd "$mem")"
    top="$top$mem "
  done <<EOF
$clean
EOF
  # ...then the sub-teams: under a Claude account of the lead's team, one level deep
  while IFS='|' read -r mem par role; do
    [ "$par" != - ] && [ -n "$mem" ] || continue
    case $top in *" $par "*) ;; *) par= ;; esac
    if [ -z "$par" ] || [ "$par" = "$mem" ] || ! team_is_claude "$par"; then
      warn "skipped $mem|${par:-?}: a sub-team leader must be a Claude account in your own team"
      continue
    fi
    if printf '%s' "$clean" | grep -q "^[^|]*|$mem|"; then
      warn "skipped $mem under $par: it leads a sub-team itself (one level deep only)"
      continue
    fi
    tsv_put "$dir/new/teams/$par" "$mem" "$role" "$(team_saved_cmd "$mem")"
  done <<EOF
$clean
EOF
  for f in "$dir/new/teams"/*; do [ -f "$f" ] && [ ! -s "$f" ] && rm -f "$f"; done
  [ -s "$dir/new/team" ] || die "the lead put nobody in its team; nothing changed"
  order=$(team_succession "$lead" "$order")

  echo
  echo "the team the lead proposes:"
  (AI_TEAM=$dir/new/team AI_TEAMS=$dir/new/teams team_show)
  if [ -n "$order" ]; then
    printf '\nwho takes over at a usage limit: %s\n' "$(printf '%s' "$order" | tr '\n' ' ' | sed 's/ $//; s/ / -> /g')"
    fo_on || echo "$(dim "(failover is off: it is used once you run ai failover on)")"
  fi
  [ -n "$why" ] && printf '\nwhy:\n%s\n' "$why"
  echo
  confirm "use this team${order:+ and order}? (the old ones are kept as .bak)" || {
    echo "nothing changed"
    return 1
  }
  # copies as .bak first, then the new files over the old ones: a failure never leaves no team
  mkdir -p "$AI_CONFIG_DIR" || return 1
  [ -f "$AI_TEAM" ] && cp -p "$AI_TEAM" "$AI_TEAM.bak"
  if [ -d "$AI_TEAMS" ]; then rm -rf "$AI_TEAMS.bak" && cp -Rp "$AI_TEAMS" "$AI_TEAMS.bak"; fi
  mv -f "$dir/new/team" "$AI_TEAM" || return 1
  rm -rf "$AI_TEAMS"
  if [ -n "$(ls "$dir/new/teams" 2>/dev/null)" ]; then mv "$dir/new/teams" "$AI_TEAMS"; fi
  if [ -n "$order" ]; then
    [ -f "$AI_FO_ORDER" ] && cp -p "$AI_FO_ORDER" "$AI_FO_ORDER.bak"
    # shellcheck disable=SC2086 # one member per word
    fo_set_order $order >/dev/null || warn "could not save the order"
  fi
  echo "saved. start it with: ai team   (or ai do \"<task>\")"
}

# team_succession <lead> <names>: the order the lead proposed, checked: the lead first, then
# members that can take over (a Claude account, codex:<name> or an agent), each once, Claude
# accounts before the others (they take the whole session; the rest get it as text, at
# another provider). Empty when the lead proposed nobody.
team_succession() {
  local a claude='' other=''
  for a in $2; do
    [ "$a" != "$1" ] && fo_member_ok "$a" || continue
    case " $claude $other " in *" $a "*) continue ;; esac
    if fo_other "$a"; then other="$other $a"; else claude="$claude $a"; fi
  done
  [ -n "$claude$other" ] || return 0
  # shellcheck disable=SC2086 # one member per word
  printf '%s\n' "$1" $claude $other
}
