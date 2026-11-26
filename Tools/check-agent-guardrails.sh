#!/bin/bash
#
# Mechanical checks for the Agent Operating Contract in AGENTS.md.
#
# Usage:
#   Tools/check-agent-guardrails.sh                 # check staged changes (pre-commit)
#   Tools/check-agent-guardrails.sh --range A..B    # check every commit in a range (pre-push, CI)
#
# Checks:
#   1. A change to code, tooling, build settings or app assets includes a trail entry,
#      Documentation/trail/YYYY-MM-DD-<slug>.md, and every touched entry has every
#      section of Documentation/trail/TEMPLATE.md.
#   2. A change to Swift or tool sources also changes a test, or its trail entry
#      says why not on a line starting with "- **No new tests:**".
#   3. .claude/settings.json still denies the Agent tool (no subagents).
#   4. The Quran app (QuranEngine, Example/) never depends on the Arabican app's package:
#      no Swift file outside ArabicLearning/ and Apps/Arabican/ imports an ArabicLearning
#      module, and the root Package.swift and Example project never name ArabicLearning.
#
# Package.swift enforces layer dependencies itself (validateDependenciesStructure), and
# `make format-lint` enforces style, so they are not repeated here.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mode="staged"
range=""
case "${1:-}" in
    "" | --staged) ;;
    --range)
        mode="range"
        range="${2:-}"
        if [ -z "$range" ]; then
            echo "usage: $0 [--staged | --range <rev-range>]" >&2
            exit 2
        fi
        ;;
    -h | --help)
        sed -n '2,21p' "$0"
        exit 0
        ;;
    *)
        echo "usage: $0 [--staged | --range <rev-range>]" >&2
        exit 2
        ;;
esac

failures=0
fail() {
    echo "guardrail: $*" >&2
    failures=$((failures + 1))
}

# A path needs a trail entry when it can change the shipped app, its build, or agent rules.
needs_trail() {
    case "$1" in
        Documentation/trail/*) return 1 ;;
        Core/* | Model/* | Data/* | Domain/* | UI/* | Features/* | Example/* | AllTargetsTests/*) return 0 ;;
        ArabicLearning/* | Apps/*) return 0 ;;
        Tools/* | Branding/* | .github/* | .claude/* | .githooks/*) return 0 ;;
        Package.swift | Package.resolved | Makefile | QuranEngine-Package.xctestplan) return 0 ;;
        .swiftformat | .swiftlint.yml | .swift-version | AGENTS.md) return 0 ;;
        *) return 1 ;;
    esac
}

# A path is a test when it lives in a Tests target or is a tool test.
is_test() {
    case "$1" in
        */Tests/* | AllTargetsTests/* | Tools/*.test.*) return 0 ;;
        *) return 1 ;;
    esac
}

# A path is source whose behavior tests should cover.
is_source() {
    case "$1" in
        */Tests/* | AllTargetsTests/* | Tools/*.test.*) return 1 ;;
        *.swift | Tools/*.sh | Tools/lib/*.sh | Tools/*.mjs | Tools/*.pl | Tools/learning/*.py) return 0 ;;
        *) return 1 ;;
    esac
}

is_trail_entry() {
    [[ "$1" =~ ^Documentation/trail/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]*\.md$ ]]
}

REQUIRED_SECTIONS=("## Context" "## Decisions" "## Trade-offs" "## Changes" "## Tests" "## Validation" "## Release" "## Follow-ups")

# check_changeset <label> <name-status listing> <reader function>
check_changeset() {
    local label="$1" listing="$2" reader="$3"
    local status path rest needs=0 has_source=0 has_test=0
    local trails=()

    while IFS=$'\t' read -r status path rest; do
        [ -n "${status:-}" ] || continue
        # Renames and copies report "R100<TAB>old<TAB>new"; use the destination.
        if [[ "$status" == R* || "$status" == C* ]]; then
            path="$rest"
        fi
        if [ "$status" != D ] && is_trail_entry "$path"; then
            trails+=("$path")
        fi
        needs_trail "$path" && needs=1
        is_source "$path" && has_source=1
        is_test "$path" && has_test=1
    done <<< "$listing"

    if [ "$needs" = 1 ] && [ "${#trails[@]}" = 0 ]; then
        fail "$label changes code or tooling but adds or updates no Documentation/trail/YYYY-MM-DD-<slug>.md entry"
    fi

    local trail content section justified=0
    for trail in ${trails[@]+"${trails[@]}"}; do
        content="$("$reader" "$trail")"
        for section in "${REQUIRED_SECTIONS[@]}"; do
            if ! grep -qxF "$section" <<< "$content"; then
                fail "$label: $trail is missing the '$section' section (copy Documentation/trail/TEMPLATE.md)"
            fi
        done
        if grep -qE '^- \*\*No new tests:\*\* .{10,}' <<< "$content"; then
            justified=1
        fi
    done

    if [ "$has_source" = 1 ] && [ "$has_test" = 0 ] && [ "$justified" = 0 ]; then
        fail "$label changes source but no test; add one, or explain on a '- **No new tests:** <why>' line in its trail entry"
    fi
}

check_no_subagents() {
    # $1 = settings.json content
    if ! grep -qE '"deny"[[:space:]]*:[[:space:]]*\[[^]]*"Agent"' <<< "$(tr -d '\n' <<< "$1")"; then
        fail ".claude/settings.json must keep \"Agent\" in permissions.deny (AGENTS.md: no subagents)"
    fi
}

# ArabicLearning modules: every target under ArabicLearning/Sources.
ARABICAN_IMPORT_PATTERN='^[[:space:]]*(@testable[[:space:]]+|@preconcurrency[[:space:]]+)?import[[:space:]]+(Learning[A-Za-z]*|ExerciseKit|ArabicScript)([^[:alnum:]_]|$)'

# check_quran_app_independent <tree-ish or empty for the index>
check_quran_app_independent() {
    local tree="$1" matches
    # The index (git grep --cached) in staged mode, the tip commit in range mode.
    local before=(--cached) after=()
    if [ -n "$tree" ]; then
        before=()
        after=("$tree")
    fi
    matches="$(git grep ${before[@]+"${before[@]}"} -nE "$ARABICAN_IMPORT_PATTERN" ${after[@]+"${after[@]}"} -- '*.swift' ':(exclude)ArabicLearning/*' ':(exclude)Apps/Arabican/*' || true)"
    if [ -n "$matches" ]; then
        fail "the Quran app must not import Arabican (ArabicLearning) modules: $matches"
    fi
    matches="$(git grep ${before[@]+"${before[@]}"} -n "ArabicLearning" ${after[@]+"${after[@]}"} -- Package.swift 'Example/*.pbxproj' || true)"
    if [ -n "$matches" ]; then
        fail "QuranEngine's Package.swift and the Example project must not reference ArabicLearning: $matches"
    fi
}

read_staged() { git show ":$1"; }

if [ "$mode" = staged ]; then
    listing="$(git diff --cached --name-status --find-renames)"
    if [ -n "$listing" ]; then
        check_changeset "staged changes" "$listing" read_staged
    fi
    if [ -f .claude/settings.json ]; then
        check_no_subagents "$(git show :.claude/settings.json 2>/dev/null || cat .claude/settings.json)"
    else
        fail ".claude/settings.json is missing"
    fi
    check_quran_app_independent ""
else
    for commit in $(git rev-list --reverse --no-merges "$range"); do
        listing="$(git diff-tree --no-commit-id --name-status --find-renames -r "$commit")"
        subject="$(git log -1 --format=%s "$commit")"
        read_commit() { git show "$commit:$1"; }
        check_changeset "commit ${commit:0:10} ($subject)" "$listing" read_commit
    done
    tip="$(git rev-parse "${range##*..}")"
    check_no_subagents "$(git show "$tip:.claude/settings.json" 2>/dev/null || true)"
    check_quran_app_independent "$tip"
fi

if [ "$failures" -gt 0 ]; then
    echo "guardrail: $failures problem(s) found. See AGENTS.md > Agent operating contract." >&2
    exit 1
fi
echo "guardrail: ok ($mode${range:+ $range})"
