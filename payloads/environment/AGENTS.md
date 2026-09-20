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

## Off limits (operator only — propose the change to Simon instead)
- `/data/.openclaw/openclaw.json`, anything under `gateway.*`, the cron store, `/data/.openclaw/agents/`,
  other agents' workspaces, `/app`, `/openclaw`, and stopping or restarting the gateway.
  Past edits of this kind took every agent offline.

## Where to look things up
- Exact-version OpenClaw docs are on the box: `grep -rn '<term>' /openclaw/docs | head`. Read them before
  saying a feature does or does not exist.
