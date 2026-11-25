# <Title: what changed, in a few words>

- **Date:** YYYY-MM-DD
- **Agent:** <harness and model, e.g. Claude Code / claude-opus-5-5>
- **Type:** feature | fix | refactor | tooling | docs | release
- **Status:** in-progress | shipped | reverted | superseded by <entry>
- **Related:** <earlier trail entries, issues, PRs, upstream commits, or "None">

## Context

Why this change exists: the owner's request (quote the words that matter), the problem
observed, and the evidence (`path:line`, logs, measurements). Mark anything you could not
verify as UNVERIFIED.

## Decisions

Each non-obvious choice, the alternatives considered, and why this one won. List product
assumptions you made without asking.

## Trade-offs

- **Complexity added:** files and lines, dependencies, permissions, entitlements, background
  work, persisted state, new failure modes.
- **Who benefits / how often:** call out rarely used features explicitly.
- **Rejected cheaper options:** and why.
- **Ongoing cost:** maintenance, launch time, memory, binary size, review burden.

## Changes

Files and symbols touched, grouped by purpose, one line each. Name the shared code you reused
or extended instead of duplicating, and the platforms (iPhone, iPad, Mac) each change affects.

## Tests

Tests added or changed (target and test names), and for a bug fix how the regression test was
shown to fail without the fix. If no test changed, replace this paragraph with a line that
starts `- **No new tests:**` followed by the reason; the guardrail requires one or the other.

## Validation

- **Verified:** exact commands and their result lines (for example `Executed 812 tests, with 0
  failures`).
- **Not verified:** what still needs hands-on checking (device behavior, VoiceOver, Dynamic
  Type, performance) and why it was not done.

## Release

- **Commit:** <sha>
- **Pushed:** origin/main at <sha>
- **TestFlight:** build <CFBundleVersion> (<marketing version>) and the upload line, or why no
  build was uploaded.
- **iCloud / CloudKit schema:** unchanged | changed: owner deployment required (see
  Documentation/agents/release-testflight.md#icloud-and-cloudkit-schema).

## Follow-ups

Remaining work, known gaps, and suggested next steps, or "None".
