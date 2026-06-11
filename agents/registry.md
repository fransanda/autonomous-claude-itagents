# Active Agents Registry

This file lists every agent the Coordinator can invoke during /itagentsreview. Edit to disable or change runs_on. Custom agents added via /additagent are appended automatically.

## Agent table

| Agent | Runs On | Severity | Mode | Notes |
|---|---|---|---|---|
| coordinator | always | n/a | live | orchestrator, no findings |
| builder | when assigned | n/a | live | implementer, no findings |
| code-reviewer | every-task | P1 | live | architecture, SOLID, DRY |
| bug-finder | every-task | P1 | live | edge cases, race conditions, null safety |
| security-analyzer | every-task | blocker | live | OWASP Top 10, secrets, auth, injection |
| performance-optimizer | every-task | P2 | live | N+1, re-renders, bundle size |
| dependency-auditor | dep-changes-only | P1 | live | CVEs, outdated, licenses, unused |
| tester | every-task | blocker | live | runs tests, a11y, RBAC, edge inputs |
| task-checker | every-task | blocker | live | requirements vs delivery (final gate) |
| pr-merger | on-demand | blocker | live | final gate before PR merge (Opus) |
| ui-tester | ui-tasks-only | blocker | live | drives a real browser like a human — visual + workflow + responsive flaws, one agent per role (also /uitest). Critical/High block; Medium=P1, Low=P2 |

## Modes
- `live` — agent's findings can block tasks based on severity
- `shadow` — agent runs but findings are logged-only (used for new custom agents in their first 3 runs)
- `disabled: true` — skip entirely (set in agent's own .md frontmatter)

## Runs On options
- `every-task` — runs on every REVIEW_QUEUE item
- `ui-tasks-only` — only when changed files include UI components
- `api-tasks-only` — only when changed files include API/server logic
- `dep-changes-only` — only when dependency manifest files change
- `full-audit-only` — only during /itagentsreview --full
- `on-keyword:WORD` — only when task title/description contains WORD
- `always` — runs even outside normal task flow (only coordinator should use this)
- `on-demand` — only invoked by specific skills (not part of the regular /itagentsreview pipeline)

## UI testing army (live browser QA)

When the Coordinator detects a UI/frontend (or you run `/uitest`), it deploys `ui-tester` agents — autonomous "client" agents that drive a real browser (Playwright MCP → chrome-devtools MCP → agent-browser CLI fallbacks) to register accounts, click, navigate, and screenshot like humans. They find what static reviewers and the curl-based Tester can't: **empty/broken buttons, navigation that lands on the wrong page, wrong scroll targets, missing intermediate screens, broken end-to-end workflows, and responsive breakage on desktop + mobile.** One agent per detected role (buyer/seller/admin/guest…), each covering every viewport. They are **read-only to code** (so they run in parallel) and return findings as a strict flaw table; the orchestrator writes `UI_FLAW_REPORT.md`. Any accounts they create are logged to `TEST_USERS.md` (gitignored) and **auto-deleted** at the end of the run. See `.agents/ui-tester.md` and the `/uitest` SKILL.md.

## Fast-track lane (trivial changes)

A task tagged `[fast-track]` in BACKLOG.md (or proposed by the Builder for a trivial change) skips the heavyweight reviewers and runs a **2-gate review**: `security-analyzer` + `task-checker` only. The Coordinator validates eligibility against the real diff before fast-tracking — **≤ 10 changed lines across ≤ 2 files, no sensitive paths (auth/security/crypto/DB/dependency/CI/config), and no new attack surface**. If any guard fails, fast-track is revoked and the task runs the full pipeline. Security and the requirements check are *never* skipped. See the FAST-TRACK ELIGIBILITY section in the /itagentsreview SKILL.md for the full guard list.

## How custom agents graduate from shadow → live
After 3 successful pipeline runs without producing false positives (i.e. its findings were either valid or low-confidence enough to be ignored), the Coordinator promotes a shadow agent to live mode automatically. This protects the pipeline from poorly-defined custom agents on day one.

To manually graduate immediately: set `mode: live` in the agent's .md frontmatter and remove the `shadow_runs_remaining` line.
