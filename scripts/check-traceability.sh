#!/usr/bin/env bash
# Traceability audit (R-16, T-003/T-080).
#  - every AC in spec.md is referenced by >= 1 automated test (unit, UI, or scripts/checks/*.sh)
#    or by a documented manual/device check in specs/dashcam/manual-checks.md
#  - every test function references an AC (name `test_ACxxx_` or a `// AC-xxx` comment right above it)
#  - every AC referenced by tests/checks exists in spec.md
#  - no open Q-xxx in spec.md; lists unchecked tasks and assumptions
set -euo pipefail
cd "$(dirname "$0")/.."

SPEC=specs/dashcam/spec.md
TASKS=specs/dashcam/tasks.md
MANUAL=specs/dashcam/manual-checks.md
fail=0

spec_acs=$(grep -oE '\*\*AC-[0-9]{3}\*\*' "$SPEC" | grep -oE '[0-9]{3}' | sort -u)
test_files=$(find SpeedCamTests SpeedCamUITests -name '*.swift' 2>/dev/null; ls scripts/checks/*.sh 2>/dev/null || true)

# AC refs in automated tests: `AC-045`, `AC045`, ranges are not accepted (each AC must be named).
auto_refs=$(cat $test_files | grep -oE 'AC-?[0-9]{3}' | grep -oE '[0-9]{3}' | sort -u)
manual_refs=""
if [[ -f "$MANUAL" ]]; then
  manual_refs=$(grep -oE 'AC-[0-9]{3}' "$MANUAL" | grep -oE '[0-9]{3}' | sort -u)
fi

total=0; covered_auto=0; covered_manual=0
missing=()
for ac in $spec_acs; do
  total=$((total+1))
  if grep -qx "$ac" <<<"$auto_refs"; then
    covered_auto=$((covered_auto+1))
  elif [[ -n "$manual_refs" ]] && grep -qx "$ac" <<<"$manual_refs"; then
    covered_manual=$((covered_manual+1))
  else
    missing+=("AC-$ac")
  fi
done

unknown=()
for ac in $auto_refs $manual_refs; do
  grep -qx "$ac" <<<"$spec_acs" || unknown+=("AC-$ac")
done

# Every XCTest function must name an AC in its name or in a `// AC-xxx` comment within the 3 lines above.
untagged=()
while IFS= read -r f; do
  [[ "$f" == *.swift ]] || continue
  while IFS=: read -r line _; do
    name=$(sed -n "${line}p" "$f" | grep -oE 'func test[A-Za-z0-9_]*' | sed 's/func //')
    if grep -qE 'AC-?[0-9]{3}' <<<"$name"; then continue; fi
    start=$((line>3 ? line-3 : 1))
    if sed -n "${start},${line}p" "$f" | grep -qE '//.*AC-[0-9]{3}'; then continue; fi
    untagged+=("$f:$line $name")
  done < <(grep -nE '^\s*(@MainActor\s+)?func test' "$f" || true)
done <<<"$test_files"

tests_count=$(cat $test_files | grep -cE '^\s*(@MainActor\s+)?func test' || true)
checks_count=$( (ls scripts/checks/*.sh 2>/dev/null || true) | wc -l | tr -d ' ')

echo "Traceability audit"
echo "  ACs in spec:              $total"
echo "  covered by automated test: $covered_auto"
echo "  covered by manual check:   $covered_manual"
echo "  test functions:            $tests_count (+ $checks_count script checks)"

if (( ${#missing[@]} )); then echo "FAIL: ACs with no test or manual check: ${missing[*]}"; fail=1; fi
if (( ${#unknown[@]} )); then echo "FAIL: references to ACs not in spec: $(printf '%s\n' "${unknown[@]}" | sort -u | tr '\n' ' ')"; fail=1; fi
if (( ${#untagged[@]} )); then echo "FAIL: tests without an AC reference:"; printf '    %s\n' "${untagged[@]}"; fail=1; fi

open_q=$(awk '/^## 5\. Questions/{q=1} q && /\*\*Q-[0-9]{3}\*\*/ && !/Resolved/' "$SPEC" | grep -oE 'Q-[0-9]{3}' || true)
if [[ -n "$open_q" ]]; then echo "FAIL: open questions: $open_q"; fail=1; else echo "  open questions:            none"; fi

unchecked=$(grep -E '^- \[ \] T-[0-9]{3}' "$TASKS" | grep -oE 'T-[0-9]{3}' | tr '\n' ' ' || true)
echo "  unchecked tasks:           ${unchecked:-none}"
echo "  assumptions:               $(grep -oE '\*\*ASM-[0-9]{3}\*\*' "$SPEC" | tr -d '*' | tr '\n' ' ')"

if (( fail )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS"
