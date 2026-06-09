# 🤖 Autonomous Claude ITAgents

**A 10-agent QA pipeline that reviews every line of code Claude writes.**

This repo is the companion to [autonomous-claude-skills](https://github.com/fransanda/autonomous-claude-skills). When both are installed, every project gets:

- A private GitHub repo (auto-created)
- Autonomous building from a backlog
- **A full team of specialist agents reviewing each task**: architecture, bugs, security, performance, dependencies, tests, and final requirements check
- Auto-improving project memory (`LESSONS.md`)

You're not just delegating coding to Claude — you're delegating an entire engineering team.

---

## Why this exists

Solo Claude is fast but blind to its own mistakes. Real engineering teams have specialists: a senior reviewer for architecture, a QA for bugs, an AppSec for security, a perf engineer for speed. This repo gives Claude that team — not by spinning up real agents (which would cost money and infrastructure) but by having the same Claude session put on different hats in a strict pipeline.

Result: the same monthly Claude bill, but every task goes through 7+ review passes before it ships.

---

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  /kickoff or /autonomy (from autonomous-claude-skills)       │
│  → Sets up project, including .agents/ folder                │
│  → Builder works through BACKLOG, fills REVIEW_QUEUE         │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│  /itagentsreview (or /itagentsreview --full)                 │
│                                                              │
│  Coordinator loops until BACKLOG + REVIEW_QUEUE are empty:  │
│   1. Promote unblocked future tasks                          │
│   2. Process REVIEW_QUEUE (priority over building)           │
│   3. Build next BACKLOG item                                 │
│                                                              │
│  Review pipeline per task (one batched pass):               │
│   Code Reviewer → Bug Finder → Security → Performance →     │
│   Dependency → Tester → Task Checker (final gate)           │
│                                                              │
│  Pass → PROGRESS.md ✅                                       │
│  Fail → stays in queue with consolidated feedback (max 3x)  │
│  3 fails → BACKLOG_BLOCKED.md (needs human)                 │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│  /mergeprs (or auto via /improve Phase 5.5)                  │
│                                                              │
│  For each open PR (oldest first):                           │
│   1. Adaptive review: security + code-reviewer + tester     │
│   2. Escalate if P2+ findings                               │
│   3. Builder fixes blockers (up to 5 retries)               │
│   4. PR Merger (Opus) final gate                            │
│   5. Auto-merge or comment findings                         │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│  /ship → final report, ready to test                         │
└─────────────────────────────────────────────────────────────┘
```

---

## The 10 agents

| Agent | Role |
|---|---|
| **Coordinator** | Orchestrates the loop, manages state files, promotes unblocked tasks |
| **Builder** | Writes code (only agent that edits source files) |
| **Code Reviewer** | Architecture, SOLID, DRY, function size, complexity |
| **Bug Finder** | Edge cases, race conditions, null safety, off-by-one, memory leaks |
| **Security Analyzer** | OWASP Top 10, hardcoded secrets, SQL injection, XSS, missing auth |
| **Performance Optimizer** | N+1 queries, re-renders, bundle size, missing indexes |
| **Dependency Auditor** | CVEs, outdated packages, unused deps, license issues |
| **Tester** | Runs the test suite, validates a11y, RBAC, edge inputs, unhappy paths |
| **Task Checker** | Final gate: did the Builder actually deliver what was asked? |
| **PR Merger** | Final gate before PR merge — heavyweight Opus reviewer (on-demand, via /mergeprs) |

You can add custom agents anytime via `/additagent`.

---

## Install

### Prerequisites
1. [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed and authenticated
2. **[autonomous-claude-skills](https://github.com/fransanda/autonomous-claude-skills) installed first** (this repo extends it)
3. [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
4. Git installed
5. A Claude Pro, Max, or API subscription

### Install in 2 steps

**Step 1: Install autonomous-claude-skills (the base)**

Mac/Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/fransanda/autonomous-claude-skills/main/install.sh | bash
```

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/fransanda/autonomous-claude-skills/main/install.ps1 | iex
```

**Step 2: Install autonomous-claude-itagents (this repo)**

Mac/Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/fransanda/autonomous-claude-itagents/main/install.sh | bash
```

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/fransanda/autonomous-claude-itagents/main/install.ps1 | iex
```

**Restart Claude Code** after installing.

That's it. Now `/kickoff` and `/autonomy` will detect the agent system and create the full file structure automatically.

---

## Usage

### Daily workflow

```bash
mkdir my-app && cd my-app
claude --dangerously-skip-permissions
```

```
/kickoff I want to build a recipe sharing app
```

Claude asks the discovery questions (one round only), creates the private GitHub repo, sets up the project files including `.agents/`, and starts building.

When you want to ship:

```
/itagentsreview
```

The Coordinator activates. You'll see live status updates:

```
→ Builder building Task #5: "User authentication endpoint"...
→ Code Reviewer reviewing Task #5...
→ Bug Finder reviewing Task #5...
→ Security Analyzer reviewing Task #5...
→ Performance Optimizer reviewing Task #5...
→ Tester reviewing Task #5...
→ Task Checker reviewing Task #5...
✅ Task #5 passed all gates → moved to PROGRESS.md
→ Builder building Task #6: ...
```

When the loop finishes:

```
/ship
```

You get a clear test report with the exact command to run.

### `/itagentsreview --full`

Runs a **review-only audit** of all completed work in `PROGRESS.md`. This mode:
- Does NOT mutate code
- Generates new BACKLOG items for any blocker/P1 findings
- Logs P2 findings to LESSONS.md
- Runs after deployments, before releases, or whenever you want a comprehensive sweep

After `--full`, run `/itagentsreview` (without the flag) to fix the new backlog items.

### `/mergeprs`

Autonomously review and merge open PRs:

```
/mergeprs
```

By default, only processes PRs on `improve/*` branches (created by `/improve`). Use `--all` for all open PRs:

```
/mergeprs --all
```

The pipeline per PR:
1. **First-pass review**: security-analyzer, code-reviewer, tester
2. **Escalation** (if P2+ findings): bug-finder, performance-optimizer, dependency-auditor, task-checker
3. **Builder fixes** any blockers (up to 5 retries)
4. **PR Merger** (Opus) does a final heavyweight review — full diff, independent security pass, coherence check, VISION.md alignment
5. If everything passes: **auto-merge**. If not after 5 retries: **comments findings on PR** for human review.

Configure via `IMPROVE_CONFIG.md`:
```markdown
## PR Merge Policy
- Auto-merge after /improve: no    # set to 'yes' to auto-merge after /improve runs
- Merge scope: improve-only        # or 'all'
- Merge model: opus                # model for the pr-merger agent
```

### `/additagent`

Add a custom specialist:

```
/additagent
```

Claude asks 7 questions in one message:
1. Agent name
2. Persona / role
3. When does it run? (every-task / ui-tasks-only / api-tasks-only / dep-changes-only / full-audit-only / on-keyword:X)
4. Specific checklist
5. Permissions (read-only or can-execute)
6. Severity (blocker/P1/P2/suggestion)
7. Tags for LESSONS.md

The agent goes into **shadow mode** for its first 3 runs (logs findings but doesn't block tasks). After 3 successful runs, it auto-promotes to live.

Examples of useful custom agents:
- `accessibility-checker` — WCAG AAA compliance specialist
- `i18n-auditor` — checks all user-facing strings are translatable
- `mobile-tester` — checks touch targets, viewport, mobile-specific bugs
- `seo-auditor` — meta tags, semantic HTML, sitemap

---

## File structure (in every project)

```
PROJECT/
├── CLAUDE.md              ← autonomous rules + security defaults
├── BACKLOG.md             ← ready to build
├── BACKLOG_FUTURE.md      ← blocked, organized by blocker
├── BACKLOG_BLOCKED.md     ← failed review 3+ times (needs human)
├── REVIEW_QUEUE.md        ← built, awaiting review
├── PROGRESS.md            ← passed all gates
├── LESSONS.md             ← auto-improving memory
└── .agents/
    ├── registry.md         ← which agents are active
    ├── STATE.md           ← run state (auto-managed)
    ├── coordinator.md
    ├── builder.md
    ├── code-reviewer.md
    ├── bug-finder.md
    ├── security-analyzer.md
    ├── performance-optimizer.md
    ├── dependency-auditor.md
    ├── tester.md
    ├── task-checker.md
    ├── pr-merger.md
    └── [your custom agents]
```

---

## v1 design decisions (the failure modes we already prevented)

This system is built with deliberate safeguards against the ways multi-agent pipelines usually fail. These are baked in:

### Single-writer rule
Only **Builder** writes code. Only **Coordinator** writes state files. All review agents are read-only and return findings as text. This prevents file corruption from concurrent edits.

### Batched review (one consolidated pass)
A naive pipeline runs Code Reviewer → Builder fix → Bug Finder → Builder fix → Security Analyzer → Builder fix... and bounces forever between agents that disagree. We instead run **all relevant agents at once**, consolidate every finding into one bundle, and the Builder addresses all of it in a single round-trip. Three of those rounds = task moves to BLOCKED.

### Blocker validation
Tasks in `BACKLOG_FUTURE.md` reference what they're blocked by. Before promoting a task, the Coordinator validates the blocker actually matches a completed task in `PROGRESS.md`. Tasks with unresolvable blocker references get moved to BLOCKED instead of looping forever.

### Smoke check after fixes
When the Builder edits a file to fix Task #5, that change might break Task #3 (which already shipped and uses the same file). After every fix, the Coordinator runs an abbreviated re-review on previously-completed tasks that touch the changed files.

### Token management
- One agent definition loaded at a time (load → use → unload)
- Auto `/compact` every 5 completed tasks
- REVIEW_QUEUE capped at 10 active items (Coordinator pauses building until queue drains)
- LESSONS.md condenses at 300 lines (with backups, never touching last-30-days entries)

### `--full` is review-only
The full audit mode never mutates existing code. It only generates new backlog items. This prevents a single audit from breaking N working features in one shot.

### Shadow mode for custom agents
New agents from `/additagent` log findings for their first 3 runs without blocking anything. If they're noisy or buggy, you find out before they break the pipeline.

### Crash recovery
The Coordinator writes `STATE.md` at every step. If the run is interrupted, the next `/itagentsreview` resumes from the last task and step.

### Tester timeout
Test suites that hang don't deadlock the pipeline. After 10 minutes, Tester reports `review-incomplete` (not failed) and the loop continues.

---

## Auto-improving memory

Every agent that finds something appends to `LESSONS.md`:

```markdown
## 2026-04-16 — security-analyzer [security] [auth]
- Builder hardcoded JWT secret in /api/auth.ts
- LESSON: Always check for hardcoded secrets in new auth-related files

## 2026-04-17 — bug-finder [bug] [race-condition]
- Found race condition in payment webhook handler
- LESSON: Webhook handlers must be idempotent in this project (Stripe retries)
```

At the start of every session, agents read relevant tagged sections of `LESSONS.md`. Over time, the project gets smarter — same bugs don't get reintroduced, same patterns get applied automatically.

After 300 lines, the Coordinator condenses repeated lessons into single rules while preserving recent verbatim entries and any specific CVE references, secret patterns, or file paths mentioned multiple times.

This is **per-project memory** — no global state, no extra cost. It's just a markdown file Claude reads.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `/itagentsreview` not found after install | Restart Claude Code |
| Still not found | Re-run install — skills go in both `~/.claude/skills/` and `~/.agents/skills/` |
| `/itagentsreview` says agent system not set up | Run it once — it auto-creates `.agents/` from global templates |
| Pipeline stuck on a task | Check `.agents/STATE.md` to see what step it was on. Delete the file to reset. The task will go through again. |
| Want to disable a specific agent | Edit its frontmatter in `.agents/<n>.md`: set `disabled: true` |
| LESSONS.md got too big | It auto-condenses at 300 lines, but you can manually run /itagentsreview which checks every cycle |
| Custom agent producing too many false positives | Set `mode: shadow` in its frontmatter, or set `disabled: true` to remove it |
| Want to start fresh | Delete `.agents/STATE.md` and clear `REVIEW_QUEUE.md` |
| `/mergeprs` says gh not authenticated | Run `gh auth login` to authenticate the GitHub CLI |
| PR stuck after 5 retries | Check the PR comments for findings. Fix manually or close and re-create the PR |

---

## Uninstall

### Mac / Linux
```bash
for d in ~/.claude/skills ~/.agents/skills; do
  rm -rf "$d/itagentsreview" "$d/additagent" "$d/mergeprs" "$d/_itagents_templates"
done
```

### Windows
```powershell
foreach ($d in @("$env:USERPROFILE\.claude\skills","$env:USERPROFILE\.agents\skills")) {
  foreach ($s in @("itagentsreview","additagent","mergeprs","_itagents_templates")) {
    Remove-Item "$d\$s" -Recurse -Force -ErrorAction SilentlyContinue
  }
}
```

This removes the agent skills but leaves `autonomous-claude-skills` intact.

---

## License

MIT — use however you want.

## Contributing

Ideas, improvements, and new default agents welcome. Open an issue or PR.

## Integration with `/improve`

The `/improve` command from [autonomous-claude-skills](https://github.com/fransanda/autonomous-claude-skills) automatically detects this repo's agents and uses them for deeper scanning. When itagents is installed, `/improve` loads `security-analyzer`, `bug-finder`, `performance-optimizer`, and `dependency-auditor` during its scan phase — giving the improvement loop the same specialist analysis as the full review pipeline, without requiring a manual `/itagentsreview` call.

### Auto-merging PRs after /improve

When both repos are installed, `/improve` can automatically review and merge previously-created improvement PRs at the end of each cycle. Enable in `IMPROVE_CONFIG.md`:

```markdown
## PR Merge Policy
- Auto-merge after /improve: yes
```

This runs the full `/mergeprs` pipeline (adaptive review + Builder fixes + PR Merger final gate) on all pending `improve/*` PRs after the current cycle's improvements are staged.

## Sister project

[autonomous-claude-skills](https://github.com/fransanda/autonomous-claude-skills) — the base layer that makes Claude Code work autonomously. Required for this repo. Includes `/kickoff`, `/autonomy`, `/improve`, and `/ship`.
