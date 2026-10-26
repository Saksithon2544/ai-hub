# shellcheck shell=bash
# Several Codex accounts. "main" is your normal Codex login (~/.codex, or $CODEX_HOME); every
# other account lives in $CDX_ROOT/<name> and runs with CODEX_HOME pointing there.
# Each login (auth.json) stays in its account's folder: it is never read or copied.

# shared from main into every new account (links, so a change shows up everywhere).
# Not shared: the login, sessions and history.
CDX_SHARED="config.toml AGENTS.md prompts"
CDX_RESERVED="main ls add rm mv help"

cdx_dir() {
  if [ "$1" = main ]; then echo "$AI_CODEX_MAIN"; else echo "$CDX_ROOT/$1"; fi
}
cdx_exists() {
  [ "$1" = main ] && return 0
  valid_name "$1" && [ -d "$CDX_ROOT/$1" ] && [ ! -L "$CDX_ROOT/$1" ]
}
# main first, then the other accounts by name
cdx_list() {
  echo main
  sub_accounts "$CDX_ROOT"
}
# logged in = the account has a login file (only its presence is checked)
cdx_logged_in() { [ -f "$(cdx_dir "$1")/auth.json" ]; }
cdx_reserved() {
  case " $CDX_RESERVED " in *" $1 "*) return 0 ;; esac
  return 1
}

# cdx_env <account> <command...>: run a command with that account's CODEX_HOME
cdx_env() {
  local a=$1
  shift
  (
    CODEX_HOME=$(cdx_dir "$a")
    export CODEX_HOME
    "$@"
  )
}

# the saved Codex command (e.g. "codex --model o3"), or plain codex
codex_cmd() {
  local c
  c=$(prov_get codex 2)
  echo "${c:-codex}"
}

# start Codex on an account in this folder
run_codex() {
  local a=$1
  shift
  cdx_exists "$a" || die "no Codex account '$a'. add it: ai codex add $a"
  trust_share "$PWD"
  cdx_env "$a" launch "$(codex_cmd)" "$@"
}

cdx_main() {
  case ${1:-} in
    '') pick_and_run codex ;;
    ls) cdx_ls ;;
    add) shift; cdx_add "$@" ;;
    rm) shift; cdx_rm "$@" ;;
    mv) shift; cdx_mv "$@" ;;
    help | -h | --help) cdx_help ;;
    -*) pick_and_run codex "$@" ;;
    *)
      local a=$1
      shift
      run_codex "$a" "$@"
      ;;
  esac
}

cdx_help() {
  cat <<'EOF'
ai codex                      pick a Codex account and start it here
ai codex <name> [codex args]  start that account ("main" = your normal ~/.codex login)
ai codex <name> login         log that account in
ai codex ls                   list accounts and whether they are logged in
ai codex add <name>           add an account
ai codex rm <name>            move an account to the trash folder (nothing is deleted)
ai codex mv <old> <new>       rename an account

In failover, a Codex account is named codex:<name>, e.g. ai failover order work codex:main
EOF
}

cdx_ls() {
  local a
  for a in $(cdx_list); do
    if cdx_logged_in "$a"; then
      printf '\033[1;36m%-12s\033[0m %s\n' "$a" "logged in    $(dim "$(cdx_dir "$a")")"
    else
      printf '\033[1;36m%-12s\033[0m %s\n' "$a" "$(dim "not logged in  (ai codex $a login)")"
    fi
  done
}

cdx_add() {
  local n=${1:-} d f m
  [ -n "$n" ] || die "usage: ai codex add <name>"
  need_name "$n"
  cdx_reserved "$n" && die "'$n' is reserved, pick another name"
  d=$CDX_ROOT/$n
  if [ -e "$d" ] || [ -L "$d" ]; then die "'$n' already exists"; fi
  mkdir -p "$d" || die "could not create $d"
  chmod 700 "$d"
  m=$(cdx_dir main)
  for f in $CDX_SHARED; do
    if [ -e "$m/$f" ] && [ ! -e "$d/$f" ] && [ ! -L "$d/$f" ]; then
      ln -s "$m/$f" "$d/$f"
    fi
  done
  # make sure Codex shows up in the picker
  prov_has codex || prov_put codex codex "Codex CLI"
  echo "added Codex account '$n' in $d"
  echo "log in with: ai codex $n login   then start it with: ai codex $n"
}

cdx_rm() {
  local n=${1:-} t
  [ -n "$n" ] || die "usage: ai codex rm <name>"
  need_name "$n"
  [ "$n" = main ] && die "main is your normal ~/.codex login and can't be removed here"
  cdx_exists "$n" || die "no Codex account '$n'. see: ai codex ls"
  confirm "move Codex account '$n' to $CDX_ROOT/.trash/? (its login and history are kept there)" || return 1
  mkdir -p "$CDX_ROOT/.trash" || die "could not create $CDX_ROOT/.trash"
  t=$CDX_ROOT/.trash/$n-$(date +%Y%m%d-%H%M%S)
  [ -e "$t" ] && t=$t-$$
  mv "$CDX_ROOT/$n" "$t" || die "could not move $CDX_ROOT/$n"
  echo "moved '$n' to $t"
  echo "tip: to also sign it out, move it back and run: ai codex $n logout"
}

cdx_mv() {
  local a=${1:-} b=${2:-}
  [ -n "$a" ] && [ -n "$b" ] || die "usage: ai codex mv <old> <new>"
  need_name "$a"
  need_name "$b"
  if [ "$a" = main ] || [ "$b" = main ]; then die "main can't be renamed"; fi
  cdx_reserved "$b" && die "'$b' is reserved, pick another name"
  cdx_exists "$a" || die "no Codex account '$a'. see: ai codex ls"
  if [ -e "$CDX_ROOT/$b" ] || [ -L "$CDX_ROOT/$b" ]; then die "'$b' already exists"; fi
  mv "$CDX_ROOT/$a" "$CDX_ROOT/$b" || die "could not rename"
  fo_rename "codex:$a" "codex:$b"
  echo "renamed '$a' -> '$b'"
}
