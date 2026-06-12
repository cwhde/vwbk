#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local dockerfile="$1"
  local name="$2"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if ! timeout 120 sudo docker build -f "$dockerfile" -t "vwbk-test-${name}" "$SCRIPT_DIR" > /dev/null 2>&1; then
    echo "❌ $name: BUILD FAILED/TIMEOUT"
    TOTAL_FAIL=$((TOTAL_FAIL+1))
    return
  fi

  if timeout 60 sudo docker run --rm \
    -v "${SCRIPT_DIR}/test_vwbk.sh:/tmp/test_vwbk.sh:ro" \
    "vwbk-test-${name}" \
    bash /tmp/test_vwbk.sh; then
    echo "✅ $name: ALL PASSED"
    TOTAL_PASS=$((TOTAL_PASS+1))
  else
    echo "❌ $name: TESTS FAILED/TIMEOUT"
    TOTAL_FAIL=$((TOTAL_FAIL+1))
  fi
}

echo "=== vwbk Multi-Platform Test Suite ==="

run_test "Dockerfile.alpine" "alpine"
run_test "Dockerfile.debian" "debian"
run_test "Dockerfile.fedora" "fedora"

echo ""
echo "=========================================="
echo "  $TOTAL_PASS platform(s) passed, $TOTAL_FAIL failed"
echo "=========================================="
[[ $TOTAL_FAIL -eq 0 ]] && exit 0 || exit 1
