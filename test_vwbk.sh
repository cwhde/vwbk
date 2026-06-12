#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(mktemp -d)
echo "=== vwbk Full Test Suite ==="
echo "Temp dir: $TEST_DIR"
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }

SRC="${TEST_DIR}/src"
mkdir -p "$SRC/sub"
echo "hello world" > "$SRC/file1.txt"
echo "nested data" > "$SRC/sub/file2.txt"
KEY_BASE="${TEST_DIR}/mykey"

# 1. Enroll
echo "--- 1. Enroll (password) ---"
printf 'testpass123\ntestpass123\n' | script -qc "vwbk enroll $KEY_BASE password" /dev/null >/dev/null
[[ -f "${KEY_BASE}.key" ]] && pass ".key created" || fail ".key missing"
[[ -f "${KEY_BASE}.pub" ]] && pass ".pub created" || fail ".pub missing"
grep -q '^age1' "${KEY_BASE}.pub" && pass ".pub has valid key" || fail ".pub has no valid key"

# 2. Encrypt
echo "--- 2. Encrypt ---"
OUT="${TEST_DIR}/out"; mkdir -p "$OUT"
vwbk encrypt "${KEY_BASE}.pub" "$SRC" "$OUT"
BACKUP=$(find "$OUT" -name "*.vwbk" -type d | head -1)
[[ -n "$BACKUP" ]] && pass "backup dir created" || fail "no backup dir"
[[ -f "${BACKUP}/meta.txt" ]] && pass "meta.txt" || fail "meta.txt missing"
[[ -f "${BACKUP}/data.tar.gz.age" ]] && pass "data.tar.gz.age" || fail "data.tar.gz.age missing"

# 3. Inspect
echo "--- 3. Inspect ---"
META_KEY=$(grep '^key_type:' "${BACKUP}/meta.txt" | awk '{print $2}')
[[ "$META_KEY" == "password" ]] && pass "key_type=password" || fail "key_type=$META_KEY"
vwbk inspect "$BACKUP" >/dev/null && pass "inspect runs" || fail "inspect failed"

# 4. Decrypt with key_path
echo "--- 4. Decrypt (with key_path) ---"
DEC="${TEST_DIR}/dec"; mkdir -p "$DEC"
printf 'testpass123\n' | script -qc "vwbk decrypt '$BACKUP' '$DEC' '${KEY_BASE}.key'" /dev/null >/dev/null
[[ -f "${DEC}/src/file1.txt" ]] && pass "file1.txt" || fail "file1.txt missing"
[[ -f "${DEC}/src/sub/file2.txt" ]] && pass "file2.txt" || fail "file2.txt missing"
grep -q "hello world" "${DEC}/src/file1.txt" && pass "content ok" || fail "content wrong"

# 5. Encrypt rejects .key
echo "--- 5. Encrypt rejects .key ---"
OUT2="${TEST_DIR}/out2"; mkdir -p "$OUT2"
ERR=$(vwbk encrypt "${KEY_BASE}.key" "$SRC" "$OUT2" 2>&1 || true)
echo "$ERR" | grep -qi "private key" && pass "rejects .key" || fail "did not reject .key"

# 6. Decrypt rejects invalid path
echo "--- 6. Decrypt invalid path ---"
ERR=$(vwbk decrypt "${TEST_DIR}/nonexistent" "${TEST_DIR}/dec4" 2>&1 || true)
echo "$ERR" | grep -q "does not exist\|not a directory\|not a valid\|missing" && pass "rejects bad path" || fail "did not reject bad path"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
