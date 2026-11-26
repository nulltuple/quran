#!/bin/bash
#
# Tests Tools/check-agent-guardrails.sh against throwaway Git repositories.
# Run: bash Tools/check-agent-guardrails.test.sh (or make test-tools)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARDRAILS="$ROOT/Tools/check-agent-guardrails.sh"
TEMPLATE="$ROOT/Documentation/trail/TEMPLATE.md"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passed=0
failed=0

# new_repo: an empty repository whose settings deny subagents, with one commit.
new_repo() {
    local repo="$scratch/repo-$RANDOM$RANDOM"
    mkdir -p "$repo/.claude" "$repo/Documentation/trail"
    git -C "$repo" init --quiet
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    printf '{\n  "permissions": {\n    "deny": [\n      "Agent"\n    ]\n  }\n}\n' > "$repo/.claude/settings.json"
    echo "# Readme" > "$repo/README.md"
    git -C "$repo" add -A
    git -C "$repo" commit --quiet -m "initial"
    echo "$repo"
}

# write_trail <repo> <name> [extra line]: a complete entry built from the real template.
write_trail() {
    cp "$TEMPLATE" "$1/Documentation/trail/$2"
    if [ -n "${3:-}" ]; then
        echo "$3" >> "$1/Documentation/trail/$2"
    fi
}

# expect <pass|fail> <description> <repo> [guardrail arguments...]
expect() {
    local want="$1" description="$2" repo="$3"
    shift 3
    local output status
    set +e
    output="$(cd "$repo" && bash "$GUARDRAILS" "$@" 2>&1)"
    status=$?
    set -e
    if { [ "$want" = pass ] && [ "$status" = 0 ]; } || { [ "$want" = fail ] && [ "$status" != 0 ]; }; then
        passed=$((passed + 1))
        echo "ok - $description"
    else
        failed=$((failed + 1))
        echo "not ok - $description (exit $status)"
        echo "$output" | sed 's/^/    /'
    fi
}

# Documentation outside the trail needs no entry.
repo="$(new_repo)"
echo "more" >> "$repo/README.md"
git -C "$repo" add -A
expect pass "a README change needs no trail entry" "$repo"

# Source without a trail entry fails.
repo="$(new_repo)"
mkdir -p "$repo/Domain/Foo/Sources" "$repo/Domain/Foo/Tests"
echo "struct Foo {}" > "$repo/Domain/Foo/Sources/Foo.swift"
echo "final class FooTests {}" > "$repo/Domain/Foo/Tests/FooTests.swift"
git -C "$repo" add -A
expect fail "source without a trail entry is rejected" "$repo"

# Source, test and complete entry pass.
write_trail "$repo" "2026-01-02-add-foo.md"
git -C "$repo" add -A
expect pass "source with a test and a complete entry passes" "$repo"

# An entry missing a section fails.
grep -vxF "## Trade-offs" "$TEMPLATE" > "$repo/Documentation/trail/2026-01-02-add-foo.md"
git -C "$repo" add -A
expect fail "an entry missing Trade-offs is rejected" "$repo"

# An entry with a malformed name does not count.
repo="$(new_repo)"
mkdir -p "$repo/Tools"
echo "echo hi" > "$repo/Tools/hello.sh"
echo "echo test" > "$repo/Tools/hello.test.sh"
cp "$TEMPLATE" "$repo/Documentation/trail/Add Hello.md"
git -C "$repo" add -A
expect fail "an entry without a YYYY-MM-DD-slug name is rejected" "$repo"

# Source without a test fails unless the entry explains why.
repo="$(new_repo)"
mkdir -p "$repo/Features/Bar/Sources"
echo "struct Bar {}" > "$repo/Features/Bar/Sources/Bar.swift"
write_trail "$repo" "2026-01-03-bar.md"
git -C "$repo" add -A
expect fail "source without a test or justification is rejected" "$repo"
write_trail "$repo" "2026-01-03-bar.md" "- **No new tests:** renames a private constant; existing BarTests cover it."
git -C "$repo" add -A
expect pass "source without a test passes with a justification" "$repo"
write_trail "$repo" "2026-01-03-bar.md" "- **No new tests:** n/a"
git -C "$repo" add -A
expect fail "a one-word justification is rejected" "$repo"

# Build settings and assets need an entry but no test.
repo="$(new_repo)"
mkdir -p "$repo/Example"
echo "BUNDLE = x" > "$repo/Example/project.pbxproj"
git -C "$repo" add -A
expect fail "a project change without an entry is rejected" "$repo"
write_trail "$repo" "2026-01-04-bundle.md"
git -C "$repo" add -A
expect pass "a project change with an entry needs no test" "$repo"

# Removing the subagent deny fails.
repo="$(new_repo)"
printf '{\n  "permissions": {\n    "deny": []\n  }\n}\n' > "$repo/.claude/settings.json"
write_trail "$repo" "2026-01-05-settings.md"
git -C "$repo" add -A
expect fail "dropping Agent from permissions.deny is rejected" "$repo"

# Range mode checks each commit on its own.
repo="$(new_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$repo/Core/Baz/Sources" "$repo/Core/Baz/Tests"
echo "struct Baz {}" > "$repo/Core/Baz/Sources/Baz.swift"
echo "final class BazTests {}" > "$repo/Core/Baz/Tests/BazTests.swift"
write_trail "$repo" "2026-01-06-baz.md"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "Add Baz"
expect pass "range with a complete commit passes" "$repo" --range "$base..HEAD"
echo "// change" >> "$repo/Core/Baz/Sources/Baz.swift"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "Change Baz without a trail"
expect fail "range with a commit lacking an entry is rejected" "$repo" --range "$base..HEAD"

# A trail-only commit (recording a TestFlight build) passes.
repo="$(new_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
write_trail "$repo" "2026-01-07-release.md"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "docs(trail): record TestFlight build"
expect pass "a trail-only commit passes" "$repo" --range "$base..HEAD"

# Arabican paths need an entry; its Python tooling counts as source.
repo="$(new_repo)"
mkdir -p "$repo/ArabicLearning/Sources/LearningModel"
echo "struct Skill {}" > "$repo/ArabicLearning/Sources/LearningModel/Skill.swift"
git -C "$repo" add -A
expect fail "an ArabicLearning change without an entry is rejected" "$repo"
repo="$(new_repo)"
mkdir -p "$repo/Apps/Arabican"
echo "BUNDLE = y" > "$repo/Apps/Arabican/project.pbxproj"
git -C "$repo" add -A
expect fail "an Apps/Arabican change without an entry is rejected" "$repo"
repo="$(new_repo)"
mkdir -p "$repo/Tools/learning"
echo "print(1)" > "$repo/Tools/learning/compile.py"
write_trail "$repo" "2026-01-08-compile.md"
git -C "$repo" add -A
expect fail "learning Python tooling without a test is rejected" "$repo"
echo "print(2)" > "$repo/Tools/learning/compile.test.py"
git -C "$repo" add -A
expect pass "learning Python tooling with a .test.py passes" "$repo"

# The Quran app never imports Arabican modules or names the ArabicLearning package.
repo="$(new_repo)"
mkdir -p "$repo/Features/Qux/Sources" "$repo/Features/Qux/Tests"
printf 'import LearningUI\nstruct Qux {}\n' > "$repo/Features/Qux/Sources/Qux.swift"
echo "final class QuxTests {}" > "$repo/Features/Qux/Tests/QuxTests.swift"
write_trail "$repo" "2026-01-09-qux.md"
git -C "$repo" add -A
expect fail "a Quran module importing an ArabicLearning module is rejected" "$repo"
printf 'import UIKit\nstruct Qux {}\n' > "$repo/Features/Qux/Sources/Qux.swift"
mkdir -p "$repo/Apps/Arabican/Arabican"
printf 'import LearningUI\n' > "$repo/Apps/Arabican/Arabican/App.swift"
git -C "$repo" add -A
expect pass "the Arabican app may import ArabicLearning modules" "$repo"
echo '.package(path: "ArabicLearning")' > "$repo/Package.swift"
git -C "$repo" add -A
expect fail "the root Package.swift naming ArabicLearning is rejected" "$repo"

# Range mode checks the Quran app's independence at the tip.
repo="$(new_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$repo/Domain/Quux/Sources" "$repo/Domain/Quux/Tests"
printf 'import ArabicScript\n' > "$repo/Domain/Quux/Sources/Quux.swift"
echo "final class QuuxTests {}" > "$repo/Domain/Quux/Tests/QuuxTests.swift"
write_trail "$repo" "2026-01-10-quux.md"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "Import ArabicScript in Domain"
expect fail "range whose tip imports an ArabicLearning module in QuranEngine is rejected" "$repo" --range "$base..HEAD"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
