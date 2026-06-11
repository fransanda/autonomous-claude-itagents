---
name: uitest
description: "Deploy an army of autonomous 'client' UI agents that drive a real browser like humans — register accounts, click, navigate, screenshot — to find visual glitches, empty/broken buttons, mis-routed navigation, wrong scroll targets, broken workflows, and responsive breakage on desktop AND mobile, one agent per user role. Full sweep by default; scope a partial review with --pages/--roles/--desktop-only/--smoke. Produces a strict UI_FLAW_REPORT.md and auto-cleans the test accounts it creates. Use with: /uitest or /uitest <url> or /uitest --pages /checkout,/cart or /uitest --smoke"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, ToolSearch
argument-hint: "[base URL] [--pages a,b] [--roles a,b] [--desktop-only] [--smoke] [--no-cleanup] [--keep-screenshots]"
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

## 1. Parse arguments — scope is set here (full vs partial)

By default `/uitest` is a **FULL** sweep: the entire page inventory × all detected roles × desktop+mobile. The flags below narrow it to a **PARTIAL** review — mix them freely:
- A bare URL (e.g. `https://staging.example.com`) → use it as the base URL (do NOT start a local server).
- `--no-cleanup` → keep created test accounts (still log them; skip the auto-delete phase).
- `--desktop-only` → skip the mobile/tablet viewports (default is desktop + mobile). *(scope: viewports)*
- `--roles a,b,c` → test only these roles instead of all auto-detected ones. *(scope: roles)*
- `--pages /checkout,/cart,/product/[id]` → test ONLY these routes instead of the full inventory. Accepts exact routes or glob-ish prefixes (`/admin/*`). The coverage matrix is restricted to these pages. *(scope: pages — this is the "partial review" control)*
- `--smoke` → fastest pass: primary role only + desktop only + key pages (home, auth, and the main happy-path routes). A quick confidence check, not exhaustive. *(scope: preset)*
- `--keep-screenshots` → keep ALL screenshots from this run (skip the end-of-run prune of unreferenced ones — see §6.5).
- `--screenshot-retention <days>` → age-prune window for old run folders (default 7; `0` = keep forever).
- Generate a short **run ID** (e.g. `ui-YYYYMMDD-HHMM`; you may pass a timestamp in or derive one from `git rev-parse --short HEAD` + a counter — do not rely on randomness).

Whatever scope the flags select, the coverage contract still applies **within that scope** — i.e. a `--pages /checkout` run must still cover `/checkout` at every in-scope viewport with every element exercised. Partial scope shrinks the matrix; it never lowers the per-cell thoroughness bar.

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

### Page inventory (the authoritative "every page" list)
Build the route inventory **from the codebase** so coverage is grounded in fact, not guessed by the agent:
- Next.js: enumerate `app/**/page.*` or `pages/**/*`. React Router / Vue Router / SvelteKit: parse the router config or file-based routes. Plain HTML: list every `.html`. Server-rendered (Express/Flask/Django): list the view routes that return pages.
- Include each **dynamic route** (`/product/[id]`) once, to be filled with a real sample id discovered during the run.
- Tag pages that require login with the role(s) that can reach them (from route guards / nav visibility).

This `PAGE_INVENTORY` is the authoritative row-set of the coverage matrix below. "Every page" means every entry here — the agent cannot define the scope down by only visiting what it happened to find. **If `--pages` (or a diff-scoped Coordinator deployment) was given, filter the inventory to those routes now** — that filtered set becomes the matrix rows. Still build the full inventory first so you can validate that the requested routes actually exist (warn on any that don't).

## 4. Deploy the army (coverage-driven, parallel)

The `ui-tester` agents are **read-only to code** (they only return findings + created-account records), so they run safely in parallel — unlike the serial code-review pipeline.

**Build the COVERAGE MATRIX** before dispatching: rows = `PAGE_INVENTORY` (filtered per role to the pages that role can access), columns = `(role × viewport)`. Every cell must end as `COVERED` or `UNREACHABLE-with-reason`. This matrix — not the agent's sense of "done" — defines completion.

For each role, dispatch a `ui-tester` agent (use the Agent tool; concurrent, cap ~4–6 to avoid thrashing the dev server — queue the rest). Give each agent:
- The persona/checklist from `.agents/ui-tester.md`
- Its assigned **role** + how to register/log in as it
- Its **explicit page list** (its rows of the matrix) and **both viewports** (desktop then mobile) — it is NOT done until every page on its list is visited at every viewport with every interactive element exercised (its **coverage contract** — see `.agents/ui-tester.md`)
- The **base URL**, the **run ID**, and the screenshot directory `.uitest/screenshots/<runid>/`
- Relevant `LESSONS.md` entries tagged `[ui] [ux] [a11y]`

Each agent returns three sections: **FLAWS**, **ACCOUNTS CREATED**, and a **COVERAGE** record (one row per page × viewport it actually visited, with screenshot + element-exercised counts).

**Completion loop (loop-until-complete, not until-tired):**
1. Collect every agent's COVERAGE records; mark each proven cell `COVERED` in the matrix.
2. Compute `coverage = covered cells / total cells`.
3. For any cell still uncovered (agent stopped early, errored, or skipped a reachable page) → **re-dispatch a fresh ui-tester for ONLY the missing cells**. Repeat. Cap at 3 rounds so a genuinely-broken page can't loop forever.
4. A cell may be closed `UNREACHABLE` only with a logged reason (route behind a feature flag, needs real payment, dynamic id couldn't be obtained, etc.).
5. The run completes only when **every cell is `COVERED` or `UNREACHABLE-with-reason`.** Record the final coverage % and list anything not covered — never silently drop a page.

**Ledger-first rule:** when an agent reports it is about to create an account, write that row to `TEST_USERS.md` with `deleted = no` *before* acknowledging — never after. (You are the single writer of `TEST_USERS.md`.)

## 5. Assemble UI_FLAW_REPORT.md

Collect every agent's FLAWS into one report at the project root. Deduplicate findings that multiple agents hit (same screen + same element + same symptom → one row, note "seen by roles: …"). Sort by Severity (Critical → Low).

```markdown
# UI Flaw Report — <run ID>

- Date: <date>
- Base URL: <url>
- Roles tested: <list>   |   Viewports: <list>
- Agents deployed: <N>   |   Screenshots: .uitest/screenshots/<runid>/
- Coverage: <covered>/<total> page×viewport×role cells (<pct>%)  |  Uncovered: <list pages + reason, or "none">
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

## 6.5 Screenshot retention (disk hygiene)

Screenshots live in `.uitest/screenshots/<runid>/` (gitignored) and accumulate fast — one per page × viewport × role, every run. Prune them so disk doesn't balloon. Two rules:

1. **End-of-run prune (keep only evidence).** A screenshot's job is done once a page is judged. After the report is written, **keep only the screenshots referenced by a flaw** in this run's `UI_FLAW_REPORT.md` — those are the proof the Builder/human needs. **Delete every unreferenced ("looks fine") screenshot.** On a fully clean pass (no flaws), that means deleting all of this run's screenshots — the COVERAGE record already proves each page was visited, so the pixels add nothing.
2. **Age prune (sweep old runs).** Delete any `.uitest/screenshots/<runid>/` folder whose run is older than the **retention window (default 7 days)**, regardless of flaws — by then the flaws those shots documented are presumably fixed and the report is historical. Do this at the start of teardown so every run also tidies up after past ones (works even if an earlier run was interrupted before its own prune).

Flags that change this:
- `--keep-screenshots` → skip the end-of-run prune; keep ALL of this run's screenshots (age prune still applies later).
- `--screenshot-retention <days>` → change the age window. `--screenshot-retention 0` disables age pruning (keep forever).

Report how many were kept vs pruned in the summary. Never delete `UI_FLAW_REPORT.md` itself — only the image files.

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
  Agents deployed:  <N>             Pages in inventory: <count>
  Coverage:         <covered>/<total> cells (<pct>%)  ·  uncovered: <n> (<reason>)
  Flaws found:      <C> Critical · <H> High · <M> Medium · <L> Low
  Test accounts:    <created> created · <deleted> cleaned up · <left> remaining
  Screenshots:      <kept> kept (flaw evidence) · <pruned> pruned · <oldRuns> old runs swept
  Report:           UI_FLAW_REPORT.md
  Kept shots:       .uitest/screenshots/<runid>/
═══════════════════════════════════════════════════════════════
```

## Guardrails
- NEVER run against a production database or a real users' dataset. Prefer the local dev server or an explicit staging URL.
- ALWAYS write a created account to TEST_USERS.md BEFORE the agent submits the registration (orphan safety).
- NEVER let a ui-tester edit code — flaws are fixed by the Builder, not the testers.
- If no browser automation tool is available anywhere, report it as a single Critical finding and exit (don't pretend to have tested).
- Respect `PAUSE.md` — if it exists, do nothing and exit.
