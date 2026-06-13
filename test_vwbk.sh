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
grep -q 'vwbk_key_type: password' "${KEY_BASE}.pub" && pass ".pub has key_type comment" || fail ".pub key_type comment missing"

# 2. Encrypt
echo "--- 2. Encrypt ---"
OUT="${TEST_DIR}/out"; mkdir -p "$OUT"
vwbk encrypt "${KEY_BASE}.pub" "$SRC" "$OUT"
BACKUP=$(find "$OUT" -name "*.vwbk" -type f | head -1)
[[ -n "$BACKUP" ]] && pass "backup file created" || fail "no backup file"
tar -tf "$BACKUP" | grep -q 'meta.txt' && pass "meta.txt in tar" || fail "meta.txt missing in tar"
tar -tf "$BACKUP" | grep -q 'data.tar.gz.age' && pass "data.tar.gz.age in tar" || fail "data.tar.gz.age missing in tar"
tar -tf "$BACKUP" | grep -q 'identity.key' && pass "identity.key embedded in tar" || fail "identity.key missing in tar"

# 3. Inspect
echo "--- 3. Inspect ---"
META_KEY=$(vwbk inspect "$BACKUP" | grep '^key_type:' | awk '{print $2}')
[[ "$META_KEY" == "password" ]] && pass "key_type=password" || fail "key_type=$META_KEY"
vwbk inspect "$BACKUP" >/dev/null && pass "inspect runs on file" || fail "inspect failed"

# 4. Decrypt with key_path
echo "--- 4. Decrypt (with key_path) ---"
DEC="${TEST_DIR}/dec"; mkdir -p "$DEC"
printf 'testpass123\n' | script -qc "vwbk decrypt '$BACKUP' '$DEC' '${KEY_BASE}.key'" /dev/null >/dev/null
[[ -f "${DEC}/src/file1.txt" ]] && pass "file1.txt" || fail "file1.txt missing"
[[ -f "${DEC}/src/sub/file2.txt" ]] && pass "file2.txt" || fail "file2.txt missing"
grep -q "hello world" "${DEC}/src/file1.txt" && pass "content ok" || fail "content wrong"

# 4b. Decrypt with embedded key (no key_path provided)
echo "--- 4b. Decrypt (with embedded key) ---"
DEC_EMB="${TEST_DIR}/dec_emb"; mkdir -p "$DEC_EMB"
# Move original key file away to verify vwbk uses the embedded one
mv "${KEY_BASE}.key" "${KEY_BASE}.key.backup"
printf 'testpass123\n' | script -qc "vwbk decrypt '$BACKUP' '$DEC_EMB'" /dev/null >/dev/null
mv "${KEY_BASE}.key.backup" "${KEY_BASE}.key"
[[ -f "${DEC_EMB}/src/file1.txt" ]] && pass "file1.txt (embedded)" || fail "file1.txt missing (embedded)"
[[ -f "${DEC_EMB}/src/sub/file2.txt" ]] && pass "file2.txt (embedded)" || fail "file2.txt missing (embedded)"
grep -q "hello world" "${DEC_EMB}/src/file1.txt" && pass "content ok (embedded)" || fail "content wrong (embedded)"

# 5. Encrypt rejects .key
echo "--- 5. Encrypt rejects .key ---"
OUT2="${TEST_DIR}/out2"; mkdir -p "$OUT2"
ERR=$(vwbk encrypt "${KEY_BASE}.key" "$SRC" "$OUT2" 2>&1 || true)
echo "$ERR" | grep -qi "private key" && pass "rejects .key" || fail "did not reject .key"

# 6. Decrypt rejects invalid path
echo "--- 6. Decrypt invalid path ---"
ERR=$(vwbk decrypt "${TEST_DIR}/nonexistent" "${TEST_DIR}/dec4" 2>&1 || true)
echo "$ERR" | grep -q "does not exist\|neither a file\|not a valid\|missing" && pass "rejects bad path" || fail "did not reject bad path"

# 7. Backward Compatibility (Directory-based backup decryption)
echo "--- 7. Backward Compatibility ---"
LEGACY_DIR="${TEST_DIR}/legacy_backup.vwbk"
mkdir -p "$LEGACY_DIR"
cat <<EOF > "${LEGACY_DIR}/meta.txt"
vwbk_version: 1.7.0
key_name: legacy
key_type: password
timestamp: legacy_ts
original_path: ${SRC}
input_type: folder
EOF
parent_dir=$(dirname "$(realpath "$SRC")")
base_dir=$(basename "$(realpath "$SRC")")
tar -czf - -C "$parent_dir" "$base_dir" | age -r "$(grep '^age1' "${KEY_BASE}.pub")" -o "${LEGACY_DIR}/data.tar.gz.age"

DEC_LEGACY="${TEST_DIR}/dec_legacy"; mkdir -p "$DEC_LEGACY"
printf 'testpass123\n' | script -qc "vwbk decrypt '$LEGACY_DIR' '$DEC_LEGACY' '${KEY_BASE}.key'" /dev/null >/dev/null
[[ -f "${DEC_LEGACY}/src/file1.txt" ]] && pass "legacy file1.txt" || fail "legacy file1.txt missing"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
