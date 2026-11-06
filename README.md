# ai-hub

**English** · [ภาษาไทย](README.th.md)

One command for all your AI coding agents. Type `ai` to see every agent and account in one list, with bars showing how much of your plan you've used, then pick one to start it in the current folder.

- **Every agent in one list**: Claude Code (several accounts), Codex (several accounts), Antigravity CLI (`agy`), Gemini, Qwen, OpenCode, Kimi, or any CLI you add yourself
- **Plan usage at a glance**: 5-hour and weekly limits with reset times. Bars turn yellow at 60% and red at 90%
- **Several Claude accounts**: add, remove and rename them safely. Removing moves an account to a trash folder, so nothing is really lost
- **Shared folder trust** (off by default): trust a folder once and no agent asks again
- **Several Codex accounts**: the same, with `ai codex`
- **Failover** (off by default): when a Claude account hits its usage limit, continue the same session on the next account, and hand it on to Codex if you add it to the chain
- **A team of agents** (off by default): a lead you talk to does what it is best at and hands the rest to other agents and accounts with `ai delegate`, then checks what they did. Any member can lead a team of its own. Members start lean and reply with short reports to save tokens, and one that hits its limit mid-task hands the task, and what it did so far, to the next free member. Set it up by answering a few questions (`ai team setup`), then just say what you want: `ai do "..."`
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
ai scan            # add agents installed later (claude codex agy gemini qwen opencode kimi)
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

Removing an account (`cla rm`, `ai codex rm`) or an agent (`ai rm`) also takes it out of every team and the failover order.

### Shared folder trust

```bash
ai trust on        # turn on
ai trust off       # turn off
```

Before an agent starts in a folder: if any agent (or any of your Claude accounts) already trusts that folder, the others are set to trust it too. Supports Claude Code, Codex, Gemini and Qwen. The Antigravity CLI keeps no list of trusted folders, so there is nothing to share with it.

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

#### Hand over to Codex or another agent

Put a Codex account in the order as `codex:<name>`, or another agent from `ai ls` (e.g. `agy`, the Antigravity CLI), usually last, so they pick up the work when every Claude account is out:

```bash
ai failover order main work codex:main agy
```

They can't open a Claude session, so each starts in the same folder with the conversation so far as its first message: what you and Claude wrote (no tool calls or their output), cut to the last 60 KB (`AI_FO_HANDOFF_MAX`). The first line of that message can be changed with `AI_FO_CODEX_PROMPT`. When the session was a team lead (`ai team`), the message also says so, and how to see the team.

- **This sends your conversation to another provider**, so Codex or an agent is never in the chain unless you add it, and you are asked every time (the default is no)
- **Your Claude accounts come first**: a Claude account you did not name in the order (also one added later) is tried before the first Codex account or agent
- **The chain goes on after Codex**: when you exit Codex, ai reads its session file (a `codex exec` run, like a team delegation, is never taken for it); if Codex stopped at its plan limit (it is marked limited until its reset), the next member gets the conversation so far, including what Codex wrote. A Claude account after Codex starts a new session with it, and with the options the first session had (the team brief, `--model`, ...)
- **The chain ends at any other agent**: ai can't tell whether it stopped at a limit
- Starting from Codex or an agent has no failover; it only works from a Claude session

### A team of agents

**The easy way**: answer a few questions once, then give the team work in plain words. No other commands to remember:

```bash
ai team setup                      # pick the lead, the members, what each is good at, and extra folders
ai do "add a dark mode and tests for it"   # in your project folder: the lead plans it and hands parts to the team
```

**Let the team decide who does what**: `ai team discover` asks every member at once what it does best (its model, strengths, weaknesses, fast or thorough), adds what ai knows itself (the provider and how much of its plan is used), and has the lead propose each member's role, who leads a sub-team, and who takes over from the lead at its usage limit. You see the proposal and why, and nothing changes until you answer `y` (the old team and failover order are kept as `.bak`). It costs one short request per member plus one for the lead, and only runs when you ask; run it again after adding a member or when plans fill up. `ai team discover <member>...` asks only those: the other members keep their place and role. The proposed order is checked: unknown names are dropped, each member is in it once, and Claude accounts come before Codex and other agents, which only get the conversation as text, at another provider.

`ai team setup` shows numbered lists of your accounts and agents, so you only type numbers (Enter takes the answer in brackets). Run it again any time to add to the team or start a new one (the old one is kept as `.bak`). `ai do` with no team yet starts the setup first; `ai do` with no task asks for one. The lead is allowed to run `ai delegate`, `ai team wait` and `ai team log` without asking you each time, so the team works on its own while you watch.

The commands below are what setup does for you, for when you want to change one thing.

```bash
ai team add codex:main "large refactors, writing tests"
ai team add work2 "docs and small fixes"        # a second Claude account
ai team add agy "reading a big codebase"        # any agent from ai ls
ai team lead main                               # the one you talk to (default: main)
ai team                                         # start the lead in this folder
ai team ls                                      # the lead and the members
ai team log                                     # what was delegated, and how it went
```

`ai team` starts the lead (your normal Claude Code) with a brief added to its system prompt: who is in the team, what each member is good at, and how to hand work over. The lead does what it is best at itself and runs `ai delegate <member> "<task>"` for the rest. That runs the member headless in the same folder (`claude -p`, `codex exec`, `agy -p`, ...), prints its reply so the lead can read it, and keeps the full log. Extra args go to the lead, e.g. `ai team --model opus`.

- **Members edit files directly, one at a time per folder**: a second delegation waits for the first, so two agents never change the same files at once
- **The lead stays responsible**: the brief tells it to check what comes back (run the tests, read the diff) and fix or re-delegate
- **A member at its usage limit is refused**, so the lead picks another one
- **Failover never picks up a team delegation**: a headless Claude run (`claude -p`) in the same folder is skipped when ai looks for the session that hit its limit
- **A member that hits its limit while working hands the task on**: it is marked limited, the same way failover does, and the task goes to the next free member of the same team (in failover order, then team order) with a note to check `git status` first and the end of what the first one wrote (`AI_TEAM_HANDOFF_MAX`, 4 KB). Both runs are in one log, and `ai team wait` waits for the one that finishes and prints only its reply. `AI_TEAM_HANDOFF=0` turns this off
- **A member that prints no reply** (e.g. it was refused a permission it can't ask for) is shown with the end of its log, so the lead sees why
- **Everything is logged**: `ai team log` lists past delegations; the full task and reply of each one is in `~/.local/state/ai-hub/team/logs/`, readable only by you. Logs of finished delegations are deleted after 30 days (`AI_TEAM_KEEP_DAYS`, `0` keeps them); `ai team log --clean` deletes them all now
- `ai delegate -b <member> "<task>"` runs in the background (the log file ends with `# done` when it has finished). `ai delegate <member> -` reads a long task from stdin. `ai team brief` prints the brief, to paste into another setup
- Members use their own plan limits, so the team also spreads your usage across accounts

#### Saving tokens

Every member pays for what it reads and writes, so the team is set up to waste little:

- **Claude members start lean**: only the tools they need to code (`Read Edit Write Bash Glob Grep`), with no MCP servers, skills or plugin commands. Measured on Claude Code 2.1, a member starts with ~7.7k tokens instead of ~24k. `AI_TEAM_CLAUDE_LEAN=''` loads everything again; the lead you talk to always keeps all its tools
- **Short reports**: every task ends with a request for a report of at most 15 lines (done or not, files changed, how it was checked, what is open) and no code, so the lead doesn't read whole files back (`AI_TEAM_REPORT`, empty = off)
- **The brief tells the lead how**: do a few-line change itself, put the files and facts it already knows in the task, check with the tests and `git diff --stat` instead of re-reading files, give a member that leads a team only big multi-part tasks, and don't redo a check that member already did
- A deeper team costs more: each level plans, delegates and checks. Use sub-teams for big tasks, and keep small members in the lead's own team for small jobs

#### Folders outside the project

By default the team works only in the folder you start it in. To let every member (and the lead) also use other folders, e.g. specs or data next to the project:

```bash
ai team access add ~/Documents/specs
ai team access                     # the list
ai team access rm ~/Documents/specs
```

They are passed as `--add-dir` to Claude, Codex and Antigravity, and `--include-directories` to Gemini and Qwen. A member with its own command (`ai team add <m> "..." "<command>"`) gets nothing added. **A folder in this list can be read and changed by every member**, and by the provider each member sends its work to: none of these CLIs has a read-only option. `/` and your home folder are refused; add only what the team needs.

#### Teams inside the team

Any member can lead a team of its own. It hands parts of its task to its own members, checks what they did, and reports back to whoever gave it the task:

```bash
ai team add work "frontend"                               # in the lead's team
ai team add --of work codex:main "component tests"        # in work's own team
ai team add --of work agy "reading the old code"
ai team ls
#   work           frontend
#     └ codex:main   component tests
#     └ agy          reading the old code
```

When `work` is given a task, it also gets a brief of its team, and its `ai delegate` calls go to its own members (a Claude member is allowed to run `ai delegate`, `ai team wait` and `ai team log` for this; other agents get the brief at the top of the task). `ai team rm --of` and `ai team brief --of` work the same way.

- **A task never goes back up**: a member can't delegate to anyone above it in the chain, and it stops after `AI_TEAM_MAX_DEPTH` levels (default 3). At the last level a member gets no team brief and works alone
- **Each team runs one at a time**: a member's team has its own lock, so it never waits for the lock its leader holds. Its leader shouldn't edit the same files while its members work
- **Waiting for background work**: `ai team wait <log>...` prints the replies when they are done. It gives up after 9 minutes with exit 3 (`AI_TEAM_WAIT_STEP`), so an agent's shell call doesn't time out; run it again
- **A Codex member can't lead out of the box**: its `workspace-write` sandbox has no network and can't write ai's logs. `ai team add --of codex:<name>` prints the `AI_TEAM_CODEX_OPTS` that loosen it, if you want that
- `ai team log` shows who delegated each task (`from work`)

How a member runs headless, added after its saved command: Claude `-p --permission-mode acceptEdits` (`AI_TEAM_CLAUDE_OPTS`) and the lean options (`AI_TEAM_CLAUDE_LEAN`), Codex `exec --sandbox workspace-write --skip-git-repo-check` (`AI_TEAM_CODEX_OPTS`), Antigravity `--mode accept-edits --disable-slash-commands -p` (`AI_TEAM_AGY_OPTS`), Gemini and Qwen `--approval-mode auto_edit -p` (`AI_TEAM_GEMINI_OPTS`), OpenCode `run`. For any other agent give the command yourself; it gets the task as its last argument: `ai team add kimi "..." "kimi -p"`.

- **Delegating to Codex or another agent sends the task, and the files that agent reads, to its provider**, so a member is only in the team when you add it yourself, and `ai team add` says where the work goes
- A Claude member runs with `acceptEdits`: it can edit files, but a shell command it wants to run is refused unless you allow it (e.g. `AI_TEAM_CLAUDE_OPTS="--permission-mode acceptEdits --allowedTools 'Bash(npm test)'"`). Codex runs in its `workspace-write` sandbox

## Settings

Everything works without these. Set one for a single run (`AI_TEAM_REPORT='' ai do "..."`) or export it in your shell profile.

| Variable | Default | What it does |
|---|---|---|
| `AI_TEAM_CLAUDE_OPTS` | `--permission-mode acceptEdits` | options of a Claude member (headless) |
| `AI_TEAM_CLAUDE_LEAN` | `--strict-mcp-config --disable-slash-commands --tools=Read,Edit,Write,Bash,Glob,Grep` | a lean Claude member; `''` loads everything |
| `AI_TEAM_CODEX_OPTS` | `--sandbox workspace-write --skip-git-repo-check` | options of a Codex member (`codex exec`) |
| `AI_TEAM_AGY_OPTS` | `--mode accept-edits --disable-slash-commands` | options of an Antigravity member (`agy -p`) |
| `AI_TEAM_GEMINI_OPTS` | `--approval-mode auto_edit` | options of a Gemini or Qwen member |
| `AI_TEAM_REPORT` | a report of at most 15 lines | added to every delegated task; `''` = nothing |
| `AI_TEAM_HANDOFF` | `1` | a member at its limit hands its task on; `0` = off |
| `AI_TEAM_HANDOFF_MAX` | `4000` | bytes of its reply passed on |
| `AI_TEAM_MAX_DEPTH` | `3` | levels of delegation below the lead |
| `AI_TEAM_WAIT` | `3600` | seconds a delegation waits for the folder |
| `AI_TEAM_WAIT_STEP` | `540` | seconds `ai team wait` waits before exit 3 |
| `AI_TEAM_KEEP_DAYS` | `30` | days a finished delegation log is kept; `0` = forever |
| `AI_TEAM_DISCOVER_MAX` | `1500` | bytes of each answer the lead reads in `ai team discover` |
| `AI_FO_COOLDOWN` | `18000` | seconds a limited member is skipped when its reset time is unknown |
| `AI_FO_PROMPT` | "Continue exactly where you left off" | the message a moved Claude session resumes with |
| `AI_FO_CODEX_PROMPT` | "You are taking over..." | the first line of a conversation handed over as text |
| `AI_FO_HANDOFF_MAX` | `60000` | bytes of the conversation handed over as text |
| `AI_NO_FZF` |  | `1` = the numbered menu even when fzf is installed |
| `AI_YES` |  | `1` = answer yes to every question (scripts, tests) |
| `CLA_ROOT`, `CDX_ROOT` | `~/.claude-accounts`, `~/.codex-accounts` | where the extra accounts live |

## Security

- **Account and agent names are always checked**: only letters, digits, `.` `_` `-`, and never starting with `.`, so a name can never become a path like `..`
- **Your files are never deleted**: `cla rm` always moves to the trash
- **Passwords and tokens are left alone**: Keychain is never read and no credential is copied. On macOS you may need to log in once again after `cla mv`, because Claude ties the login to the folder path
- **Other agents' JSON files are edited carefully**: checked to be valid JSON before and after, the original backed up once as `<file>.ai-hub.bak`, and the new file swapped in with a single rename that keeps the original permissions, so a running agent never reads a half-written file
- **`cla` works from inside a Claude window** (e.g. `! cla ls`): `main` always means `~/.claude`, never the account that is currently open. The same goes for `ai codex` and `~/.codex`
- **Shared trust is off by default**, because trusting a folder lets an agent load that folder's own settings, hooks and MCP servers. A repo trusted once becomes trusted in every agent
- **Failover stays within your own Claude accounts unless you add Codex or another agent**: a conversation only goes to another provider when you put a `codex:` account or an agent in the order yourself and answer `y` at that moment. `cla rm` always takes the name out of the order, even when an agent has the same name
- **A team task that a member can't finish at its limit goes to another member of the same team**, which can be another provider: it is in the team because you added it there
- **Accounts made with `cla add` share settings**, including the hooks and plugins set in `~/.claude/settings.json`. If those settings contain `env` (e.g. `ANTHROPIC_API_KEY`) or `apiKeyHelper`, every account uses the same value. If you don't want that, remove the `settings.json` link in that account's folder and create its own file
- **The team lead runs `ai delegate` without asking**, and team members may use the folders in `ai team access`, which they can also change. Keep that list short
- **A team member only gets work after you added it**: the lead already has a shell, so `ai delegate` gives it nothing it could not do by running `codex` itself; it makes the hand-over explicit, logged, and limited to the members you chose
- **Delegation logs are private**: they hold whole tasks and replies (often code), so the team folder is readable only by you (folders `700`, files `600`, older ones are tightened on the next delegation). They are deleted after 30 days (`AI_TEAM_KEEP_DAYS`), or now with `ai team log --clean`
- **Failover always asks before moving a session, and the default is no**: pressing Enter does nothing, only `y` moves it, so a conversation never slips from a work account to a personal one by accident
- **An account removed with `cla rm` keeps its login in `~/.claude-accounts/.trash/`** (on Linux that is `.credentials.json`). To really remove it, delete that folder yourself

## Limitations

- Failover detects a limit from the last error in the Claude Code transcript, and finds the session by the folder name Claude Code gives it. If a future Claude Code changes either, `fo_hit_limit` or `fo_project_keys` in `lib/failover.sh` may need an update. Codex's limit is read from its session files (`$CODEX_HOME/sessions`); `fo_codex_*` in the same file
- A member that hits its limit while working is detected from the last lines it prints (`fo_hit_limit`): Claude and Codex say "usage limit". The wording of the Antigravity CLI could not be checked, so an `agy` member that runs out may fail instead of handing its task on; the lead then sees the error and picks another member
- Claude usage data depends on your Claude Code version passing `rate_limits` to the status line
- The headless options a team member runs with (`claude -p`, `codex exec --sandbox`, `agy -p --mode`, `gemini --approval-mode`) are those of the current versions; if one changes, set the `AI_TEAM_*_OPTS` variable or give the member its own command
- No native Windows support yet (use WSL)

## Tests

```bash
bash tests/run.sh
/bin/bash tests/run.sh    # on macOS: also test with bash 3.2
shellcheck --severity=warning bin/ai bin/cla install.sh lib/*.sh scripts/*.sh tests/run.sh
```

Every feature is tested in a throwaway HOME with a fake `claude`; your real config is never touched. On every push, GitHub Actions runs these on Ubuntu and macOS (including bash 3.2) together with shellcheck (`.github/workflows/test.yml`).

## License

MIT
