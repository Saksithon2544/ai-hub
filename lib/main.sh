# shellcheck shell=bash
# Entry point and help.

ai_main() {
  local sub
  case ${1:-} in
    ls | add | edit | rm | scan | trust | failover | team | delegate)
      sub=$1
      shift
      "ai_$sub" "$@"
      ;;
    cla)
      shift
      cla_main "$@"
      ;;
    codex)
      shift
      cdx_main "$@"
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
ai scan                             add known agents installed since (claude codex gemini ...)

cla ...                             several Claude accounts (see: cla help)
ai codex ...                        several Codex accounts (see: ai codex help)

ai trust [on|off|status]            share folder trust between agents (off by default)
ai failover [on|off|status]         resume on the next Claude account at a usage limit
ai failover order <account>...     set the order (top is tried first)
ai failover clear [account]         forget a limit

ai team                             start the team lead with a brief of its members (see: ai team help)
ai team add <member> "<good at>"    add a member: a Claude account, codex:<name>, or an agent from ai ls
ai delegate <member> "<task>"       run a member on a task in this folder (the lead uses this)

Files: ~/.config/ai-hub (settings)  ~/.local/state/ai-hub (limits)  ~/.claude-accounts (accounts)
Optional tools: fzf (searchable picker), jq (usage bars, trust, failover)
EOF
}
