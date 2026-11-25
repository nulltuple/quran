# Change trail

Every feature, fix, refactor and tooling change has an entry here. Agents write the entry while
they work and commit it with the change, so the next agent can recover the context, decisions
and trade-offs without the original conversation.

The trail starts on 2026-11-24, when this fork became agent-only. Earlier history is upstream
QuranEngine work: read it with `git log` and the pull requests it links (`quran/quran-ios`).

## Rules

- One file per change: `YYYY-MM-DD-<kebab-slug>.md`, copied from [TEMPLATE.md](TEMPLATE.md).
  Every template section is required; `Tools/check-agent-guardrails.sh` rejects a code commit
  without a complete entry.
- Commit the entry with the code, and name it in the commit message: `Trail: Documentation/trail/<file>.md`.
- Recording release facts afterwards (pushed SHA, TestFlight build) is a trail-only commit:
  `docs(trail): record TestFlight build for <slug>`.
- Never rewrite an old entry's history. Add a new entry and set the old one's **Status** to
  `superseded by <new entry>`.
- No secrets, tokens, personal data or user content.

## Finding context

```sh
grep -ril "<area or symbol>" Documentation/trail        # entries that touched an area
ls Documentation/trail | sort | tail -20                # most recent work
grep -rn "^- \*\*Status:\*\* in-progress" Documentation/trail   # unfinished work
grep -rn -A4 "^## Follow-ups" Documentation/trail       # open follow-ups
```

## Index

Newest first. Add one line per entry.

- [2026-11-24 — Word-by-word recitation highlighting and word meanings from QUL](2026-11-24-word-by-word-recitation.md)
- [2026-11-24 — Agent-only contract, change trail, Quran rebrand and TestFlight path](2026-11-24-agentic-contract-rebrand-testflight.md)
