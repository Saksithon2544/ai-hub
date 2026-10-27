# ai-hub

**English** · [ภาษาไทย](README.th.md)

One command for all your AI coding agents. Type `ai` to see every agent and account in one list, with bars showing how much of your plan you've used, then pick one to start it in the current folder.

- **Every agent in one list**: Claude Code (several accounts), Codex, Gemini, Qwen, OpenCode, Kimi, or any CLI you add yourself
- **Plan usage at a glance**: 5-hour and weekly limits with reset times. Bars turn yellow at 60% and red at 90%
- **Several Claude accounts**: add, remove and rename them safely. Removing moves an account to a trash folder, so nothing is really lost
- **Shared folder trust** (off by default): trust a folder once and no agent asks again
- **Several Codex accounts**: the same, with `ai codex`
- **Failover** (off by default): when a Claude account hits its usage limit, continue the same session on the next account, and hand it on to Codex if you add it to the chain
- **A team of agents** (off by default): a lead you talk to does what it is best at and hands the rest to other agents and accounts with `ai delegate`, then checks what they did
- **No API calls**: usage data is read from files the agents already write on your machine

Works on macOS, Linux and WSL. Plain bash (runs on the bash 3.2 built into macOS).

## Install

Download this repo (**Code → Download ZIP**), unpack it anywhere, e.g. `~/ai-hub`, then run:

```bash
cd ~/ai-hub
bash install.sh        # links ai and cla into ~/.local/bin
bash tests/run.sh      # check it before real use; it should end with "all passed"
```

Optional tools (everything works without them, but some features are turned off):

| Tool | Adds |
|---|---|
| [jq](https://jqlang.org) | usage bars, shared trust, failover (built into macOS 15+) |
| [fzf](https://github.com/junegunn/fzf) | a searchable picker; without it you get a numbered menu |

```bash
brew install jq fzf              # macOS
sudo apt install jq fzf          # Linux / WSL
```

### Show Claude plan usage

Claude Code passes plan usage to its status line. Add this to `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh" }
```

If you already have a status line, put its command at the end and the script passes the data on to it:

```json
"statusLine": { "type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh my-statusline --flag" }
```

The numbers show up after Claude's next reply, and only on Pro/Max plans. Accounts made with `cla add` share `settings.json`, so you only set this once.

## Usage

```bash
ai                 # pick an agent and start it in this folder
ai --resume        # any other args are passed on to the agent
ai ls              # list agents and the commands that start them
ai add aider "aider --model sonnet" "Aider"
ai edit claude "claude --model opus"
ai rm aider
ai scan            # add agents installed later (claude codex gemini qwen opencode kimi)
```

The list lives in `~/.config/ai-hub/providers`, one agent per line. On first run it is filled with the agents you have installed; if you install a new one later, run `ai scan`. A command runs like a shell alias, so a `VAR=value` prefix works, e.g. a second Codex account:

```bash
ai add codex-work "CODEX_HOME=~/.codex-work codex" "Codex (work)"
```

Codex usage bars are read from the `CODEX_HOME` in the command; `~/...` and `$HOME/...` both work. For several Codex logins, `ai codex` below is simpler.

### Several Claude accounts

```bash
cla add work       # create an account (settings, skills and plugins are shared with main)
cla work           # start it; Claude asks you to log in the first time
cla main           # your normal account (~/.claude)
cla                # pick an account from the list
cla ls             # see which email each account is logged in with
cla mv work job    # rename
cla rm job         # move to ~/.claude-accounts/.trash/ (nothing is deleted)
```

### Several Codex accounts

```bash
ai codex add work       # create an account (config.toml, AGENTS.md and prompts are shared with main)
ai codex work login     # log it in (any args after the name go to codex)
ai codex work           # start it
ai codex main           # your normal account (~/.codex)
ai codex                # pick a Codex account from the list
ai codex ls             # see which accounts are logged in
ai codex mv work job    # rename
ai codex rm job         # move to ~/.codex-accounts/.trash/ (nothing is deleted)
```

Each account runs with its own `CODEX_HOME` in `~/.codex-accounts/<name>` (set `CDX_ROOT` to use another folder), and shows up in the `ai` picker with its own usage bars. Its login stays in its own folder; ai-hub only checks that the file is there, it never reads it.

### Shared folder trust

```bash
ai trust on        # turn on
ai trust off       # turn off
```

Before an agent starts in a folder: if any agent (or any of your Claude accounts) already trusts that folder, the others are set to trust it too. Supports Claude Code, Codex, Gemini and Qwen.

### Failover

```bash
ai failover on
ai failover order work main personal   # the order to try, top first
ai failover status
ai failover clear work                  # forget a limit
```

When Claude says you've hit a limit, exit Claude (`/exit` or ctrl-c twice). `ai` then asks whether to continue on the next account. Answer `y` and it copies the session to that account and resumes it with `claude --resume` (just pressing Enter means no).

- **Only this folder's session is checked**: you can run the same account in several windows in different folders and the wrong session is never picked up
- **Your options come along**: e.g. with `cla work --model opus` the next account still uses `--model opus`. The prompt, `--continue` and the old `--resume` are dropped. For an option that takes a value, `--option=value` is the safest way to write it
- **A limited account is skipped until its real reset time**: taken from the error message or from the usage the status line saved (so weekly limits are skipped correctly too). When the reset time is unknown it is skipped for 5 hours (change with `AI_FO_COOLDOWN`, in seconds)
- **Only a used-up plan counts**: a short rate limit (429) or a full context is not treated as a limit

#### Hand over to Codex

Put a Codex account in the order as `codex:<name>`, usually last, so Codex picks up the work when every Claude account is out:

```bash
ai failover order work main codex:main
```

Codex can't open a Claude session, so it starts in the same folder with the conversation so far as its first message: what you and Claude wrote (no tool calls or their output), cut to the last 60 KB (`AI_FO_HANDOFF_MAX`). The first line of that message can be changed with `AI_FO_CODEX_PROMPT`.

- **This sends your conversation to another provider (OpenAI)**, so Codex is never in the chain unless you add it, and you are asked every time (the default is no)
- **The chain ends at Codex**: Codex has no way to report its own limit, so nothing after it is tried
- Starting from Codex has no failover; it only works from a Claude session

### A team of agents

```bash
ai team add codex:main "large refactors, writing tests"
ai team add work2 "docs and small fixes"        # a second Claude account
ai team add gemini "reading a big codebase"     # any agent from ai ls
ai team lead main                               # the one you talk to (default: main)
ai team                                         # start the lead in this folder
ai team ls                                      # the lead and the members
ai team log                                     # what was delegated, and how it went
```

`ai team` starts the lead (your normal Claude Code) with a brief added to its system prompt: who is in the team, what each member is good at, and how to hand work over. The lead does what it is best at itself and runs `ai delegate <member> "<task>"` for the rest. That runs the member headless in the same folder (`claude -p`, `codex exec`, `gemini -p`, ...), prints its reply so the lead can read it, and keeps the full log. Extra args go to the lead, e.g. `ai team --model opus`.

- **Members edit files directly, one at a time per folder**: a second delegation waits for the first, so two agents never change the same files at once
- **The lead stays responsible**: the brief tells it to check what comes back (run the tests, read the diff) and fix or re-delegate
- **A member at its usage limit is refused**, so the lead picks another one. A Claude member that hits its limit while working is marked limited, the same way failover does
- **Everything is logged**: `ai team log` lists past delegations; the full task and reply of each one is in `~/.local/state/ai-hub/team/logs/`
- `ai delegate -b <member> "<task>"` runs in the background (the log file ends with `# done` when it has finished). `ai delegate <member> -` reads a long task from stdin. `ai team brief` prints the brief, to paste into another setup
- Members use their own plan limits, so the team also spreads your usage across accounts

How a member runs headless, added after its saved command: Claude `-p --permission-mode acceptEdits` (`AI_TEAM_CLAUDE_OPTS`), Codex `exec --sandbox workspace-write --skip-git-repo-check` (`AI_TEAM_CODEX_OPTS`), Gemini and Qwen `--approval-mode auto_edit -p` (`AI_TEAM_GEMINI_OPTS`), OpenCode `run`. For any other agent give the command yourself; it gets the task as its last argument: `ai team add kimi "..." "kimi -p"`.

- **Delegating to Codex or another agent sends the task, and the files that agent reads, to its provider**, so a member is only in the team when you add it yourself, and `ai team add` says where the work goes
- A Claude member runs with `acceptEdits`: it can edit files, but a shell command it wants to run is refused unless you allow it (e.g. `AI_TEAM_CLAUDE_OPTS="--permission-mode acceptEdits --allowedTools 'Bash(npm test)'"`). Codex runs in its `workspace-write` sandbox

## Security

- **Account and agent names are always checked**: only letters, digits, `.` `_` `-`, and never starting with `.`, so a name can never become a path like `..`
- **Your files are never deleted**: `cla rm` always moves to the trash
- **Passwords and tokens are left alone**: Keychain is never read and no credential is copied. On macOS you may need to log in once again after `cla mv`, because Claude ties the login to the folder path
- **Other agents' JSON files are edited carefully**: checked to be valid JSON before and after, the original backed up once as `<file>.ai-hub.bak`, and the new file swapped in with a single rename that keeps the original permissions, so a running agent never reads a half-written file
- **`cla` works from inside a Claude window** (e.g. `! cla ls`): `main` always means `~/.claude`, never the account that is currently open. The same goes for `ai codex` and `~/.codex`
- **Shared trust is off by default**, because trusting a folder lets an agent load that folder's own settings, hooks and MCP servers. A repo trusted once becomes trusted in every agent
- **Failover stays within your own Claude accounts unless you add Codex**: a conversation only goes to another provider (Codex / OpenAI) when you put a `codex:` account in the order yourself and answer `y` at that moment
- **Accounts made with `cla add` share settings**, including the hooks and plugins set in `~/.claude/settings.json`. If those settings contain `env` (e.g. `ANTHROPIC_API_KEY`) or `apiKeyHelper`, every account uses the same value. If you don't want that, remove the `settings.json` link in that account's folder and create its own file
- **A team member only gets work after you added it**: the lead already has a shell, so `ai delegate` gives it nothing it could not do by running `codex` itself; it makes the hand-over explicit, logged, and limited to the members you chose
- **Failover always asks before moving a session, and the default is no**: pressing Enter does nothing, only `y` moves it, so a conversation never slips from a work account to a personal one by accident
- **An account removed with `cla rm` keeps its login in `~/.claude-accounts/.trash/`** (on Linux that is `.credentials.json`). To really remove it, delete that folder yourself

## Limitations

- Failover detects a limit from the last error in the Claude Code transcript, and finds the session by the folder name Claude Code gives it. If a future Claude Code changes either, `fo_hit_limit` or `fo_project_keys` in `lib/failover.sh` may need an update
- Claude usage data depends on your Claude Code version passing `rate_limits` to the status line
- The headless options a team member runs with (`claude -p`, `codex exec --sandbox`, `gemini --approval-mode`) are those of the current versions; if one changes, set the `AI_TEAM_*_OPTS` variable or give the member its own command
- No native Windows support yet (use WSL)

## Tests

```bash
bash tests/run.sh
/bin/bash tests/run.sh    # on macOS: also test with bash 3.2
shellcheck --severity=warning bin/ai bin/cla install.sh lib/*.sh scripts/*.sh tests/run.sh
```

Every feature is tested in a throwaway HOME with a fake `claude`; your real config is never touched. On every push, GitHub Actions runs these on Ubuntu and macOS (including bash 3.2) together with shellcheck (`.github/workflows/test.yml`).

## Credits

Inspired by [Ak1Ena/ai-launcher](https://github.com/Ak1Ena/ai-launcher) (MIT). All the code in this repo was written from scratch.

## License

MIT
