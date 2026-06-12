#!/usr/bin/env bash

# install.sh - Installer for vwbk utility
# Version: DEV (replaces with release tag in CI/CD)
VWBK_VERSION="DEV"

# Target versions
PINNED_AGE_VERSION="v1.3.1"
PINNED_YUBIKEY_PLUGIN_VERSION="v0.5.0"
PINNED_FIDO2_PLUGIN_VERSION="v0.5.0"

# Debian targets
DEB_BASH="5.2.37-2+b9"
DEB_TAR="1.35+dfsg-3.1"
DEB_GZIP="1.13-1"
DEB_PCSCD="2.3.3-1"
DEB_CCID="1.6.2-1"
DEB_FIDO2="1.15.0-1+b1"

# Alpine targets
APK_BASH="5.2.26-r0"
APK_TAR="1.35-r2"
APK_GZIP="1.13-r0"
APK_PCSCD="2.2.3-r0"
APK_CCID="1.5.5-r0"
APK_FIDO2="1.14.0-r1"

# Fedora targets
FEDORA_BASH="5.3.0-2.fc43"
FEDORA_TAR="1.35-6.fc43"
FEDORA_GZIP="1.13-4.fc43"
FEDORA_CURL="8.15.0-7.fc43"
FEDORA_PCSCD="2.3.3-2.fc43"
FEDORA_CCID="1.7.0-2.fc43"
FEDORA_FIDO2="1.16.0-3.fc43"

echo "=== vwbk ${VWBK_VERSION} Installer ==="

# 1. OS Detection
if [ -f /etc/os-release ]; then
  # Read os-release but store VERSION in a temporary variable or don't import it to avoid collision
  # We only need ID from os-release
  OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
else
  OS_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
fi

run_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif which sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: This command requires root privileges but sudo is not installed and you are not root." >&2
    exit 1
  fi
}

install_debian_deps() {
  echo "Detected Debian/Ubuntu system."
  echo "Updating apt repositories..."
  run_cmd apt-get update -y

  echo "Installing system dependencies (pinned where possible)..."
  # Attempt pinned install, fallback if package version was updated in mirror
  if ! run_cmd apt-get install -y bash="${DEB_BASH}" tar="${DEB_TAR}" gzip="${DEB_GZIP}" pcscd="${DEB_PCSCD}" libccid="${DEB_CCID}" libfido2-1="${DEB_FIDO2}" curl; then
    echo "Warning: Pinned Debian package versions failed. Installing latest available..."
    run_cmd apt-get install -y bash tar gzip pcscd libccid libfido2-1 curl
  fi

  # Enable and start pcscd daemon (ignore if fails, e.g. in container)
  if which systemctl >/dev/null 2>&1; then
    run_cmd systemctl enable --now pcscd || true
  elif [ -f /etc/init.d/pcscd ]; then
    run_cmd service pcscd start || true
  fi
}

install_alpine_deps() {
  echo "Detected Alpine Linux system."
  echo "Updating apk repositories..."
  run_cmd apk update

  echo "Installing system dependencies (pinned where possible)..."
  # Attempt pinned install, fallback if package version was updated in mirror
  if ! run_cmd apk add --no-cache bash="${APK_BASH}" tar="${APK_TAR}" gzip="${APK_GZIP}" pcsc-lite="${APK_PCSCD}" ccid="${APK_CCID}" libfido2="${APK_FIDO2}" curl; then
    echo "Warning: Pinned Alpine package versions failed. Installing latest available..."
    run_cmd apk add --no-cache bash tar gzip pcsc-lite ccid libfido2 curl
  fi

  if which rc-service >/dev/null 2>&1; then
    run_cmd rc-update add pcscd default || true
    run_cmd rc-service pcscd start || true
  fi
}

install_fedora_deps() {
  echo "Detected Fedora system."
  echo "Installing system dependencies (pinned where possible)..."
  # Attempt pinned install, fallback if package version was updated in repo
  if ! run_cmd dnf install -y bash-"${FEDORA_BASH}" tar-"${FEDORA_TAR}" gzip-"${FEDORA_GZIP}" pcsc-lite-"${FEDORA_PCSCD}" pcsc-lite-ccid-"${FEDORA_CCID}" libfido2-"${FEDORA_FIDO2}" curl-"${FEDORA_CURL}"; then
    echo "Warning: Pinned Fedora package versions failed. Installing latest available..."
    run_cmd dnf install -y bash tar gzip pcsc-lite pcsc-lite-ccid libfido2 curl
  fi

  if which systemctl >/dev/null 2>&1; then
    run_cmd systemctl enable --now pcscd || true
  fi
}

case "$OS_ID" in
  debian|ubuntu|raspbian)
    install_debian_deps
    ;;
  alpine)
    install_alpine_deps
    ;;
  fedora)
    install_fedora_deps
    ;;
  *)
    echo "Warning: Unsupported OS '$OS_ID'. Please ensure bash, tar, gzip, and curl are installed manually."
    ;;
esac

# 2. Setup user local bin directory
USER_BIN_DIR="$HOME/.local/bin"
mkdir -p "$USER_BIN_DIR"

# 3. age and age-keygen Setup
install_yubikey_plugin() {
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    echo "Downloading age-plugin-yubikey ${PINNED_YUBIKEY_PLUGIN_VERSION}..."
    TEMP_DIR=$(mktemp -d)
    TARBALL="age-plugin-yubikey-${PINNED_YUBIKEY_PLUGIN_VERSION}-x86_64-linux.tar.gz"
    DOWNLOAD_URL="https://github.com/str4d/age-plugin-yubikey/releases/download/${PINNED_YUBIKEY_PLUGIN_VERSION}/${TARBALL}"

    if curl -sSfL "$DOWNLOAD_URL" -o "${TEMP_DIR}/${TARBALL}"; then
      tar -xzf "${TEMP_DIR}/${TARBALL}" -C "$TEMP_DIR"
      mv "${TEMP_DIR}/age-plugin-yubikey/age-plugin-yubikey" "$USER_BIN_DIR/age-plugin-yubikey"
      chmod +x "$USER_BIN_DIR/age-plugin-yubikey"
      echo "Installed age-plugin-yubikey into $USER_BIN_DIR"
    else
      echo "Warning: Failed to download age-plugin-yubikey prebuilt binary." >&2
    fi
    rm -rf "$TEMP_DIR"
  else
    echo "Warning: No prebuilt age-plugin-yubikey binary available for ${ARCH}." >&2
  fi
}

install_fido2_plugin() {
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    echo "Downloading age-plugin-fido2-hmac ${PINNED_FIDO2_PLUGIN_VERSION}..."
    TEMP_DIR=$(mktemp -d)
    TARBALL="age-plugin-fido2-hmac-${PINNED_FIDO2_PLUGIN_VERSION}-linux-amd64.tar.gz"
    DOWNLOAD_URL="https://github.com/olastor/age-plugin-fido2-hmac/releases/download/${PINNED_FIDO2_PLUGIN_VERSION}/${TARBALL}"

    if curl -sSfL "$DOWNLOAD_URL" -o "${TEMP_DIR}/${TARBALL}"; then
      tar -xzf "${TEMP_DIR}/${TARBALL}" -C "$TEMP_DIR"
      mv "${TEMP_DIR}/age-plugin-fido2-hmac/age-plugin-fido2-hmac" "$USER_BIN_DIR/age-plugin-fido2-hmac"
      chmod +x "$USER_BIN_DIR/age-plugin-fido2-hmac"
      echo "Installed age-plugin-fido2-hmac into $USER_BIN_DIR"
    else
      echo "Warning: Failed to download age-plugin-fido2-hmac prebuilt binary." >&2
    fi
    rm -rf "$TEMP_DIR"
  else
    echo "Warning: No prebuilt age-plugin-fido2-hmac binary available for ${ARCH}." >&2
  fi
}

install_age_binary() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)
      AGE_ARCH="linux-amd64"
      ;;
    aarch64|arm64)
      AGE_ARCH="linux-arm64"
      ;;
    armv7l)
      AGE_ARCH="linux-arm"
      ;;
    *)
      echo "Error: Unsupported architecture '$ARCH' for age binary download." >&2
      exit 1
      ;;
  esac

  echo "Downloading age ${PINNED_AGE_VERSION} for ${AGE_ARCH}..."
  TEMP_DIR=$(mktemp -d)
  TARBALL="age-${PINNED_AGE_VERSION}-${AGE_ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/FiloSottile/age/releases/download/${PINNED_AGE_VERSION}/${TARBALL}"

  if curl -sSfL "$DOWNLOAD_URL" -o "${TEMP_DIR}/${TARBALL}"; then
    tar -xzf "${TEMP_DIR}/${TARBALL}" -C "$TEMP_DIR"
    mv "${TEMP_DIR}/age/age" "$USER_BIN_DIR/age"
    mv "${TEMP_DIR}/age/age-keygen" "$USER_BIN_DIR/age-keygen"
    chmod +x "$USER_BIN_DIR/age" "$USER_BIN_DIR/age-keygen"
    echo "Installed age and age-keygen into $USER_BIN_DIR"
  else
    echo "Error: Failed to download age binary from $DOWNLOAD_URL" >&2
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  rm -rf "$TEMP_DIR"
}

# Check existing age
NEED_AGE_INSTALL=true
if which age >/dev/null 2>&1 && which age-keygen >/dev/null 2>&1; then
  CURRENT_AGE_VER=$(age --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  # Parse major and minor
  IFS='.' read -r major minor patch <<< "$CURRENT_AGE_VER"
  if [[ -n "$major" && -n "$minor" ]]; then
    if (( major > 1 || (major == 1 && minor >= 3) )); then
      echo "Found compatible age version ${CURRENT_AGE_VER}."
      NEED_AGE_INSTALL=false
    fi
  fi
fi

if [ "$NEED_AGE_INSTALL" = true ]; then
  install_age_binary
fi

# 3b. Install age plugins (YubiKey & FIDO2)
install_yubikey_plugin
install_fido2_plugin

# 4. Download and Install vwbk script
# Determine vwbk download URL
if [ "$VWBK_VERSION" = "DEV" ]; then
  if [ -f "./vwbk" ]; then
    echo "Local vwbk script found. Copying locally for dev install..."
    cp "./vwbk" "$USER_BIN_DIR/vwbk"
    chmod +x "$USER_BIN_DIR/vwbk"
    echo "vwbk installed successfully to $USER_BIN_DIR/vwbk"
  else
    VWBK_URL="https://raw.githubusercontent.com/cwhde/vwbk/main/vwbk"
    echo "Downloading vwbk ${VWBK_VERSION} from ${VWBK_URL}..."
    if curl -sSfL "$VWBK_URL" -o "$USER_BIN_DIR/vwbk"; then
      chmod +x "$USER_BIN_DIR/vwbk"
      echo "vwbk installed successfully to $USER_BIN_DIR/vwbk"
    else
      echo "Error: Failed to download vwbk script from $VWBK_URL" >&2
      exit 1
    fi
  fi
else
  # Release mode: download from the specific release tag
  VWBK_URL="https://github.com/cwhde/vwbk/releases/download/${VWBK_VERSION}/vwbk"
  echo "Downloading vwbk ${VWBK_VERSION} from ${VWBK_URL}..."
  if curl -sSfL "$VWBK_URL" -o "$USER_BIN_DIR/vwbk"; then
    chmod +x "$USER_BIN_DIR/vwbk"
    echo "vwbk installed successfully to $USER_BIN_DIR/vwbk"
  else
    echo "Error: Failed to download vwbk script from $VWBK_URL" >&2
    exit 1
  fi
fi

# 5. Update user PATH if necessary
PATH_UPDATED=false
if [[ ":$PATH:" != *":$USER_BIN_DIR:"* ]]; then
  echo "Adding $USER_BIN_DIR to user PATH..."

  # Determine shell profile
  SHELL_NAME=$(basename "$SHELL")
  PROFILE_FILE=""
  if [ "$SHELL_NAME" = "bash" ]; then
    PROFILE_FILE="$HOME/.bashrc"
  elif [ "$SHELL_NAME" = "zsh" ]; then
    PROFILE_FILE="$HOME/.zshrc"
  else
    PROFILE_FILE="$HOME/.profile"
  fi

  if [ -f "$PROFILE_FILE" ]; then
    # Ensure it's not already added or we append it
    if ! grep -q "$USER_BIN_DIR" "$PROFILE_FILE"; then
      echo -e "\n# Added by vwbk installer\nexport PATH=\"\$PATH:$USER_BIN_DIR\"" >> "$PROFILE_FILE"
      PATH_UPDATED=true
    fi
  fi
fi

echo "----------------------------------------"
echo "Installation complete!"
if [ "$PATH_UPDATED" = true ]; then
  echo "Please restart your terminal or run:"
  echo "  source $PROFILE_FILE"
  echo "to update your PATH."
else
  echo "You can now run 'vwbk' directly."
fi
