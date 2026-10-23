# shellcheck shell=bash
# Entry point and help.

ai_main() {
  local sub
  case ${1:-} in
    ls | add | edit | rm | trust | failover)
      sub=$1
      shift
      "ai_$sub" "$@"
      ;;
    cla)
      shift
      cla_main "$@"
      ;;
    help | -h | --help) ai_help ;;
    version | -v | --version) echo "ai-hub $AI_VERSION" ;;
    *) pick_and_run all "$@" ;;
  esac
}

ai_help() {
  cat <<'EOF'
ai                                  pick an agent (with plan usage) and start it in this folder
ai [agent args]                     same; extra args go to the agent (e.g. ai --resume)

ai ls                               list agents and their launch commands
ai add  <name> <command> [label]    add an agent      e.g. ai add aider "aider --model sonnet"
ai edit <name> <command> [label]    change its command
ai rm   <name>                      remove it from the list

cla ...                             several Claude accounts (see: cla help)

ai trust [on|off|status]            share folder trust between agents (off by default)
ai failover [on|off|status]         resume on the next Claude account at a usage limit
ai failover order <account>...     set the order (top is tried first)
ai failover clear [account]         forget a limit

Files: ~/.config/ai-hub (settings)  ~/.local/state/ai-hub (limits)  ~/.claude-accounts (accounts)
Optional tools: fzf (searchable picker), jq (usage bars, trust, failover)
EOF
}
