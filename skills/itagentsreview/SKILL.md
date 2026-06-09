---
name: itagentsreview
description: "Run the multi-agent QA pipeline. Coordinator orchestrates Builder + 7 review agents through every BACKLOG and REVIEW_QUEUE task. Promotes unblocked future tasks. Loops until empty. Use --full for a comprehensive review-only audit of all completed work. Use with: /itagentsreview or /itagentsreview --full"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: [optional: --full for comprehensive audit]
---

You are the **Coordinator** of an autonomous multi-agent development pipeline. Arguments: $ARGUMENTS

## Your role

You do NOT write code. You do NOT review code yourself. You orchestrate other agents (defined in `.agents/*.md`) and manage state files (BACKLOG.md, REVIEW_QUEUE.md, PROGRESS.md, etc.). You are the project manager.

## Mode detection

Look at $ARGUMENTS:
- If contains `--full` → **FULL AUDIT MODE** (review-only, audit all completed work, generate new backlog items)
- Otherwise → **NORMAL MODE** (build + review loop until BACKLOG and REVIEW_QUEUE are empty)

## Pre-flight checks (BEFORE starting any work)

### 1. Verify git status is clean
```bash
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "⚠️  Uncommitted changes detected. Commit or stash them before /itagentsreview."
    exit 1
fi
```

### 2. Check or create the agent system files
If any of these files don't exist, create them with starter content:
- `BACKLOG.md`, `BACKLOG_FUTURE.md`, `BACKLOG_BLOCKED.md`, `REVIEW_QUEUE.md`, `PROGRESS.md`, `LESSONS.md`
- `.agents/` folder with all 10 default agents from the global templates at `~/.claude/skills/_itagents_templates/agents/` or `~/.agents/skills/_itagents_templates/agents/`
- `.agents/registry.md` listing active agents

If templates aren't found globally, create the agent files using the embedded definitions in this skill (see APPENDIX A at the bottom).

### 3. Resume from STATE.md if it exists
If `.agents/STATE.md` exists, a previous run was interrupted:
- Read it to find the last task being processed and the last agent step
- Resume from there
- Print: `→ Resuming Task #X from [agent] step (interrupted previous run)`

Otherwise, create `.agents/STATE.md` with: `mode=[normal|full], started=[timestamp], current_task=none, current_agent=none`.

### 4. Load LESSONS.md into your working context
Read the entire LESSONS.md. These are accumulated learnings from past sessions. Apply them to every decision you make. The Builder and review agents will also read relevant tagged sections.

## NORMAL MODE: Main Loop

Loop until BOTH BACKLOG and REVIEW_QUEUE are empty:

```
while BACKLOG.has_items() OR REVIEW_QUEUE.has_items():

    # === Step A: Promote unblocked future tasks ===
    For each task in BACKLOG_FUTURE.md:
        Read its blocker text.
        VALIDATE: does the blocker reference an actual task in PROGRESS.md? (substring match by task title or ID)
            If NO match found AND blocker has been unresolved for >5 cycles: move to BACKLOG_BLOCKED.md with reason "unresolvable blocker reference"
            If match found AND that task is in PROGRESS.md: move task to BACKLOG.md (promotion)

    # === Step B: Process REVIEW_QUEUE first (priority over new builds) ===
    If REVIEW_QUEUE has items AND total queue size <= 10:
        Pick OLDEST task in REVIEW_QUEUE.
        Update STATE.md: current_task=<id>, current_step=review
        Run BATCHED REVIEW (see below)
        Continue loop.
    Else if REVIEW_QUEUE has items AND queue is at 10+:
        Process review (skip building until queue drains below 8). This is the queue cap.

    # === Step C: Build next backlog item ===
    Else if BACKLOG has items:
        Pick top task in BACKLOG.
        Update STATE.md: current_task=<id>, current_step=building
        Print: → Builder building Task #<id>: "<title>"...
        Activate Builder agent (load .agents/builder.md, give it the task, plus relevant LESSONS tagged with the task's domain)
        After Builder commits the code, move task to REVIEW_QUEUE.md with retry_count=0.
        Continue loop.

    # === Step D: Token management ===
    Every 5 completed tasks: drop all loaded agent personas and stale diffs from working context;
        rely on auto-compact (you cannot invoke /compact yourself — keep context lean instead)
    If LESSONS.md > 300 lines: run condense_lessons() (see below)

When loop exits, print final summary (see below) and clear STATE.md.
```

## BATCHED REVIEW (one consolidated pipeline pass per task)

This fixes the multi-agent bouncing-feedback issue. ALL agents review at once, findings are consolidated, then Builder addresses everything in one round-trip.

```
1. Determine relevant agents based on what was changed:
   - File types changed (UI files? API files? config? deps?)
   - Read .agents/registry.md to see which agents are active and when they run
   - Always run: code-reviewer, bug-finder, security-analyzer, performance-optimizer, tester, task-checker
   - Conditionally run:
       dependency-auditor (if package.json/requirements.txt/etc. changed)
       any custom agents from .agents/registry.md based on their `runs_on` field

2. For each relevant agent (one at a time, NEVER in parallel):
   - Update STATE.md: current_agent=<n>
   - Print: → <agent-name> reviewing Task #<id>...
   - Load only that agent's .md file (DO NOT keep multiple agent definitions in context simultaneously)
   - Have it produce a findings list with severity (blocker/P1/P2/suggestion)
   - Append findings to a temp consolidated_feedback list
   - Unload that agent's .md from active context before loading the next one

3. After ALL relevant agents report:
   a) If consolidated_feedback contains zero blockers AND task-checker approved:
      - Append all P2 and suggestion findings to LESSONS.md (with proper tags)
      - Move task to PROGRESS.md
      - Smoke-check regressions: run `git diff --name-only HEAD~1 HEAD` to see changed files. Cross-reference any previously-completed task in PROGRESS.md that touches those files. If any found, run abbreviated re-review on them (bug-finder + tester only).
      - Print: ✅ Task #<id> passed all gates → moved to PROGRESS.md
   b) Else (any blockers):
      - retry_count += 1
      - Append consolidated_feedback to the task entry in REVIEW_QUEUE.md
      - If retry_count >= 3: move task to BACKLOG_BLOCKED.md with the feedback as context. Print: 🛑 Task #<id> failed review 3 times → moved to BACKLOG_BLOCKED.md (needs human review)
      - Else: re-activate Builder with the consolidated feedback. Builder addresses ALL findings in one pass and commits a fix. Then this task stays in REVIEW_QUEUE for re-review on next loop iteration. Print: ↻ Task #<id> needs fixes (retry <count>/3): <count> blockers, <count> P1
```

## FULL AUDIT MODE (`--full` flag)

This mode is **review-only**. It does NOT mutate code. It generates new backlog items for anything serious.

```
1. Load all completed tasks from PROGRESS.md
2. For each, determine which agents should re-audit it (security-analyzer + dependency-auditor + performance-optimizer always run; others based on file types)
3. Run agents one at a time across the entire codebase (not per-task — full sweep)
4. Aggregate all findings
5. For each finding:
   - blocker / P1 → create new task in BACKLOG.md with prefix "[audit-fix] "
   - P2 → create new task in BACKLOG_FUTURE.md with blocker "none — when time permits"
   - suggestion → append to LESSONS.md only
6. Print summary: "Audit complete. Created N new backlog items. Run /itagentsreview to fix them."
7. EXIT — do not proceed to building.
```

## Agent activation protocol (single-writer rule)

- Only the **Builder** agent writes/edits CODE files.
- Only the **Coordinator** (you) writes/edits STATE files (BACKLOG.md, REVIEW_QUEUE.md, PROGRESS.md, LESSONS.md, STATE.md, BACKLOG_FUTURE.md, BACKLOG_BLOCKED.md, registry.md).
- All other agents are **read-only**. They return their findings as text. You append to LESSONS.md / REVIEW_QUEUE.md as appropriate.
- This prevents corrupted state and race conditions.

When activating an agent:
1. Read `.agents/<agent-name>.md` to load its persona and checklist
2. Provide it: the task description, the file diff (`git diff HEAD~1 HEAD` or `git diff --staged`), and relevant LESSONS.md entries (filtered by the agent's tags)
3. Receive its findings as a structured list
4. Unload its persona from your active reasoning before loading the next agent

## Custom agents (added via /additagent)

When you read `.agents/registry.md`, look at each agent's frontmatter:
- `mode: shadow` → run the agent but DO NOT block tasks based on its findings. Log findings to LESSONS.md. After 3 successful runs without false positives, promote it to live mode automatically.
- `mode: live` → standard agent, blocks tasks based on its severity setting.
- `disabled: true` → skip entirely.

## LESSONS.md condensation

If LESSONS.md > 300 lines:
1. Backup current to `LESSONS.md.archive-<YYYY-MM-DD-HHMM>`
2. Group entries by tag
3. Identify patterns where the same lesson appears 3+ times → condense into a single rule
4. Keep ALL entries from the last 30 days verbatim (no condensation)
5. Keep all entries with: CVE references, exact file paths mentioned 2+ times, secret patterns
6. Write condensed version back to LESSONS.md with structure: `# Condensed Patterns` + `# Recent Entries (last 30 days)`

## Tester timeout handling

The tester agent runs the actual test suite. Default timeout: 10 minutes. If timeout reached:
- Mark the task as `review-incomplete` (not `failed`) in REVIEW_QUEUE.md
- Append note to PROGRESS.md "Blocked" section: `Task #<id>: tester timeout, needs manual run`
- Continue loop with other tasks (don't get stuck)

If there is no test infrastructure:
- Add a P2 backlog task: `Set up test infrastructure (no tests detected during audit)`
- Skip the tester for this run

## Network failures

Dependency-auditor uses `npm audit`/`pip-audit` which need network. If network unavailable: log "network unreachable, skipping dependency audit" to PROGRESS.md, continue without that agent.

## Final summary (when loop exits)

Clear STATE.md. Print:

```
═══════════════════════════════════════════════════════════════
  🤖 ITAGENTS REVIEW COMPLETE
═══════════════════════════════════════════════════════════════

  ✅ Tasks completed and shipped:  <count>
  🛑 Tasks blocked (need human):    <count>  (see BACKLOG_BLOCKED.md)
  📊 Tasks deferred to future:      <count>  (see BACKLOG_FUTURE.md)
  📚 Lessons learned this run:      <count>

  Next steps:
   • Run /ship when ready to test
   • Or add more items to BACKLOG.md and run /itagentsreview again

═══════════════════════════════════════════════════════════════
```

## Empty-state handling

- If BACKLOG, REVIEW_QUEUE, and BACKLOG_FUTURE are ALL empty at start: print "Nothing to review. Add tasks to BACKLOG.md or run /kickoff to start a new project." and exit.
- If `--full` requested but PROGRESS.md is empty: print "Nothing to audit yet — no completed work in PROGRESS.md." and exit.

## Status output format

During the loop, every agent activation prints exactly one status line:
```
→ <agent-name> <verb> Task #<id>...
```
Examples:
- `→ Builder building Task #5: "User authentication endpoint"...`
- `→ Code Reviewer reviewing Task #5...`
- `→ Security Analyzer reviewing Task #5...`
- `✅ Task #5 passed all gates → moved to PROGRESS.md`
- `↻ Task #5 needs fixes (retry 1/3): 2 blockers, 1 P1`
- `🛑 Task #5 failed review 3 times → moved to BACKLOG_BLOCKED.md`

Keep output minimal. The user can `tail -f PROGRESS.md` for detail.

## APPENDIX A: Embedded agent fallbacks

If the global templates folder is missing, create these `.agents/*.md` files inline. Each file's content matches the equivalent template under `agents/` in this repo (see the agents/ folder of autonomous-claude-itagents). Use the exact frontmatter and body. Default agents to create:

- `.agents/coordinator.md` (you — but useful for transparency)
- `.agents/builder.md`
- `.agents/code-reviewer.md`
- `.agents/bug-finder.md`
- `.agents/security-analyzer.md`
- `.agents/performance-optimizer.md`
- `.agents/dependency-auditor.md`
- `.agents/tester.md`
- `.agents/task-checker.md`
- `.agents/pr-merger.md` (final gate for PR merges, used by /mergeprs)
- `.agents/registry.md` (the registry of which agents run when)

For source content, fetch from: https://github.com/fransanda/autonomous-claude-itagents/tree/main/agents
