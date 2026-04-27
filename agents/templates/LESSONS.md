# Project Lessons (Auto-improving memory)

Agents append to this file when they find patterns worth remembering. Future sessions read these before working — that's how the pipeline gets smarter over time at zero infrastructure cost.

## Tag taxonomy

Use these tags so agents can filter relevant lessons:

- `[security]` `[auth]` `[secrets]` `[injection]` `[xss]` `[csrf]`
- `[performance]` `[database]` `[frontend]` `[bundle]` `[cache]`
- `[bug]` `[race-condition]` `[edge-case]` `[null-safety]` `[concurrency]`
- `[architecture]` `[design]` `[refactor]` `[coupling]`
- `[testing]` `[a11y]` `[rbac]` `[e2e]`
- `[dependencies]` `[cve]` `[license]` `[supply-chain]`
- `[ui]` `[api]` `[mobile]` `[email]` `[payment]` (domain-specific)

## Format

```
## YYYY-MM-DD — agent-name [tag] [tag] [tag]
- What was found / decided
- LESSON: <generalized rule for future tasks>
```

## Auto-condensation

When this file exceeds 300 lines:
1. Coordinator backs up to LESSONS.md.archive-YYYY-MM-DD-HHMM
2. Groups by tag
3. Patterns appearing 3+ times → condensed into one rule under `# Condensed Patterns`
4. Last 30 days kept verbatim under `# Recent Entries`
5. CVE refs, exact secret patterns, file paths mentioned 2+ times preserved

---

# Recent Entries

(empty — fills as agents work)
