#!/usr/bin/env bash

# test_vwbk.sh - Local test suite for vwbk inside container

# Setup temporary test directories
TEST_DIR=$(mktemp -d)
echo "=== Running vwbk Container Test Suite ==="
echo "Temporary directory: $TEST_DIR"

# Cleanup function on exit
cleanup() {
  echo "Cleaning up temporary files..."
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 1. Test Key Enrollment (Password Mode)
echo "----------------------------------------"
echo "Testing: vwbk enroll (password mode)"
KEY_PATH="${TEST_DIR}/testkeys"
# Pipe password input twice for age -p (since age asks for password confirmation)
vwbk enroll "$KEY_PATH" password <<< $'testpassword123\ntestpassword123'

if [[ -f "${KEY_PATH}.key" && -f "${KEY_PATH}.pub" ]]; then
  echo "SUCCESS: Key files created."
  echo "Public key content:"
  cat "${KEY_PATH}.pub"
else
  echo "FAILURE: Key files not created." >&2
  exit 1
fi

# 2. Test Encryption
echo "----------------------------------------"
echo "Testing: vwbk encrypt"
SRC_DIR="${TEST_DIR}/src"
mkdir -p "$SRC_DIR"
echo "Test file content 1" > "${SRC_DIR}/file1.txt"
echo "Test file content 2" > "${SRC_DIR}/file2.txt"

OUT_DIR="${TEST_DIR}/out"
mkdir -p "$OUT_DIR"

# Run encrypt
vwbk encrypt "${KEY_PATH}.pub" "$SRC_DIR" "$OUT_DIR"

# Verify backup structure
BACKUP_DIR=$(find "$OUT_DIR" -name "*-testkeys.vwbk" -type d | head -n 1)
if [[ -n "$BACKUP_DIR" && -f "${BACKUP_DIR}/meta.txt" && -f "${BACKUP_DIR}/data.tar.gz.age" ]]; then
  echo "SUCCESS: Backup folder structured correctly."
  echo "Backup folder path: $BACKUP_DIR"
else
  echo "FAILURE: Backup structure invalid." >&2
  exit 1
fi

# 3. Test Inspection
echo "----------------------------------------"
echo "Testing: vwbk inspect"
vwbk inspect "$BACKUP_DIR"

# 4. Test Decryption
echo "----------------------------------------"
echo "Testing: vwbk decrypt"
DEC_DIR="${TEST_DIR}/dec"
mkdir -p "$DEC_DIR"

# Run decrypt
vwbk decrypt "${KEY_PATH}.key" "$BACKUP_DIR" "$DEC_DIR" <<< 'testpassword123'

# Verify decrypted contents
if [[ -f "${DEC_DIR}/src/file1.txt" && -f "${DEC_DIR}/src/file2.txt" && -f "${DEC_DIR}/vwbk-meta.txt" ]]; then
  echo "SUCCESS: Backup decrypted and verified."
  echo "Decrypted file1 content: $(cat "${DEC_DIR}/src/file1.txt")"
  echo "Decrypted file2 content: $(cat "${DEC_DIR}/src/file2.txt")"
  echo "Decrypted audit meta.txt content:"
  cat "${DEC_DIR}/vwbk-meta.txt"
else
  echo "FAILURE: Decryption check failed." >&2
  exit 1
fi

echo "----------------------------------------"
echo "All container tests passed successfully!"
