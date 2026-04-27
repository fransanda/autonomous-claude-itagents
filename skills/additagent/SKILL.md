---
name: additagent
description: "Add a custom agent to the project's review pipeline. Asks 7 questions about role, when it runs, checklist, severity, and tags. Generates .agents/<name>.md and updates .agents/registry.md. New agents start in shadow mode (3 silent runs before going live). Use with: /additagent"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

You are creating a new custom agent for this project's review pipeline.

## Step 1: Verify the project has the agent system

Check that `.agents/` folder exists. If not:
```
This project doesn't have the agent system set up yet.
Run /itagentsreview first — it will set up .agents/ automatically.
```
And exit.

## Step 2: Ask all 7 questions in ONE message

This is the only opportunity. Ask them all together:

```
Let's add a new agent. Answer all in one message:

1. Agent name (kebab-case, e.g. "accessibility-checker"):
2. Persona / role description (1-3 sentences, in the voice of the agent):
3. When does it run? Pick one or describe:
   - every-task (runs on every REVIEW_QUEUE item)
   - ui-tasks-only (only when UI files changed)
   - api-tasks-only (only when API/server files changed)
   - dep-changes-only (only when package.json/requirements.txt/etc. changed)
   - full-audit-only (only during /itagentsreview --full)
   - on-keyword:[word] (only when task title/description contains the keyword)
4. Specific checklist — what does it look for? (bulleted list, 3-10 items):
5. Permissions: read-only / can-execute (run scripts/tests)
6. Severity of findings: blocker / P1 / P2 / suggestion
7. Tags for LESSONS.md (comma-separated, e.g. "ui, accessibility, a11y"):
```

Wait for the user's answer.

## Step 3: Validate the answers

- Agent name must be kebab-case, no spaces, no special chars except hyphens
- Name must not collide with existing agents in `.agents/` (check first)
- If user picked severity "blocker", check `.agents/registry.md`: count existing blocker-severity agents. If already 3+ blocker agents are live, WARN the user:
  ```
  ⚠️  You already have 3 blocker-severity agents. Adding another may make the pipeline too strict.
      Continuing anyway, but consider P1 instead.
  ```
  But proceed.
- Permissions "can-execute" requires the agent to have a valid testing/execution justification. Otherwise default to read-only.

## Step 4: Generate the agent file

Create `.agents/<name>.md` with this exact structure:

```markdown
---
name: <name>
runs_on: <when_it_runs>
severity: <severity>
permissions: <permissions>
tags: <comma-separated-tags>
mode: shadow
shadow_runs_remaining: 3
---

# <Title-Case Name>

## Persona
<role_description>

## Checklist
When activated on a task, you check:
<bulleted_checklist_from_user>

## Output format
Return findings as:
```
[<severity>] <description>
  File: <path>
  Line: <number>
  Suggested fix: <text>
```
If no findings: return `NO ISSUES FOUND`.

## Tags for LESSONS.md
Use these tags when appending learnings: <tags>
```

## Step 5: Update .agents/registry.md

Read the current registry.md. Append a row to the agents table. Example:

```markdown
| accessibility-checker | ui-tasks-only | P1 | shadow | tags: ui, accessibility, a11y |
```

If the registry doesn't yet have a table, create it with this header:

```markdown
# Active Agents Registry

| Agent | Runs On | Severity | Mode | Notes |
|---|---|---|---|---|
| code-reviewer | every-task | P1 | live | architecture, SOLID, DRY |
| bug-finder | every-task | P1 | live | edge cases, race conditions |
| security-analyzer | every-task | blocker | live | OWASP Top 10, secrets, auth |
| performance-optimizer | every-task | P2 | live | N+1, re-renders, bundle size |
| dependency-auditor | dep-changes-only | P1 | live | CVEs, outdated, licenses |
| tester | every-task | blocker | live | runs the test suite |
| task-checker | every-task | blocker | live | requirements vs output (final gate) |
| <new-agent> | <runs_on> | <severity> | shadow | <tags> |
```

## Step 6: Confirm

Print:

```
✅ Agent created: <name>
   File: .agents/<name>.md
   Mode: shadow (3 silent runs before going live)
   Runs on: <runs_on>
   Severity: <severity>

The agent will run on the next /itagentsreview but won't block tasks until it has logged 3 successful runs without false positives.
To disable: edit .agents/<name>.md and set `disabled: true` in frontmatter.
```

## Shadow mode mechanics (for reference; the Coordinator handles this)

- Each run, the Coordinator decrements `shadow_runs_remaining`
- During shadow runs, findings are logged to LESSONS.md but DO NOT block any task
- After `shadow_runs_remaining` reaches 0, Coordinator updates frontmatter to `mode: live`
- This prevents a poorly-written agent from breaking the pipeline on day one
