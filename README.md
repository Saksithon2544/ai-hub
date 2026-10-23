# ai-hub

คำสั่งเดียวสำหรับ AI coding agent ทุกตัว พิมพ์ `ai` แล้วจะเห็นรายชื่อ agent และบัญชีทั้งหมด พร้อมแถบแสดงโควตาที่ใช้ไป จากนั้นเลือกตัวที่ต้องการเพื่อเปิดในโฟลเดอร์ปัจจุบัน

- **ทุก agent ในรายการเดียว** Claude Code (หลายบัญชี), Codex, Gemini, Qwen, OpenCode, Kimi หรือ CLI อะไรก็ได้ที่เพิ่มเอง
- **ดูโควตาได้ทันที** แสดงลิมิต 5 ชั่วโมงและรายสัปดาห์พร้อมเวลารีเซ็ต แถบเป็นสีเหลืองที่ 60% และสีแดงที่ 90%
- **หลายบัญชี Claude** เพิ่ม ลบ เปลี่ยนชื่อได้อย่างปลอดภัย การลบคือย้ายไปถังขยะ ไม่มีอะไรหายจริง
- **แชร์ folder trust** (ปิดไว้เป็นค่าเริ่มต้น) trust โฟลเดอร์ครั้งเดียว agent ทุกตัวไม่ต้องถามซ้ำ
- **Failover** (ปิดไว้เป็นค่าเริ่มต้น) เมื่อบัญชี Claude ชนลิมิต ทำงานต่อใน session เดิมบนบัญชีถัดไป
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
```

รายชื่อเก็บใน `~/.config/ai-hub/providers` บรรทัดละหนึ่งตัว คำสั่งทำงานเหมือน shell alias จึงใส่ `VAR=value` นำหน้าได้ เช่น Codex บัญชีที่สอง:

```bash
ai add codex-work "CODEX_HOME=~/.codex-work codex" "Codex (work)"
```

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

เมื่อเห็นข้อความว่าชนลิมิตใน Claude ให้ออกจาก Claude (`/exit` หรือ ctrl-c สองครั้ง) แล้ว `ai` จะถามว่าจะทำงานต่อในบัญชีถัดไปไหม ถ้าตอบตกลง จะคัดลอก session ไปบัญชีนั้นแล้วเปิดด้วย `claude --resume` บัญชีที่ชนลิมิตจะถูกข้ามไป 5 ชั่วโมง (เปลี่ยนได้ด้วย `AI_FO_COOLDOWN` หน่วยวินาที)

## เรื่องความปลอดภัย

- **ชื่อบัญชีและชื่อ agent ถูกตรวจทุกครั้ง** ใช้ได้เฉพาะตัวอักษร ตัวเลข `.` `_` `-` และห้ามขึ้นต้นด้วย `.` จึงไม่มีทางกลายเป็น path อย่าง `..`
- **ไม่มีการลบไฟล์ของผู้ใช้** `cla rm` ย้ายไปถังขยะเสมอ
- **ไม่ยุ่งกับรหัสผ่านหรือ token** ไม่อ่าน Keychain ไม่คัดลอก credential บน macOS หลัง `cla mv` อาจต้องล็อกอินใหม่หนึ่งครั้ง เพราะ Claude เก็บการล็อกอินผูกกับ path ของโฟลเดอร์
- **ไฟล์ JSON ของ agent อื่นแก้อย่างระวัง** ตรวจว่าเป็น JSON ที่ถูกต้องก่อนและหลังแก้ สำรองไฟล์เดิมไว้ที่ `<ไฟล์>.ai-hub.bak` หนึ่งครั้ง
- **การแชร์ trust ปิดไว้เป็นค่าเริ่มต้น** เพราะการ trust โฟลเดอร์ทำให้ agent โหลด settings, hooks และ MCP server ของโฟลเดอร์นั้น repo ที่ trust ครั้งเดียวจะถูก trust ในทุก agent
- **Failover ทำงานเฉพาะระหว่างบัญชี Claude ของคุณเอง** บทสนทนาไม่ถูกส่งไปผู้ให้บริการรายอื่น
- **บัญชีที่สร้างด้วย `cla add` ใช้ settings ร่วมกัน** รวมถึง hooks และ plugins ที่ตั้งไว้ใน `~/.claude/settings.json` ด้วย

## ข้อจำกัด

- Failover ตรวจลิมิตจากข้อความ error สุดท้ายใน transcript ของ Claude Code ถ้า Claude Code เปลี่ยนรูปแบบข้อความในอนาคต อาจต้องปรับ `fo_hit_limit` ใน `lib/failover.sh`
- ข้อมูลโควตาของ Claude ขึ้นกับว่า Claude Code เวอร์ชันที่ใช้ส่ง `rate_limits` ให้ status line หรือไม่
- ยังไม่รองรับ Windows แบบ native (ใช้ผ่าน WSL ได้)

## ทดสอบ

```bash
bash tests/run.sh
/bin/bash tests/run.sh    # บน macOS: ทดสอบกับ bash 3.2 ด้วย
```

ทดสอบทุกฟีเจอร์ใน HOME ชั่วคราวพร้อม `claude` ปลอม ไม่แตะไฟล์ตั้งค่าจริงของคุณ

## เครดิต

แนวคิดมาจาก [Ak1Ena/ai-launcher](https://github.com/Ak1Ena/ai-launcher) (MIT) โค้ดใน repo นี้เขียนขึ้นใหม่ทั้งหมด

## License

MIT
