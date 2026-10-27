# ai-hub

[English](README.md) · **ภาษาไทย**

คำสั่งเดียวสำหรับ AI coding agent ทุกตัว พิมพ์ `ai` แล้วจะเห็นรายชื่อ agent และบัญชีทั้งหมด พร้อมแถบแสดงโควตาที่ใช้ไป จากนั้นเลือกตัวที่ต้องการเพื่อเปิดในโฟลเดอร์ปัจจุบัน

- **ทุก agent ในรายการเดียว** Claude Code (หลายบัญชี), Codex, Gemini, Qwen, OpenCode, Kimi หรือ CLI อะไรก็ได้ที่เพิ่มเอง
- **ดูโควตาได้ทันที** แสดงลิมิต 5 ชั่วโมงและรายสัปดาห์พร้อมเวลารีเซ็ต แถบเป็นสีเหลืองที่ 60% และสีแดงที่ 90%
- **หลายบัญชี Claude** เพิ่ม ลบ เปลี่ยนชื่อได้อย่างปลอดภัย การลบคือย้ายไปถังขยะ ไม่มีอะไรหายจริง
- **แชร์ folder trust** (ปิดไว้เป็นค่าเริ่มต้น) trust โฟลเดอร์ครั้งเดียว agent ทุกตัวไม่ต้องถามซ้ำ
- **หลายบัญชี Codex** ทำได้แบบเดียวกันด้วย `ai codex`
- **Failover** (ปิดไว้เป็นค่าเริ่มต้น) เมื่อบัญชี Claude ชนลิมิต ทำงานต่อใน session เดิมบนบัญชีถัดไป และส่งงานต่อให้ Codex ได้ถ้าเพิ่ม Codex เข้าไปในลำดับ
- **ทีม agent** (ปิดไว้เป็นค่าเริ่มต้น) หัวหน้าทีมที่คุณคุยด้วยจะทำงานที่ตัวเองถนัด ส่วนที่เหลือกระจายให้ agent และบัญชีอื่นด้วย `ai delegate` แล้วตรวจผลงานที่ได้กลับมา
- **ไม่เรียก API ใดๆ** ข้อมูลโควตาอ่านจากไฟล์ที่ agent เขียนไว้ในเครื่องอยู่แล้ว

รองรับ macOS, Linux และ WSL เขียนด้วย bash ล้วน (ใช้ได้กับ bash 3.2 ที่มากับ macOS)

## ติดตั้ง

ดาวน์โหลด repo นี้ (ปุ่ม **Code → Download ZIP**) แตกไฟล์ไว้ที่ไหนก็ได้ เช่น `~/ai-hub` แล้วรัน:

```bash
cd ~/ai-hub
bash install.sh        # สร้างลิงก์ ai และ cla ไว้ใน ~/.local/bin
bash tests/run.sh      # ทดสอบก่อนใช้จริง ต้องขึ้น "all passed"
```

เครื่องมือเสริม (ไม่ติดตั้งก็ใช้ได้ แต่ฟีเจอร์บางอย่างจะปิด):

| เครื่องมือ | เพิ่มอะไร |
|---|---|
| [jq](https://jqlang.org) | แถบโควตา, แชร์ trust, failover (มีใน macOS 15+ แล้ว) |
| [fzf](https://github.com/junegunn/fzf) | ตัวเลือกแบบค้นหาได้ ถ้าไม่มีจะเป็นเมนูตัวเลข |

```bash
brew install jq fzf              # macOS
sudo apt install jq fzf          # Linux / WSL
```

### เปิดการแสดงโควตาของ Claude

Claude Code ส่งข้อมูลโควตาให้ status line ใส่ใน `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh" }
```

ถ้ามี status line เดิมอยู่แล้ว ใส่คำสั่งเดิมต่อท้ายได้ สคริปต์จะส่งข้อมูลต่อให้:

```json
"statusLine": { "type": "command", "command": "bash ~/ai-hub/scripts/statusline-usage.sh my-statusline --flag" }
```

ตัวเลขจะขึ้นหลัง Claude ตอบครั้งถัดไป และมีเฉพาะแพ็กเกจ Pro/Max เท่านั้น บัญชีที่สร้างด้วย `cla add` ใช้ `settings.json` ร่วมกัน จึงตั้งครั้งเดียวพอ

## ใช้งาน

```bash
ai                 # เลือก agent แล้วเปิดในโฟลเดอร์นี้
ai --resume        # อาร์กิวเมนต์ที่เหลือส่งต่อให้ agent
ai ls              # ดูรายชื่อ agent และคำสั่งที่ใช้เปิด
ai add aider "aider --model sonnet" "Aider"
ai edit claude "claude --model opus"
ai rm aider
ai scan            # เพิ่ม agent ที่เพิ่งติดตั้งทีหลัง (claude codex gemini qwen opencode kimi)
```

รายชื่อเก็บใน `~/.config/ai-hub/providers` บรรทัดละหนึ่งตัว ตอนรันครั้งแรกจะใส่ agent ที่ติดตั้งอยู่ให้อัตโนมัติ ถ้าติดตั้งตัวใหม่ทีหลังให้รัน `ai scan` คำสั่งทำงานเหมือน shell alias จึงใส่ `VAR=value` นำหน้าได้ เช่น Codex บัญชีที่สอง:

```bash
ai add codex-work "CODEX_HOME=~/.codex-work codex" "Codex (work)"
```

แถบโควตาของ Codex อ่านจาก `CODEX_HOME` ในคำสั่ง เขียนเป็น `~/...` หรือ `$HOME/...` ก็ได้ ถ้ามี Codex หลายบัญชี ใช้ `ai codex` ด้านล่างจะง่ายกว่า

### หลายบัญชี Claude

```bash
cla add work       # สร้างบัญชี (settings, skills, plugins ใช้ร่วมกับบัญชีหลัก)
cla work           # เปิดบัญชีนั้น ครั้งแรก Claude จะให้ล็อกอิน
cla main           # บัญชีปกติ (~/.claude)
cla                # เลือกบัญชีจากรายการ
cla ls             # ดูว่าแต่ละบัญชีล็อกอินด้วยอีเมลอะไร
cla mv work job    # เปลี่ยนชื่อ
cla rm job         # ย้ายไป ~/.claude-accounts/.trash/ (ไม่ลบจริง)
```

### หลายบัญชี Codex

```bash
ai codex add work       # สร้างบัญชี (config.toml, AGENTS.md และ prompts ใช้ร่วมกับบัญชีหลัก)
ai codex work login     # ล็อกอินบัญชีนั้น (อาร์กิวเมนต์หลังชื่อบัญชีส่งต่อให้ codex)
ai codex work           # เปิดบัญชีนั้น
ai codex main           # บัญชีปกติ (~/.codex)
ai codex                # เลือกบัญชี Codex จากรายการ
ai codex ls             # ดูว่าบัญชีไหนล็อกอินแล้ว
ai codex mv work job    # เปลี่ยนชื่อ
ai codex rm job         # ย้ายไป ~/.codex-accounts/.trash/ (ไม่ลบจริง)
```

แต่ละบัญชีมี `CODEX_HOME` ของตัวเองใน `~/.codex-accounts/<ชื่อ>` (เปลี่ยนโฟลเดอร์ได้ด้วย `CDX_ROOT`) และขึ้นในตัวเลือกของ `ai` พร้อมแถบโควตาของตัวเอง ข้อมูลล็อกอินอยู่ในโฟลเดอร์ของบัญชีนั้น ai-hub แค่เช็คว่ามีไฟล์อยู่ ไม่เคยเปิดอ่าน

### แชร์ folder trust

```bash
ai trust on        # เปิด
ai trust off       # ปิด
```

ก่อนเปิด agent ในโฟลเดอร์ใด ถ้ามี agent ตัวไหน (หรือบัญชี Claude ใด) trust โฟลเดอร์นั้นอยู่แล้ว ตัวอื่นจะถูกตั้งให้ trust ด้วย รองรับ Claude Code, Codex, Gemini และ Qwen

### Failover

```bash
ai failover on
ai failover order work main personal   # ลำดับที่จะลอง บนสุดก่อน
ai failover status
ai failover clear work                  # ล้างสถานะติดลิมิต
```

เมื่อเห็นข้อความว่าชนลิมิตใน Claude ให้ออกจาก Claude (`/exit` หรือ ctrl-c สองครั้ง) แล้ว `ai` จะถามว่าจะทำงานต่อในบัญชีถัดไปไหม ถ้าตอบ `y` จะคัดลอก session ไปบัญชีนั้นแล้วเปิดด้วย `claude --resume` (กด Enter เฉยๆ คือไม่ย้าย)

- **ตรวจเฉพาะ session ของโฟลเดอร์นี้** เปิดบัญชีเดียวกันหลายหน้าต่างในโฟลเดอร์ต่างกันได้ ไม่หยิบ session ผิดตัว
- **ตัวเลือกที่พิมพ์ไว้ตามไปด้วย** เช่น `cla work --model opus` พอย้ายบัญชีจะยังใช้ `--model opus` ส่วน prompt, `--continue` และ `--resume` เดิมจะถูกตัดออก ถ้าตัวเลือกไหนมีค่าตามหลัง ให้เขียนแบบ `--option=value` จะชัวร์ที่สุด
- **บัญชีที่ชนลิมิตจะถูกข้ามจนถึงเวลารีเซ็ตจริง** ใช้เวลาจากข้อความ error หรือจากข้อมูลโควตาที่ status line บันทึกไว้ (ลิมิตรายสัปดาห์ก็ข้ามได้ถูก) ถ้าไม่รู้เวลารีเซ็ตจะข้ามไป 5 ชั่วโมง (เปลี่ยนได้ด้วย `AI_FO_COOLDOWN` หน่วยวินาที)
- **นับเฉพาะโควตาของแพลนที่หมด** rate limit ชั่วคราว (429) หรือ context เต็ม ไม่ถือว่าชนลิมิต

#### ส่งงานต่อให้ Codex

ใส่บัญชี Codex ในลำดับเป็น `codex:<ชื่อ>` ปกติไว้ท้ายสุด เพื่อให้ Codex รับงานต่อเมื่อบัญชี Claude หมดทุกบัญชี:

```bash
ai failover order work main codex:main
```

Codex เปิด session ของ Claude ไม่ได้ จึงเปิดในโฟลเดอร์เดิม โดยส่งบทสนทนาที่ผ่านมาไปเป็นข้อความแรก ส่งเฉพาะสิ่งที่คุณกับ Claude พิมพ์ ไม่รวมการเรียก tool และผลลัพธ์ และตัดเหลือ 60 KB ล่าสุด (`AI_FO_HANDOFF_MAX`) ข้อความเปิดของบทสนทนาที่ส่งไปเปลี่ยนได้ด้วย `AI_FO_CODEX_PROMPT`

- **เป็นการส่งบทสนทนาไปผู้ให้บริการอีกราย (OpenAI)** Codex จึงไม่อยู่ในลำดับจนกว่าคุณจะเพิ่มเอง และระบบถามทุกครั้ง (ค่าเริ่มต้นคือไม่ส่ง)
- **Codex เป็นปลายทางสุดท้าย** Codex บอกไม่ได้ว่าตัวเองชนลิมิต จึงไม่ลองบัญชีถัดจากนั้น
- ถ้าเริ่มจาก Codex จะไม่มี failover ใช้ได้เฉพาะตอนเริ่มจาก session ของ Claude

### ทีม agent

```bash
ai team add codex:main "refactor ใหญ่ เขียน test"
ai team add work2 "เขียนเอกสาร แก้จุดเล็กๆ"        # บัญชี Claude ที่สอง
ai team add gemini "อ่าน codebase ขนาดใหญ่"         # agent ตัวไหนก็ได้จาก ai ls
ai team lead main                                  # หัวหน้าทีม คนที่คุณคุยด้วย (ค่าเริ่มต้น: main)
ai team                                            # เปิดหัวหน้าทีมในโฟลเดอร์นี้
ai team ls                                         # ดูหัวหน้าและสมาชิก
ai team log                                        # ดูว่ากระจายงานอะไรไปบ้าง ผลเป็นอย่างไร
```

`ai team` เปิดหัวหน้าทีม (Claude Code ตามปกติ) พร้อมแนบคำชี้แจงเข้าไปใน system prompt ว่าในทีมมีใครบ้าง แต่ละคนถนัดอะไร และจะส่งงานอย่างไร หัวหน้าจะทำงานที่ตัวเองถนัดเอง ส่วนที่เหลือจะรัน `ai delegate <สมาชิก> "<งาน>"` ซึ่งเปิดสมาชิกคนนั้นแบบไม่มีหน้าจอ (headless) ในโฟลเดอร์เดียวกัน (`claude -p`, `codex exec`, `gemini -p`, ...) พิมพ์คำตอบกลับมาให้หัวหน้าอ่านต่อ และเก็บ log ฉบับเต็มไว้ อาร์กิวเมนต์อื่นส่งต่อให้หัวหน้า เช่น `ai team --model opus`

- **สมาชิกแก้ไฟล์ได้เอง แต่ทีละคนต่อโฟลเดอร์** งานที่สองจะรอให้งานแรกเสร็จก่อน agent สองตัวจึงไม่มีทางแก้ไฟล์เดียวกันพร้อมกัน
- **หัวหน้ายังรับผิดชอบผลงาน** คำชี้แจงบอกให้หัวหน้าตรวจสิ่งที่ได้กลับมา (รัน test ดู diff) แล้วแก้เองหรือส่งกลับไปทำใหม่
- **สมาชิกที่ชนลิมิตจะถูกปฏิเสธ** หัวหน้าจึงเลือกคนอื่นแทน สมาชิก Claude ที่ชนลิมิตระหว่างทำงานจะถูกบันทึกว่าติดลิมิตแบบเดียวกับ failover
- **ทุกอย่างมี log** `ai team log` แสดงรายการงานที่เคยกระจายไป ส่วนงานและคำตอบฉบับเต็มอยู่ใน `~/.local/state/ai-hub/team/logs/`
- `ai delegate -b <สมาชิก> "<งาน>"` รันเบื้องหลัง (ไฟล์ log จะลงท้ายด้วย `# done` เมื่อเสร็จ) `ai delegate <สมาชิก> -` รับงานยาวๆ จาก stdin และ `ai team brief` พิมพ์คำชี้แจงออกมา เผื่อเอาไปใช้กับ setup อื่น
- สมาชิกแต่ละคนใช้โควตาของตัวเอง การตั้งทีมจึงช่วยกระจายการใช้งานไปหลายบัญชีด้วย

วิธีรันสมาชิกแบบ headless ซึ่งต่อท้ายคำสั่งที่บันทึกไว้: Claude `-p --permission-mode acceptEdits` (`AI_TEAM_CLAUDE_OPTS`), Codex `exec --sandbox workspace-write --skip-git-repo-check` (`AI_TEAM_CODEX_OPTS`), Gemini และ Qwen `--approval-mode auto_edit -p` (`AI_TEAM_GEMINI_OPTS`), OpenCode `run` ส่วน agent อื่นให้ระบุคำสั่งเอง โดยงานจะถูกส่งเป็นอาร์กิวเมนต์ตัวสุดท้าย: `ai team add kimi "..." "kimi -p"`

- **การส่งงานให้ Codex หรือ agent อื่น คือการส่งงานและไฟล์ที่ agent นั้นอ่านไปยังผู้ให้บริการของมัน** สมาชิกจึงอยู่ในทีมก็ต่อเมื่อคุณเพิ่มเอง และ `ai team add` จะบอกว่างานไปที่ไหน
- สมาชิก Claude รันด้วย `acceptEdits` คือแก้ไฟล์ได้ แต่คำสั่ง shell ที่มันอยากรันจะถูกปฏิเสธจนกว่าคุณจะอนุญาต (เช่น `AI_TEAM_CLAUDE_OPTS="--permission-mode acceptEdits --allowedTools 'Bash(npm test)'"`) ส่วน Codex รันใน sandbox แบบ `workspace-write`

## เรื่องความปลอดภัย

- **ชื่อบัญชีและชื่อ agent ถูกตรวจทุกครั้ง** ใช้ได้เฉพาะตัวอักษร ตัวเลข `.` `_` `-` และห้ามขึ้นต้นด้วย `.` จึงไม่มีทางกลายเป็น path อย่าง `..`
- **ไม่มีการลบไฟล์ของผู้ใช้** `cla rm` ย้ายไปถังขยะเสมอ
- **ไม่ยุ่งกับรหัสผ่านหรือ token** ไม่อ่าน Keychain ไม่คัดลอก credential บน macOS หลัง `cla mv` อาจต้องล็อกอินใหม่หนึ่งครั้ง เพราะ Claude เก็บการล็อกอินผูกกับ path ของโฟลเดอร์
- **ไฟล์ JSON ของ agent อื่นแก้อย่างระวัง** ตรวจว่าเป็น JSON ที่ถูกต้องก่อนและหลังแก้ สำรองไฟล์เดิมไว้ที่ `<ไฟล์>.ai-hub.bak` หนึ่งครั้ง และสลับไฟล์ใหม่เข้าไปในครั้งเดียว (rename) โดยคงสิทธิ์ไฟล์เดิมไว้ agent ที่รันอยู่จึงไม่มีทางอ่านเจอไฟล์ที่เขียนไปครึ่งเดียว
- **รัน `cla` จากในหน้าต่าง Claude ได้** (เช่น `! cla ls`) `main` ยังหมายถึง `~/.claude` เสมอ ไม่สับสนกับบัญชีที่กำลังเปิดอยู่ `ai codex` กับ `~/.codex` ก็เช่นกัน
- **การแชร์ trust ปิดไว้เป็นค่าเริ่มต้น** เพราะการ trust โฟลเดอร์ทำให้ agent โหลด settings, hooks และ MCP server ของโฟลเดอร์นั้น repo ที่ trust ครั้งเดียวจะถูก trust ในทุก agent
- **Failover อยู่ในบัญชี Claude ของคุณเอง เว้นแต่จะเพิ่ม Codex** บทสนทนาจะไปถึงผู้ให้บริการอีกราย (Codex / OpenAI) ก็ต่อเมื่อคุณใส่บัญชี `codex:` ในลำดับเอง และตอบ `y` ตอนที่ระบบถามเท่านั้น
- **บัญชีที่สร้างด้วย `cla add` ใช้ settings ร่วมกัน** รวมถึง hooks และ plugins ที่ตั้งไว้ใน `~/.claude/settings.json` ด้วย ถ้าใน settings มี `env` (เช่น `ANTHROPIC_API_KEY`) หรือ `apiKeyHelper` ทุกบัญชีจะใช้ค่านั้นเหมือนกันหมด ถ้าไม่ต้องการ ให้ลบลิงก์ `settings.json` ในโฟลเดอร์บัญชีนั้นแล้วสร้างไฟล์ของตัวเองแทน
- **สมาชิกทีมจะได้รับงานก็ต่อเมื่อคุณเพิ่มเข้าทีมเอง** หัวหน้ามี shell อยู่แล้ว `ai delegate` จึงไม่ได้ให้สิทธิ์อะไรเพิ่มจากการรัน `codex` เองโดยตรง แต่ทำให้การส่งงานชัดเจน มี log และจำกัดอยู่แค่สมาชิกที่คุณเลือก
- **Failover ถามก่อนย้าย session เสมอ และค่าเริ่มต้นคือ "ไม่"** กด Enter เฉยๆ จะไม่ย้าย ต้องพิมพ์ `y` เท่านั้น เพื่อกันไม่ให้บทสนทนาหลุดจากบัญชีงานไปบัญชีส่วนตัวโดยไม่ตั้งใจ
- **บัญชีที่ `cla rm` ยังเก็บข้อมูลล็อกอินไว้ใน `~/.claude-accounts/.trash/`** (บน Linux คือ `.credentials.json`) ถ้าต้องการลบจริง ให้ลบโฟลเดอร์นั้นเอง

## ข้อจำกัด

- Failover ตรวจลิมิตจากข้อความ error สุดท้ายใน transcript ของ Claude Code และหา session จากชื่อโฟลเดอร์ที่ Claude Code ตั้งให้ ถ้า Claude Code เปลี่ยนรูปแบบสองอย่างนี้ในอนาคต อาจต้องปรับ `fo_hit_limit` และ `fo_project_keys` ใน `lib/failover.sh`
- ข้อมูลโควตาของ Claude ขึ้นกับว่า Claude Code เวอร์ชันที่ใช้ส่ง `rate_limits` ให้ status line หรือไม่
- ตัวเลือก headless ที่ใช้รันสมาชิกทีม (`claude -p`, `codex exec --sandbox`, `gemini --approval-mode`) อิงจากเวอร์ชันปัจจุบัน ถ้าตัวไหนเปลี่ยน ให้ตั้งตัวแปร `AI_TEAM_*_OPTS` หรือระบุคำสั่งของสมาชิกคนนั้นเอง
- ยังไม่รองรับ Windows แบบ native (ใช้ผ่าน WSL ได้)

## ทดสอบ

```bash
bash tests/run.sh
/bin/bash tests/run.sh    # บน macOS: ทดสอบกับ bash 3.2 ด้วย
shellcheck --severity=warning bin/ai bin/cla install.sh lib/*.sh scripts/*.sh tests/run.sh
```

ทดสอบทุกฟีเจอร์ใน HOME ชั่วคราวพร้อม `claude` ปลอม ไม่แตะไฟล์ตั้งค่าจริงของคุณ ทุกครั้งที่ push GitHub Actions จะรันชุดนี้บน Ubuntu และ macOS (รวม bash 3.2) พร้อม shellcheck ให้ (`.github/workflows/test.yml`)

## License

MIT
