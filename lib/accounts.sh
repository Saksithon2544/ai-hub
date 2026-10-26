# shellcheck shell=bash
# Several Claude Code accounts. "main" is your normal login (~/.claude); every other
# account lives in $CLA_ROOT/<name> and runs with CLAUDE_CONFIG_DIR pointing there.

# shared from ~/.claude into every new account (links, so a change shows up everywhere).
# Not shared: the login, history (projects/) and .claude.json.
CLA_SHARED="settings.json CLAUDE.md agents commands skills plugins"
CLA_RESERVED="main ls add rm mv help"

acct_dir() {
  if [ "$1" = main ]; then echo "${AI_MAIN_CFG:-$HOME/.claude}"; else echo "$CLA_ROOT/$1"; fi
}
# the .claude.json holding an account's login info and trusted folders
acct_json() {
  if [ "$1" = main ] && [ -z "$AI_MAIN_CFG" ]; then
    echo "$HOME/.claude.json"
  else
    echo "$(acct_dir "$1")/.claude.json"
  fi
}
acct_exists() {
  [ "$1" = main ] && return 0
  valid_name "$1" && [ -d "$CLA_ROOT/$1" ] && [ ! -L "$CLA_ROOT/$1" ]
}
# main first, then the other accounts by name
acct_list() {
  echo main
  sub_accounts "$CLA_ROOT"
}
acct_email() {
  has jq && jq -r '.oauthAccount.emailAddress // empty' "$(acct_json "$1")" 2>/dev/null
}
is_reserved() {
  case " $CLA_RESERVED " in *" $1 "*) return 0 ;; esac
  return 1
}

# acct_env <account> <command...>: run a command with that account's CLAUDE_CONFIG_DIR
acct_env() {
  local a=$1
  shift
  (
    if [ "$a" != main ]; then
      export CLAUDE_CONFIG_DIR="$CLA_ROOT/$a"
    elif [ -n "$AI_MAIN_CFG" ]; then
      export CLAUDE_CONFIG_DIR="$AI_MAIN_CFG"
    else
      unset CLAUDE_CONFIG_DIR
    fi
    "$@"
  )
}

# the saved Claude command (e.g. "claude --model opus"), or plain claude
claude_cmd() {
  local c
  c=$(prov_get claude 2)
  echo "${c:-claude}"
}

# start Claude on an account in this folder (with failover when it is on)
run_claude() {
  local a=$1
  shift
  acct_exists "$a" || die "no account '$a'. add it: cla add $a"
  trust_share "$PWD"
  if fo_on; then
    fo_run "$a" "$@"
  else
    acct_env "$a" launch "$(claude_cmd)" "$@"
  fi
}

cla_main() {
  case ${1:-} in
    '') pick_and_run claude ;;
    ls) cla_ls ;;
    add) shift; cla_add "$@" ;;
    rm) shift; cla_rm "$@" ;;
    mv) shift; cla_mv "$@" ;;
    help | -h | --help) cla_help ;;
    -*) pick_and_run claude "$@" ;;
    *)
      local a=$1
      shift
      run_claude "$a" "$@"
      ;;
  esac
}

cla_help() {
  cat <<'EOF'
cla                      pick a Claude account and start it here
cla <name> [claude args] start that account ("main" = your normal ~/.claude login)
cla ls                   list accounts and who is logged in
cla add <name>           add an account (it asks you to log in the first time you start it)
cla rm <name>            move an account to the trash folder (nothing is deleted)
cla mv <old> <new>       rename an account
EOF
}

cla_ls() {
  local a e
  for a in $(acct_list); do
    e=$(acct_email "$a")
    if [ -n "$e" ]; then
      printf '\033[1;36m%-12s\033[0m %s\n' "$a" "$e"
    else
      printf '\033[1;36m%-12s\033[0m %s\n' "$a" "$(dim 'not logged in')"
    fi
  done
}

cla_add() {
  local n=${1:-} d f m
  [ -n "$n" ] || die "usage: cla add <name>"
  need_name "$n"
  is_reserved "$n" && die "'$n' is reserved, pick another name"
  d=$CLA_ROOT/$n
  if [ -e "$d" ] || [ -L "$d" ]; then die "'$n' already exists"; fi
  mkdir -p "$d" || die "could not create $d"
  chmod 700 "$d"
  m=$(acct_dir main)
  for f in $CLA_SHARED; do
    if [ -e "$m/$f" ] && [ ! -e "$d/$f" ] && [ ! -L "$d/$f" ]; then
      ln -s "$m/$f" "$d/$f"
    fi
  done
  # make sure Claude shows up in the picker
  prov_has claude || prov_put claude claude "Claude Code"
  echo "added account '$n' in $d"
  echo "start it with: cla $n   (Claude asks you to log in the first time)"
}

cla_rm() {
  local n=${1:-} t
  [ -n "$n" ] || die "usage: cla rm <name>"
  need_name "$n"
  [ "$n" = main ] && die "main is your normal ~/.claude login and can't be removed here"
  acct_exists "$n" || die "no account '$n'. see: cla ls"
  confirm "move account '$n' to $CLA_ROOT/.trash/? (its login and history are kept there)" || return 1
  mkdir -p "$CLA_ROOT/.trash" || die "could not create $CLA_ROOT/.trash"
  t=$CLA_ROOT/.trash/$n-$(date +%Y%m%d-%H%M%S)
  [ -e "$t" ] && t=$t-$$
  mv "$CLA_ROOT/$n" "$t" || die "could not move $CLA_ROOT/$n"
  rm -f "$AI_STATE_DIR/limited/$n"
  echo "moved '$n' to $t"
  echo "tip: to also sign it out, move it back, start it and type /logout"
}

cla_mv() {
  local a=${1:-} b=${2:-}
  [ -n "$a" ] && [ -n "$b" ] || die "usage: cla mv <old> <new>"
  need_name "$a"
  need_name "$b"
  if [ "$a" = main ] || [ "$b" = main ]; then die "main can't be renamed"; fi
  is_reserved "$b" && die "'$b' is reserved, pick another name"
  acct_exists "$a" || die "no account '$a'. see: cla ls"
  if [ -e "$CLA_ROOT/$b" ] || [ -L "$CLA_ROOT/$b" ]; then die "'$b' already exists"; fi
  mv "$CLA_ROOT/$a" "$CLA_ROOT/$b" || die "could not rename"
  fo_rename "$a" "$b"
  echo "renamed '$a' -> '$b'"
  # Claude on macOS keeps the login in Keychain under a name made from the folder path.
  # We don't copy secrets around, so log in again once.
  if [ "$(uname -s)" = Darwin ]; then
    echo "note: on macOS you may need to log in again: cla $b, then /login"
  fi
}
