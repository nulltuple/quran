# Prioritized Quran competitive roadmap

- **Date:** 2026-11-24
- **Agent:** ChatGPT / GPT-6.2
- **Type:** docs
- **Status:** shipped
- **Related:** [Word-by-word recitation](2026-11-24-word-by-word-recitation.md), [agent contract](2026-11-24-agentic-contract-rebrand-testflight.md)

## Context

Owner requested adversarial review, priority order, spec on main and Claude implementation prompt; explicitly said licensing is not a priority at this point. Baseline main e18de36e; functional commit 6597d965. Inspected source tree, Container.swift, AyahMenuViewModel.swift, HomeViewModel.swift, MoreMenuViewModel.swift, audio/search modules and both prior trails. Competitor public feature claims are linked in spec; no hands-on validation.

## Decisions

Prioritize canonical word identity and pointer correctness, resource packs, local data durability, manual Hifz, linguistic study, similar passages, goals, reader polish, bounded ASR spike, live alignment, mistakes, sync, optional study and Apple integrations, then separate Tajweed research. Formal licensing review deferred by owner; not a milestone or implementation gate. Additional platform/dependency/permission changes require existing owner approvals. Do not duplicate existing upstream features.

## Trade-offs

- **Complexity added:** documentation only (spec, trail and index); no runtime, dependency, permission, entitlement or persisted state change.
- **Who benefits / how often:** future agents and owner; no measured usage. Rare features deferred, particularly Apple Pencil, additional platforms and advanced pronunciation.
- **Rejected cheaper options:** unordered feature checklist without gates; direct AI implementation before verified word IDs and manual practice; broad release audit before requested functionality.
- **Ongoing cost:** maintain milestone evidence, test and cost register per slice; no app launch, size or battery cost from docs.

## Changes

- Documentation/agents/quran-prioritized-roadmap.md: prioritized requirements, dependencies, acceptance criteria, failure modes and scope.
- Documentation/trail/README.md: index entry.

## Tests

- **No new tests:** documentation-only planning change, no source or tooling behavior changes.

## Validation

- **Verified:** inspected main e18de36e, source tree, source files and prior implementation trail via GitHub; public GreenTech, Tarteel, Quranly and Quran.com descriptions checked. Spec references existing AGENTS.md and Make commands.
- **Not verified:** Xcode, local git hooks, make format-lint, package tests/builds and guardrails cannot run in GitHub connector-only environment; no app changes. Prior tests/upload are reported in existing trail, not rerun. Device UX, model feasibility and estimates remain unverified.

## Release

- **Commit:** this documentation commit (self-reference omitted).
- **Pushed:** intended origin/main via non-force fast-forward; verify branch head after update.
- **TestFlight:** not required for documentation-only change per AGENTS.md.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

Implement M1 then subsequent slices as defined in spec; record blockers and exact evidence. Owner deferred licensing audit.
