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
[[ -f "${KEY_BASE}.vwbkey" ]] && pass ".vwbkey created" || fail ".vwbkey missing"
tar -tf "${KEY_BASE}.vwbkey" | grep 'key.pub' >/dev/null && pass "key.pub in .vwbkey" || { fail "key.pub missing in .vwbkey"; tar -tf "${KEY_BASE}.vwbkey"; }
tar -tf "${KEY_BASE}.vwbkey" | grep 'key.key' >/dev/null && pass "key.key in .vwbkey" || { fail "key.key missing in .vwbkey"; tar -tf "${KEY_BASE}.vwbkey"; }

# Extract key.pub from tar to check if it contains the public key and comment
tar -O -xf "${KEY_BASE}.vwbkey" ./key.pub 2>/dev/null | grep -q '^age1' && pass "key.pub has valid key" || fail "key.pub has no valid key"
tar -O -xf "${KEY_BASE}.vwbkey" ./key.pub 2>/dev/null | grep -q 'vwbk_key_type: password' && pass "key.pub has key_type comment" || fail "key.pub comment missing"

# 2. Encrypt
echo "--- 2. Encrypt ---"
OUT="${TEST_DIR}/out"; mkdir -p "$OUT"
vwbk encrypt "${KEY_BASE}.vwbkey" "$SRC" "$OUT"
BACKUP=$(find "$OUT" -name "*.vwbk" -type f | head -1)
[[ -n "$BACKUP" ]] && pass "backup file created" || fail "no backup file"
tar -tf "$BACKUP" | grep 'meta.txt' >/dev/null && pass "meta.txt in tar" || fail "meta.txt missing in tar"
tar -tf "$BACKUP" | grep 'data.tar.gz.age' >/dev/null && pass "data.tar.gz.age in tar" || fail "data.tar.gz.age missing in tar"
tar -tf "$BACKUP" | grep 'identity.key' >/dev/null && pass "identity.key embedded in tar" || fail "identity.key missing in tar"

# 3. Inspect
echo "--- 3. Inspect ---"
META_KEY=$(vwbk inspect "$BACKUP" | grep '^key_type:' | awk '{print $2}')
[[ "$META_KEY" == "password" ]] && pass "key_type=password" || fail "key_type=$META_KEY"
vwbk inspect "$BACKUP" >/dev/null && pass "inspect runs on file" || fail "inspect failed"

# 4. Decrypt with key_path (.vwbkey)
echo "--- 4. Decrypt (with key_path as .vwbkey) ---"
DEC="${TEST_DIR}/dec"; mkdir -p "$DEC"
printf 'testpass123\n' | script -qc "vwbk decrypt '$BACKUP' '$DEC' '${KEY_BASE}.vwbkey'" /dev/null >/dev/null
[[ -f "${DEC}/src/file1.txt" ]] && pass "file1.txt" || fail "file1.txt missing"
[[ -f "${DEC}/src/sub/file2.txt" ]] && pass "file2.txt" || fail "file2.txt missing"
grep -q "hello world" "${DEC}/src/file1.txt" && pass "content ok" || fail "content wrong"

# 4b. Decrypt with embedded key (no key_path provided)
echo "--- 4b. Decrypt (with embedded key) ---"
DEC_EMB="${TEST_DIR}/dec_emb"; mkdir -p "$DEC_EMB"
# Move original vwbkey file away to verify vwbk uses the embedded one
mv "${KEY_BASE}.vwbkey" "${KEY_BASE}.vwbkey.backup"
printf 'testpass123\n' | script -qc "vwbk decrypt '$BACKUP' '$DEC_EMB'" /dev/null >/dev/null
mv "${KEY_BASE}.vwbkey.backup" "${KEY_BASE}.vwbkey"
[[ -f "${DEC_EMB}/src/file1.txt" ]] && pass "file1.txt (embedded)" || fail "file1.txt missing (embedded)"
[[ -f "${DEC_EMB}/src/sub/file2.txt" ]] && pass "file2.txt (embedded)" || fail "file2.txt missing (embedded)"
grep -q "hello world" "${DEC_EMB}/src/file1.txt" && pass "content ok (embedded)" || fail "content wrong (embedded)"

# 5. Encrypt rejects .key
echo "--- 5. Encrypt rejects .key ---"
EXTRACT_DIR="${TEST_DIR}/extract_key"
mkdir -p "$EXTRACT_DIR"
tar -xf "${KEY_BASE}.vwbkey" -C "$EXTRACT_DIR"
OUT2="${TEST_DIR}/out2"; mkdir -p "$OUT2"
ERR=$(vwbk encrypt "${EXTRACT_DIR}/key.key" "$SRC" "$OUT2" 2>&1 || true)
echo "$ERR" | grep -qi "private key" && pass "rejects .key" || fail "did not reject .key"

# 6. Decrypt rejects invalid path
echo "--- 6. Decrypt invalid path ---"
ERR=$(vwbk decrypt "${TEST_DIR}/nonexistent" "${TEST_DIR}/dec4" 2>&1 || true)
echo "$ERR" | grep -q "does not exist\|neither a file\|not a valid\|missing" && pass "rejects bad path" || fail "did not reject bad path"

# 7. Backward Compatibility (Directory-based backup decryption and separate key files)
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
tar -czf - -C "$parent_dir" "$base_dir" | age -r "$(grep '^age1' "${EXTRACT_DIR}/key.pub")" -o "${LEGACY_DIR}/data.tar.gz.age"

DEC_LEGACY="${TEST_DIR}/dec_legacy"; mkdir -p "$DEC_LEGACY"
printf 'testpass123\n' | script -qc "vwbk decrypt '$LEGACY_DIR' '$DEC_LEGACY' '${EXTRACT_DIR}/key.key'" /dev/null >/dev/null
[[ -f "${DEC_LEGACY}/src/file1.txt" ]] && pass "legacy file1.txt" || fail "legacy file1.txt missing"

# 8. Self-Update Command
echo "--- 8. Self-Update ---"
TEST_UP_DIR="${TEST_DIR}/test_up"
mkdir -p "$TEST_UP_DIR"
cp "$(command -v vwbk || echo './vwbk')" "$TEST_UP_DIR/vwbk"
# Update to a specific historical version to verify it succeeds and replaces the file
if "$TEST_UP_DIR/vwbk" update v1.7.10 >/dev/null 2>&1; then
  "$TEST_UP_DIR/vwbk" help | head -n 1 | grep 'v1.7.10' >/dev/null && pass "update command to specific version works" || fail "update failed to replace version"
else
  fail "update command to specific version failed to execute"
fi
# Reset the temp script back to our local version so we run the fixed update command again
cp "$(command -v vwbk || echo './vwbk')" "$TEST_UP_DIR/vwbk"
# Update to latest version from GitHub (should be v1.7.13)
if "$TEST_UP_DIR/vwbk" update >/dev/null 2>&1; then
  "$TEST_UP_DIR/vwbk" help | head -n 1 | grep 'v1.7.13' >/dev/null && pass "update command to latest works" || fail "update to latest failed to replace version"
else
  fail "update command to latest failed to execute"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
