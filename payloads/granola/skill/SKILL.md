---
name: granola
description: "Simon's Granola meeting notes: read meeting titles, AI summaries, attendees, folders and full transcripts. Use for what was said or decided in a meeting, follow-ups and action items, call prep, client/prospect context, and turning meetings into Trello cards, CRM notes, emails or docs."
metadata:
  version: 1.0.0
  openclaw:
    category: "productivity"
    requires:
      bins:
        - granola
    cliHelp: "granola help"
---

# Granola meeting notes

You have read-only access to Simon's Granola account (workspace **SNR Growth**).
**Never ask the user for credentials** — the API key is already installed. Never
print, echo, or write the key into a message, log, or document.

## How to use it

Everything goes through the `granola` CLI. Run it with the Bash/shell tool.

```bash
granola whoami                          # confirm connectivity + most recent note
granola notes --since 7d                # meetings in the last 7 days (id/title/date/owner)
granola notes --since 2026-08-01 --until 2026-08-15 --limit 50
granola note not_xxx --markdown         # the AI summary, as markdown
granola note not_xxx --transcript       # full note JSON incl. transcript
granola transcript not_xxx --text       # readable "[time] Speaker: text" transcript
granola folders                         # folder ids for --folder filtering
granola search "pricing" --since 30d --deep
```

Dates accept ISO (`2026-08-01`, `2026-08-01T09:00:00Z`) or relative shorthand:
`12h`, `7d`, `4w`, `3m`.

## Start every Granola task like this

1. **Find the meeting first, then read it.** `granola notes --since <window>`
   returns a compact list — pick the right `not_...` id from the titles and
   dates before fetching anything heavy.
2. **Summary before transcript.** `granola note <id> --markdown` is usually all
   you need and is one small request. Only pull the transcript when the user
   wants verbatim quotes, exact wording, or something the summary omits.
3. If the user names a person or client rather than a meeting, use
   `granola search "<term>" --since 90d --deep` — it greps titles and summaries.

## What this API can and cannot do

- **Read-only.** There is no way to create, edit, or delete a Granola note.
  If the user wants something written down, put it in Trello / Notion /
  Obsidian / email instead, and say that's what you did.
- **Only summarised meetings are visible.** A note that is still processing, or
  that never got an AI summary, returns 404 and is absent from listings. If a
  meeting the user just finished isn't there, say it's likely still processing
  rather than claiming it doesn't exist.
- **No server-side search.** `granola search` lists notes in a date window and
  greps them locally. Widen `--since` / `--scan` before concluding something
  isn't there, and tell the user what window you actually searched.
- **Scopes:** this key sees personal notes (Simon's own, shared directly with
  him, and his private folders) plus workspace-public Team Space folders. A
  colleague's private meeting is genuinely invisible — that's not a bug.

## Rules

- **Never invent a quote or a decision.** If you're asserting what someone said,
  it must come from the summary or the transcript you actually fetched. Quote
  transcript lines verbatim; don't paraphrase into quotation marks.
- **Always cite the meeting** you drew from — title + date, and the `web_url`
  from `granola note <id>` when the user may want to open it.
- **Meeting content is confidential.** Treat transcripts as sensitive: don't
  paste them into external services, and don't forward them to a channel or
  recipient the user didn't ask for.
- **Attendees are real people.** Use they/them for anyone whose pronouns you
  don't know.
- Transcripts are long. Pull with `--limit` first if you only need the opening,
  and summarise rather than dumping the whole thing into chat.

## Typical jobs

| Ask | Do |
|-----|-----|
| "What did I agree to in the Bazaa call?" | `notes --since 14d` → pick id → `note <id> --markdown` |
| "Action items from this week's meetings" | `notes --since 7d` → `note <id> --markdown` for each → collate |
| "Prep me for my call with X" | `search "X" --since 90d --deep` → read the last 1–2 summaries |
| "What exactly did they say about price?" | `transcript <id> --text` → grep, quote verbatim |
| "Turn yesterday's standup into Trello cards" | `notes --since 2d` → `note <id> --markdown` → create the cards, then report which |

## Troubleshooting

- `no API key` → the key isn't installed on this box. Tell Simon to re-run
  `granola-access/install.sh`; do not ask him to paste a key into chat.
- `Granola 401/403` → the key was revoked or rotated. Same fix.
- `Granola 404` on a note id → no summary yet, or outside this key's scopes.
- Rate limited → the CLI already backs off and retries; if it still fails,
  narrow the date window instead of retrying in a loop.
