# Shared Environment Facts (all agents) — operator-managed, do not edit

This file is restored from the deployed image on every container start, so edits here are overwritten.
It is identical for every agent. To change it, ask Simon (it lives in the repo at
`payloads/environment/AGENTS.md`). Put your own notes in your `MEMORY.md` / `AGENTS.md` instead.

## Where you run
- You are one agent on Simon's self-hosted **OpenClaw** gateway. The host is a **Railway container**
  (Debian 12, root), rebuilt from a Docker image on every deploy. It is **not** a VPS or a persistent server.
- **Only `/data` survives a redeploy or restart.** `/usr`, `/etc`, `/var`, `/root`, `/tmp`, `/opt` and
  anything from `apt install` are wiped. If you did not put it under `/data`, assume it will be gone.
- No systemd, no cron daemon, no init services. A background process you start dies with the container —
  nothing restarts it. For scheduled work use OpenClaw cron (ask Simon), not `crontab`.
- No VPN device (`/dev/net/tun`), no `NET_ADMIN`/`NET_RAW`: kernel VPNs, `ping`, raw-socket scans cannot work.
  Inbound is HTTPS to the gateway only; outbound is open from a shared, changing IP.
- The box is shared production: every agent, Simon's Slack/Telegram bots and client credentials live here.
  The volume is small (~4.6 GB) — check `df -h /data` before any large download.

## Installing things so they survive
| You need | Do this | Survives? |
|---|---|---|
| A Node CLI/library | `npm install -g <pkg>` → lands in `/data/npm` (already configured) | Yes |
| A Python package | `python3 -m venv /data/venvs/<name>` then `/data/venvs/<name>/bin/pip install <pkg>`; call it by that absolute path | Yes |
| A standalone binary / script | put it in `/data/bin/` (`chmod 755`), call it by absolute path | Yes |
| Your own data, exports, caches | your workspace, or `/data/<project>/` | Yes |
| A secret or token | `/data/.openclaw/credentials/<name>/` mode 0600 — never in workspace or memory files | Yes |
| An apt/system package, shared library, or a command on the default PATH | **You cannot make this durable yourself.** See below. | No |

**When it needs apt, a system library, or a PATH entry:** do not just `apt install` and move on — it will
silently vanish on the next deploy and the task will break later. Instead:
1. Append a line to `/data/.openclaw/install-requests.md`:
   `- YYYY-MM-DD | <your agent id> | <package/binary> | <why it is needed> | <how you verified it works>`
2. Tell Simon plainly that it needs adding to the image (Dockerfile / manifest) by the operator.
3. A temporary `apt install` to test an approach is fine — say clearly that it is temporary.

## Shell gotchas on this box
- Your Bash tool has a **sanitised PATH**: `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`.
  `/data/npm/bin`, `/data/bin` and venvs are **not** on it — call those by absolute path. `command not found`
  (exit 127) usually means this, not that the tool is missing: check `ls /data/npm/bin /data/bin` first.
- **Any stderr output is treated as a failed command.** Append `2>&1` for chatty tools, and judge by the exit code.
- Put credentials in double quotes — `"$TOKEN"`, never `'$TOKEN'` — or the shell sends the literal name.
  Check your quoting before concluding a credential is missing or invalid.
- Before claiming something is installed, saved, or fixed: verify it with a command, and say so if you could not.

## Slack interactive messages: buttons, selects, tables, charts

Pick the control by whether you are waiting for the answer:
1. **You need the answer to continue this turn** → call `ask_user`: ONE single-select question per call, 2–5 short options. Typed answers count too.
2. **Anything Simon may act on later** (reports, cron output, lists of cards/keywords/tasks) → put **action buttons or selects** on the message, using the action protocol below. Each tap wakes you in that conversation with the action; you then carry it out.

### Building action controls (`message` tool, `presentation`)
- Button: `{"label":"✅ Done","style":"primary","action":{"type":"callback","value":"act:trello.done:hBeoL4zT"}}`
- Select, for 4+ choices: `{"type":"select","placeholder":"Move to…","options":[{"label":"Tomorrow","action":{"type":"callback","value":"act:trello.due:hBeoL4zT:+1d"}}]}`
- **Value format** `act:<system>.<verb>:<arg>:<arg>` — colon-separated, **150 characters max** (longer is cut off). Use stable IDs (card id, campaign id, list id), never titles. The value must be enough on its own: when the tap arrives you may be in a fresh session with no memory of the message.
- **One `buttons` block per item.** When tapped, Slack replaces that row with "✅ <label> selected by @Simon", so a row is one-shot. Put each item's actions in their own row directly under that item's text. Max 5 buttons per row; use a select for longer lists.
- **Too much data for a value?** Save the details to `<your workspace>/actions/<key>.json` (e.g. the proposed todo's title, description, due date) and put only the key in the value: `act:todo.add:20261012-3:today`. When the tap arrives, read that file. Keep keys short and unique per message.
- **Keep your verb list in your own AGENTS.md** under "My action verbs" (e.g. `trello.done:<cardId>` = move the card to Done and mark its due date complete). Reuse those verbs every time so a tap means the same thing tomorrow as today; add a verb there before you first use it.
- Only controls that DO something. No "Open"/link buttons (link the title instead), no `command` buttons, never a callback value without the `act:` prefix.

### Handling a tap
When your turn contains `Slack interaction: {...}` whose `value` or `selectedValues` starts with `act:`:
- That is Simon tapping one of your controls — a real instruction, not a heartbeat. Never ignore it.
- Parse the verb and args, do it with your normal tools, and verify the result.
- Confirm in the same Slack thread with ONE line via the `message` tool (channel `slack`, your own account, target the same conversation, `threadId` = the event's `threadTs`, or its `messageTs` when there is no thread), e.g. "✅ Marked *Send WorkWhile brief* done." On failure say exactly what failed. Then end the turn with `NO_REPLY` so nothing posts twice.
- Several taps can arrive in one turn — handle each. If the verb is unknown or the value is ambiguous, ask in the thread instead of guessing.
- Operator test: `act:test.echo:<text>` → reply in the thread `echo: <text>`.

### Rich layout (use whenever it makes the message easier to read or act on)
- `table` block for tabular data (≤20 columns, ≤100 rows; numbers as numbers) — not monospace code-block tables.
- `chart` block (`bar` / `line` / `area` / `pie`) for trends, pacing and splits: ≤2 charts per message, ≤12 series, ≤20 categories, labels ≤20 chars, title ≤50 chars.
- `context` for small metadata (dates, sources), `divider` between sections, `text` for body sections.
- Link titles inline `[Title](url)`; never bare URLs.
- Long reports: a short top-level summary message, then each section as a reply in its thread.

## Off limits (operator only — propose the change to Simon instead)
- `/data/.openclaw/openclaw.json`, anything under `gateway.*`, the cron store, `/data/.openclaw/agents/`,
  other agents' workspaces, `/app`, `/openclaw`, and stopping or restarting the gateway.
  Past edits of this kind took every agent offline.

## Where to look things up
- Exact-version OpenClaw docs are on the box: `grep -rn '<term>' /openclaw/docs | head`. Read them before
  saying a feature does or does not exist.
