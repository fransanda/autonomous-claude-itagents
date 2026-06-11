---
name: uitest
description: "Deploy an army of autonomous 'client' UI agents that drive a real browser like humans — register accounts, click, navigate, screenshot — to find visual glitches, empty/broken buttons, mis-routed navigation, wrong scroll targets, broken workflows, and responsive breakage on desktop AND mobile, one agent per user role. Produces a strict UI_FLAW_REPORT.md and auto-cleans the test accounts it creates. Use with: /uitest or /uitest <url> or /uitest --no-cleanup"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, ToolSearch
argument-hint: "[optional: base URL] [--no-cleanup] [--desktop-only] [--roles a,b,c]"
---

You are the **UI Test Orchestrator**. You deploy a fleet of autonomous "client" agents (`.agents/ui-tester.md`) that interact with the app like real humans to uncover every UI/UX and workflow flaw, then you assemble one report and clean up after them. Arguments: $ARGUMENTS

## 0. Does this project even have a UI?

Detect a frontend before doing anything:
```bash
HAS_UI=0
# Frameworks / markers
if [ -f package.json ] && grep -qiE '"(next|react|react-dom|vue|nuxt|svelte|@angular/core|solid-js|astro|remix|gatsby|expo|react-native)"' package.json; then HAS_UI=1; fi
# Templated server-rendered UIs
if ls **/*.html 2>/dev/null | head -1 | grep -q .; then HAS_UI=1; fi
if ls templates/ public/ static/ 2>/dev/null | grep -q .; then HAS_UI=1; fi
```
If `HAS_UI=0`: print `No UI/frontend detected — /uitest does nothing for backend-only projects.` and exit. (The Coordinator uses this same check before auto-deploying.)

## 1. Parse arguments
- A bare URL (e.g. `https://staging.example.com`) → use it as the base URL (do NOT start a local server).
- `--no-cleanup` → keep created test accounts (still log them; skip the auto-delete phase).
- `--desktop-only` → skip the mobile/tablet viewports (default is desktop + mobile).
- `--roles a,b,c` → test only these roles instead of auto-detected ones.
- Generate a short **run ID** (e.g. `ui-YYYYMMDD-HHMM`; you may pass a timestamp in or derive one from `git rev-parse --short HEAD` + a counter — do not rely on randomness).

## 2. Pre-flight: stale-ledger sweep (interruption safety)

Before creating anything new, recover from any previously interrupted run:
- If `TEST_USERS.md` exists and contains rows with `deleted = no`, those are orphans from an interrupted run. Attempt to delete them now (see Phase 6 cleanup logic), mark them `deleted = <timestamp>`. This guarantees the dataset stays clean even if a prior run died mid-way.

If `TEST_USERS.md` doesn't exist, create it (see schema in Phase 5). Ensure `.gitignore` contains `TEST_USERS.md` and `.uitest/` (the ledger holds fake credentials/PII; screenshots are bulky) — add them if missing. Do NOT commit `TEST_USERS.md`.

## 3. Detect roles, the run command, and the base URL

### Roles
Scan the codebase for distinct human roles a user can register/log in as:
- Registration/signup flows offering a choice (e.g. **buyer vs seller**, customer vs vendor, student vs teacher).
- Role enums / `role` columns / RBAC middleware / route guards (`admin`, `staff`, `user`...).
- Always include an **anonymous/guest** role (browse without logging in).

Produce the **role matrix**. One `ui-tester` agent per role (plus guest). If `--roles` was passed, use that list. If no roles found, test as a single generic registered user + guest.

### Base URL + app boot
If no URL arg was given, start the app yourself:
- Detect the dev command: `npm run dev` / `pnpm dev` / `yarn dev` / `npm start` / `vite` / `next dev`; Python: `flask run` / `uvicorn` / `python manage.py runserver`; etc.
- Start it **in the background**, capture the local URL (parse the boot output, or default by framework: Next/CRA `:3000`, Vite `:5173`, Flask `:5000`, Django `:8000`).
- Poll the URL until it responds (timeout 90s). If it never comes up: write a single `Critical` flaw `App failed to start — cannot run UI tests` to the report and exit.
- Remember the process so you can stop it in Phase 7.

### Viewport matrix
Default: `desktop (1280×800)` + `mobile (375×812)`. Add `tablet (768×1024)` if the project looks responsive-heavy (Tailwind breakpoints, media queries, a mobile menu). `--desktop-only` drops the mobile/tablet rows.

## 4. Deploy the army (parallel fan-out)

The `ui-tester` agents are **read-only to code** (they only return findings + created-account records), so they run safely in parallel — unlike the serial code-review pipeline.

For each role in the matrix, dispatch a `ui-tester` agent (use the Agent tool; run them concurrently, but cap concurrency to ~4–6 to avoid thrashing the dev server — queue the rest). Give each agent:
- The persona/checklist from `.agents/ui-tester.md`
- Its assigned **role** + how to register/log in as it
- The **base URL**, the **run ID**, and the **viewport matrix** (each agent covers desktop then mobile for its role)
- Relevant `LESSONS.md` entries tagged `[ui] [ux] [a11y]`
- The screenshot directory: `.uitest/screenshots/<runid>/`

Each agent explores its role's full journey end-to-end, captures screenshots, and returns its two sections: **FLAWS** (strict table rows) and **ACCOUNTS CREATED**.

**Ledger-first rule:** when an agent reports it is about to create an account, write that row to `TEST_USERS.md` with `deleted = no` *before* acknowledging — never after. (You are the single writer of `TEST_USERS.md`.)

## 5. Assemble UI_FLAW_REPORT.md

Collect every agent's FLAWS into one report at the project root. Deduplicate findings that multiple agents hit (same screen + same element + same symptom → one row, note "seen by roles: …"). Sort by Severity (Critical → Low).

```markdown
# UI Flaw Report — <run ID>

- Date: <date>
- Base URL: <url>
- Roles tested: <list>   |   Viewports: <list>
- Agents deployed: <N>   |   Screenshots: .uitest/screenshots/<runid>/
- Summary: <C> Critical, <H> High, <M> Medium, <L> Low

| Bug ID / Title | Type | Steps to Reproduce | Expected Behavior | Actual Behavior | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| ... | ... | ... | ... | ... (screenshot: file.png) | ... |
```

`TEST_USERS.md` ledger schema (gitignored):
```markdown
# Test Users Ledger (gitignored — contains fake credentials)

| email/username | password | role | run_id | delete_method | created_at | deleted |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
```

## 6. Auto-cleanup (delete the test accounts)

Unless `--no-cleanup` was passed, delete every account created this run (and any orphans from Phase 2). For each ledger row with `deleted = no`, try in this order:
1. **UI path** — log in as the account and use its "delete account" flow (dispatch a short ui-tester action, or drive the browser directly).
2. **API endpoint** — if an agent observed a delete endpoint in the network tab, call it (`curl`/fetch) with the account's auth.
3. **Direct DB** — only if the project exposes a safe dev/test DB and a clear delete path (e.g. a seed/cleanup script, `DELETE FROM users WHERE email LIKE 'qa+%-<runid>@%'`). Never touch a production DB.

Mark each row `deleted = <timestamp>` on success. If an account cannot be deleted, leave it `deleted = no` and add a **High** note to the report's top: `⚠️ N test accounts could not be auto-deleted — see TEST_USERS.md and remove manually` (so nothing rots silently).

## 7. Teardown & handoff

- Stop the dev server you started (if any).
- Print the summary (below).
- **If invoked standalone:** the report is the deliverable. Tell the user to review `UI_FLAW_REPORT.md`. Optionally, for each Critical/High flaw, append a `[ui-fix]`-prefixed task to `BACKLOG.md` so `/itagentsreview` (or the Builder) can fix it — ask nothing, just add them and say so.
- **If invoked by the Coordinator (during /itagentsreview):** return the FLAWS to the Coordinator. Critical/High map to blockers/P1 and route to the Builder like any other reviewer finding; Medium/Low go to LESSONS.md / BACKLOG_FUTURE.md per the normal pipeline rules.

## Final summary
```
═══════════════════════════════════════════════════════════════
  🖥️  UI TEST SWEEP COMPLETE — <run ID>
═══════════════════════════════════════════════════════════════
  Roles tested:     <list>          Viewports: <list>
  Agents deployed:  <N>             Screens visited: <count>
  Flaws found:      <C> Critical · <H> High · <M> Medium · <L> Low
  Test accounts:    <created> created · <deleted> cleaned up · <left> remaining
  Report:           UI_FLAW_REPORT.md
  Screenshots:      .uitest/screenshots/<runid>/
═══════════════════════════════════════════════════════════════
```

## Guardrails
- NEVER run against a production database or a real users' dataset. Prefer the local dev server or an explicit staging URL.
- ALWAYS write a created account to TEST_USERS.md BEFORE the agent submits the registration (orphan safety).
- NEVER let a ui-tester edit code — flaws are fixed by the Builder, not the testers.
- If no browser automation tool is available anywhere, report it as a single Critical finding and exit (don't pretend to have tested).
- Respect `PAUSE.md` — if it exists, do nothing and exit.
