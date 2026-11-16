#!/usr/bin/env bash
# The full pre-commit gate in one run: format, analyze, test.
# The test suite is kept outside the repository, so formatting and tests
# cover test/ only when a local copy is there.
# It prints one line per passing step and the details only for a failing
# one, so an agent's context grows by a few lines, not a full test log.
set -uo pipefail
cd "$(dirname "$0")/.."

format_code() {
  local targets=(lib)
  if [[ -d test ]]; then
    targets+=(test)
  fi
  fvm dart format "${targets[@]}" | tail -1
}

analyze_code() {
  local report
  if report=$(fvm flutter analyze 2>&1); then
    echo "analyze: no issues"
    return 0
  fi
  echo "$report" | grep -E '^\s*(error|warning|info) •|issues? found'
  return 1
}

run_tests() {
  if [[ ! -d test ]]; then
    echo "test: skipped (no test folder)"
    return 0
  fi
  if fvm flutter test --reporter failures-only >/tmp/status_studio_test.log 2>&1; then
    echo "test: $(grep -Eo '\+[0-9]+' /tmp/status_studio_test.log | tail -1 | tr -d +) passed"
    return 0
  fi
  grep -vE '^\s*$' /tmp/status_studio_test.log | tail -60
  return 1
}

format_code
analyze_code || exit 1
run_tests || exit 1
