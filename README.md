# ai-hub

**English** · [ภาษาไทย](README.th.md)

One command for all your AI coding agents. Type `ai` to see every agent and account in one list, with bars showing how much of your plan you've used, then pick one to start it in the current folder.

- **Every agent in one list**: Claude Code (several accounts), Codex, Gemini, Qwen, OpenCode, Kimi, or any CLI you add yourself
- **Plan usage at a glance**: 5-hour and weekly limits with reset times. Bars turn yellow at 60% and red at 90%
- **Several Claude accounts**: add, remove and rename them safely. Removing moves an account to a trash folder, so nothing is really lost
- **Shared folder trust** (off by default): trust a folder once and no agent asks again
- **Failover** (off by default): when a Claude account hits its usage limit, continue the same session on the next account
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

Codex usage bars are read from the `CODEX_HOME` in the command; `~/...` and `$HOME/...` both work.

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

## Security

- **Account and agent names are always checked**: only letters, digits, `.` `_` `-`, and never starting with `.`, so a name can never become a path like `..`
- **Your files are never deleted**: `cla rm` always moves to the trash
- **Passwords and tokens are left alone**: Keychain is never read and no credential is copied. On macOS you may need to log in once again after `cla mv`, because Claude ties the login to the folder path
- **Other agents' JSON files are edited carefully**: checked to be valid JSON before and after, the original backed up once as `<file>.ai-hub.bak`, and the new file swapped in with a single rename that keeps the original permissions, so a running agent never reads a half-written file
- **`cla` works from inside a Claude window** (e.g. `! cla ls`): `main` always means `~/.claude`, never the account that is currently open
- **Shared trust is off by default**, because trusting a folder lets an agent load that folder's own settings, hooks and MCP servers. A repo trusted once becomes trusted in every agent
- **Failover only works between your own Claude accounts**: a conversation is never sent to another provider
- **Accounts made with `cla add` share settings**, including the hooks and plugins set in `~/.claude/settings.json`. If those settings contain `env` (e.g. `ANTHROPIC_API_KEY`) or `apiKeyHelper`, every account uses the same value. If you don't want that, remove the `settings.json` link in that account's folder and create its own file
- **Failover always asks before moving a session, and the default is no**: pressing Enter does nothing, only `y` moves it, so a conversation never slips from a work account to a personal one by accident
- **An account removed with `cla rm` keeps its login in `~/.claude-accounts/.trash/`** (on Linux that is `.credentials.json`). To really remove it, delete that folder yourself

## Limitations

- Failover detects a limit from the last error in the Claude Code transcript, and finds the session by the folder name Claude Code gives it. If a future Claude Code changes either, `fo_hit_limit` or `fo_project_keys` in `lib/failover.sh` may need an update
- Claude usage data depends on your Claude Code version passing `rate_limits` to the status line
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
