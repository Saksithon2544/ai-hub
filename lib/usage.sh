# shellcheck shell=bash
# Plan usage, read only from files the agents already write. Nothing is fetched from the internet.

# bar <label> <percent> <reset text>  ->  "5h ███░░░░░░░  33% (Tue 12:00)  "
# Fixed width, so rows line up. Green below 60%, yellow from 60%, red from 90%.
bar() {
  local label=$1 pct=$2 at=$3 c n
  case $pct in
    '' | *[!0-9]*)
      printf '%-3s \033[2m%s  n/a %-12s\033[0m' "$label" "$(rep ─ 10)" ''
      return
      ;;
  esac
  if [ "$pct" -ge 90 ]; then c=31; elif [ "$pct" -ge 60 ]; then c=33; else c=32; fi
  n=$(((pct + 5) / 10))
  [ "$n" -gt 10 ] && n=10
  printf '%-3s \033[%sm%s\033[2m%s\033[0m \033[1;%sm%3d%%\033[0m \033[2m%-12s\033[0m' \
    "$label" "$c" "$(rep █ "$n")" "$(rep ░ $((10 - n)))" "$c" "$pct" "${at:+($at)}"
}

# claude_usage <config dir>  ->  "5h%|5h reset|7d%|7d reset|minutes since saved"
# Reads <config dir>/usage/usage.json, written by scripts/statusline-usage.sh.
# A window whose reset time has passed shows 0%.
claude_usage() {
  local f=$1/usage/usage.json
  [ -r "$f" ] && has jq || return 0
  jq -r --argjson now "$(date +%s)" '
    def w:
      if . == null or .used_percentage == null then "", ""
      elif .resets_at != null and .resets_at < $now then "0", ""
      else (.used_percentage | floor | tostring),
           (if .resets_at == null then "" else (.resets_at | localtime | strftime("%a %H:%M")) end)
      end;
    [(.rate_limits.five_hour | w), (.rate_limits.seven_day | w),
     ((($now - (.saved_at // $now)) / 60) | floor | tostring)] | join("|")' "$f" 2>/dev/null
}

# codex_usage [codex home]  ->  "win1|%|reset|win2|%|reset"
# Reads the rate limits saved in the newest Codex session log.
codex_usage() {
  local home=${1:-${CODEX_HOME:-$HOME/.codex}} f rl
  has jq && [ -d "$home/sessions" ] || return 0
  # sessions/YYYY/MM/DD/rollout-<time>.jsonl, so name order is time order
  f=$(find "$home/sessions" -type f -name '*.jsonl' 2>/dev/null | sort | tail -n 1)
  [ -n "$f" ] || return 0
  rl=$(grep '"rate_limits"' "$f" 2>/dev/null | tail -n 1 | jq -c '[.. | .rate_limits? // empty] | last' 2>/dev/null)
  [ -n "$rl" ] && [ "$rl" != null ] || return 0
  printf '%s' "$rl" | jq -r --argjson now "$(date +%s)" '
    def w:
      if . == null or .used_percent == null then "", "", ""
      else (.window_minutes // 0 | if . >= 1440 then "\(. / 1440 | floor)d" elif . >= 60 then "\(. / 60 | floor)h" else "\(.)m" end),
           (if .resets_at != null and .resets_at < $now then "0" else (.used_percent | floor | tostring) end),
           (if .resets_at == null or .resets_at < $now then "" else (.resets_at | localtime | strftime("%a %H:%M")) end)
      end;
    [(.primary | w), (.secondary | w)] | join("|")' 2>/dev/null
}

# the CODEX_HOME a provider uses: from its command (CODEX_HOME=...), else the default
prov_codex_home() {
  local h
  h=$(prov_get "$1" 2 | sed -n 's/.*CODEX_HOME=\([^ ]*\).*/\1/p' | tr -d "\"'")
  case $h in '~/'*) h=$HOME/${h#\~/} ;; esac
  echo "${h:-${CODEX_HOME:-$HOME/.codex}}"
}

# "12m old" style age, only when the data is 10+ minutes old
age_note() {
  case $1 in '' | *[!0-9]*) return 0 ;; esac
  [ "$1" -ge 10 ] || return 0
  if [ "$1" -ge 2880 ]; then dim " · $(($1 / 1440))d old"
  elif [ "$1" -ge 120 ]; then dim " · $(($1 / 60))h old"
  else dim " · ${1}m old"; fi
}
