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

## How custom agents graduate from shadow → live
After 3 successful pipeline runs without producing false positives (i.e. its findings were either valid or low-confidence enough to be ignored), the Coordinator promotes a shadow agent to live mode automatically. This protects the pipeline from poorly-defined custom agents on day one.

To manually graduate immediately: set `mode: live` in the agent's .md frontmatter and remove the `shadow_runs_remaining` line.
