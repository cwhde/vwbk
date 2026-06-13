# vwbk (Backup & Encryption Utility)

`vwbk` is a bash-script-based backup and encryption utility designed for extreme durability and long-term recovery. It uses the `age` tool with native support for hybrid post-quantum cryptography (`ML-KEM-768` + `X25519`).

To guarantee future readability, backups are structured as directories containing a plaintext, unencrypted `meta.txt` (detailing the `vwbk` version used, key name, key type, and timestamp) alongside the encrypted backup archive.

---

## Key Features
- **Post-Quantum Security**: Native hybrid `ML-KEM-768` (Kyber) + `X25519` encryption via `age >= v1.3.0`.
- **Flexible Enrollment**: Protect your secret key using a password, a YubiKey hardware token, or any FIDO2 security key — each as an explicit, distinct mode.
- **Smart Decryption**: `vwbk decrypt` reads the `key_type` field from `meta.txt` to automatically select the correct decryption flow, or prompts interactively if the metadata is absent.
- **Readable Metadata**: Inspect key name, key type, script version, and backup details without decrypting the data payload.
- **Strict Version Pinning**: All system packages (Debian, Alpine, Fedora 43), Docker images, and downloaded binaries are version-pinned to prevent future breaking changes.
- **Hardware Token Support**: Installs `age-plugin-yubikey` and `age-plugin-fido2-hmac` automatically, along with the required `pcscd`/`ccid`/`libfido2` system libraries.
- **Docker Daemon & Cloud Syncing**: Run periodic backups automatically, rotate old backups, and sync encrypted directories to cloud storage using `rclone`.

---

## Installation & Updates

The installer automatically detects Debian-based, Alpine-based, and Fedora 43-based systems, installs version-pinned dependencies, downloads the official pre-built `age` v1.3.1 binaries, installs the `age-plugin-yubikey` and `age-plugin-fido2-hmac` plugins, and copies the `vwbk` script to the local PATH.

To install the latest release, run:
```bash
curl -sSfL https://git.juzo.io/juzo/vwbk/releases/download/v1.6/install.sh | bash
```

To install from the main branch directly:
```bash
curl -sSfL https://git.juzo.io/juzo/vwbk/raw/branch/main/install.sh | bash
```

### Updating
To update `vwbk` to the latest release version, simply run:
```bash
vwbk update
```
You can also update to a specific version (e.g. `v1.7.9`) by specifying it:
```bash
vwbk update v1.7.9
```
Alternatively, you can re-run the installation command with the desired version tag.

---

## Usage

All commands prompt interactively for any missing arguments if not supplied.

### 1. Key Enrollment (`vwbk enroll`)
Creates a post-quantum age identity packaged in a single, unified key archive (`.vwbkey`). This contains your public key, encrypted private key, and optional passkey.

```bash
vwbk enroll [filepath] [mode]
```
- **`filepath`**: Optional. Base path/filename for the output key archive (e.g. `./keys/mykey`).
  - If it ends with `/` or is omitted, the archive is saved inside that folder as `identity.vwbkey`.
  - Produces a single `.vwbkey` archive file (which is a tar archive of the public, private, and passkey elements).
- **`mode`**: Optional. One of:
  - **`password`**: Prompts for a passphrase and encrypts the private key using `age -p`.
  - **`yubikey`**: Runs `age-plugin-yubikey` interactively. Insert your YubiKey before running.
  - **`fido2`**: Runs `age-plugin-fido2-hmac -g` interactively. Insert your FIDO2 security key and touch it when prompted.

### 2. Encryption (`vwbk encrypt`)
Tars, compresses, and encrypts a folder or file.

```bash
vwbk encrypt [key_path] [input_path] [output_folder]
```
- **`key_path`**: Path to the public key file (`.pub`) or unified key archive (`.vwbkey`).
- **`input_path`**: Path to the folder or file to back up.
- **`output_folder`**: Directory where the backup file will be created.

**Resulting structure:**
A single `.vwbk` tar archive file is created: `${timestamp}-${key_name}.vwbk`.
Inside the archive, the payload and metadata are packed together:
* `meta.txt`: Plaintext metadata (version, key name, key type, timestamp, embedded key info).
* `data.tar.gz.age`: Encrypted backup payload.
* `identity.key` (Optional): Bundled private key file (encrypted, completely secure to distribute/store).
* `identity.passkey` (Optional): Bundled passkey file.

### 3. Decryption (`vwbk decrypt`)
Decrypts, decompresses, and extracts the backup. Supports both the new `.vwbk` file-based archives and legacy `.vwbk` directory-based formats.

```bash
vwbk decrypt [input_path] [output_folder] [key_path]
```
- **`input_path`**: Path to the `.vwbk` backup file or folder.
- **`output_folder`**: Directory to extract the backup contents into.
- **`key_path`**: Optional. Path to the private key file (`.key`) or unified key archive (`.vwbkey`).
  - If a companion key (`identity.key`) was bundled inside the backup during encryption, you can **omit `key_path` entirely**. `vwbk` will automatically use the bundled key and prompt you for the passphrase or security key touch!
  - If a custom `key_path` is provided, it will override the bundled key.
  - If no key is found or provided, it will prompt you interactively to choose a key.

### 4. Inspection (`vwbk inspect`)
Displays metadata from a backup file or directory without decrypting the data.

```bash
vwbk inspect [backup_path]
```

### 5. Self-Updating (`vwbk update`)
Updates the utility directly from the GitHub repository `cwhde/vwbk`.

```bash
# Update to latest version
vwbk update

# Update to a specific release tag
vwbk update v1.7.9
```

---

## Docker Daemon

A prebuilt Docker image is available to automate periodic backups. It handles encryption for multiple keys, manages backup rotation (`KEEP_LAST`), and syncs outputs to cloud storage via `rclone`.

### Directory Mapping
- `/encrypt`: Mount the directory you want to back up here.
- `/keys`: Mount the directory containing your public keys (`*.pub`). A backup is generated for every key found.
- `/encrypted`: Mount your target backup directory here.
- `/rclone.conf` *(Optional)*: Mount your `rclone.conf` here. If present, backups are synced to the remote named `main`.

### Docker Compose Example
```yaml
version: '3.8'

services:
  vwbk-daemon:
    image: git.juzo.io/juzo/vwbk:latest
    container_name: vwbk-daemon
    restart: unless-stopped
    volumes:
      - /path/to/data:/encrypt:ro
      - /path/to/public_keys:/keys:ro
      - /path/to/backups:/encrypted
      # Optional rclone config
      - /path/to/rclone.conf:/rclone.conf:ro
    environment:
      - KEEP_LAST=10
      - BACKUP_INTERVAL=1440 # minutes (1440 = 24 hours)
```

---

## Recovery and Compatibility

### Decrypting Years from Now
To ensure you can read backups far in the future:
1. Open the plaintext `meta.txt` inside the backup folder and note `vwbk_version` and `key_type`.
2. Install the matching `vwbk` version:
   ```bash
   curl -sSfL https://git.juzo.io/juzo/vwbk/releases/download/<version>/install.sh | bash
   ```
   This downloads the exact `vwbk` script and pins all system components to that version's validated configuration.
3. Decrypt using the appropriate method:
   ```bash
   # Password key:
   vwbk decrypt /path/to/backup.vwbk /path/to/restore /path/to/private.key

   # Hardware passkey (yubikey or fido2) — omit key_path to be prompted:
   vwbk decrypt /path/to/backup.vwbk /path/to/restore
   ```

---

## License

This project is licensed under the **BSD 3-Clause License** - see the [LICENSE](LICENSE) file for details.
