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
To update `vwbk` to a newer version, simply re-run the installation command with the desired version tag. The installer overwrites the existing `vwbk`, `age`, and plugin binaries in your local path, leaving your generated keys and backups untouched.

---

## Usage

All commands prompt interactively for any missing arguments if not supplied.

### 1. Key Enrollment (`vwbk enroll`)
Creates an age identity: a public key and a protected private key.

```bash
vwbk enroll [filepath] [mode]
```
- **`filepath`**: Optional. Base path for the output files (e.g. `./keys/mykey`).
  - If it ends with `/` or is omitted, keys are saved inside that folder as `identity`.
  - Produces `.key` (encrypted private key), `.pub` (public key), and `.passkey` (hardware token mode only).
- **`mode`**: Optional. One of:
  - **`password`**: Prompts for a passphrase and encrypts the private key using `age -p`.
  - **`yubikey`**: Runs `age-plugin-yubikey` interactively. Insert your YubiKey before running. Requires `age-plugin-yubikey` to be installed.
  - **`fido2`**: Runs `age-plugin-fido2-hmac --enroll` interactively. Insert your FIDO2 security key and touch it when prompted. Requires `age-plugin-fido2-hmac` to be installed.

### 2. Encryption (`vwbk encrypt`)
Tars, compresses, and encrypts a folder or file.

```bash
vwbk encrypt [key_path] [input_path] [output_folder]
```
- **`key_path`**: Path to the public key file (`.pub`).
- **`input_path`**: Path to the folder or file to back up.
- **`output_folder`**: Directory where the backup folder will be created.

**Resulting structure:**
```
20260612_180000-mykey.vwbk/
├── meta.txt           <-- Plaintext metadata (version, key name, key type, timestamp)
└── data.tar.gz.age    <-- Encrypted backup payload
```

The `key_type` field in `meta.txt` records whether the backup was encrypted with `password`, `yubikey`, or `fido2` — used by `vwbk decrypt` to auto-select the correct decryption flow.

### 3. Decryption (`vwbk decrypt`)
Decrypts, decompresses, and extracts the backup.

```bash
vwbk decrypt [input_path] [output_folder] [key_path]
```
- **`input_path`**: Path to the `.vwbk` backup folder.
- **`output_folder`**: Directory to extract the backup contents into.
- **`key_path`**: Optional. Path to the private key file (`.key`).
  - If provided, the **password** decryption flow is used directly.
  - If omitted, `vwbk` reads `key_type` from `meta.txt` and selects the correct flow automatically. If `key_type` is absent, it prompts interactively:
    ```
    1) Password-encrypted key file (.key)
    2) YubiKey hardware passkey
    3) FIDO2 hardware passkey
    ```

For hardware token flows (`yubikey` / `fido2`), the `.passkey` identity file paired with the `.key` file is used. All interactive prompts (PIN entry, key touch) are routed through `/dev/tty` so they work correctly even when stdin is piped.

This command also exports `vwbk-meta.txt` into the output folder for audit purposes.

### 4. Inspection (`vwbk inspect`)
Displays metadata from a backup directory without decrypting the data.

```bash
vwbk inspect [backup_folder]
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
