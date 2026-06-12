# vwbk (Vwbk - Backup & Encryption Utility)

`vwbk` is a bash-script-based backup and encryption utility designed for extreme durability and long-term recovery. It uses the `age` tool with native support for hybrid post-quantum cryptography (`ML-KEM-768` + `X25519`). 

To guarantee future readability, backups are structured as directories containing a plaintext, unencrypted `meta.txt` (detailing the `vwbk` version used, key name, and configuration) alongside the encrypted backup archive.

---

## Key Features
- **Post-Quantum Security**: Native hybrid `ML-KEM-768` (Kyber) + `X25519` encryption via `age >= v1.3.0`.
- **Flexible Enrollment**: Protect your secret key using standard password encryption or physical FIDO2/YubiKey hardware tokens.
- **Readable Metadata**: Inspect key name, script version, and backup details without decrypting the data payload.
- **Strict Version Pinning**: All system packages, Docker images, and downloaded binaries are version-pinned to prevent future breaking changes.
- **Docker Daemon & Cloud Syncing**: Run periodic backups automatically, rotate old backups, and sync encrypted directories to cloud storage using `rclone`.

---

## Installation & Updates

The installer automatically detects Debian-based and Alpine-based systems, installs version-pinned dependencies, downloads the official pre-built `age` v1.3.1 binaries if system repos are outdated, and copies the `vwbk` script to the local PATH.

To install the latest release, run:
```bash
curl -sSfL https://github.com/cwhde/vwbk/releases/download/v1.0.0/install.sh | bash
```

To install from the master branch directly:
```bash
curl -sSfL https://raw.githubusercontent.com/cwhde/vwbk/main/install.sh | bash
```

### Updating
To update `vwbk` to a newer version, simply re-run the installation command matching the version you wish to install. The installer will overwrite the existing `vwbk` and `age`/`age-keygen` binaries in your local path with the specified version, leaving your generated keys and backup configurations untouched.

---

## Usage

All commands will prompt interactively for any missing arguments if not supplied.

### 1. Key Enrollment (`vwbk enroll`)
Creates an age identity with a public key and a protected private key.

```bash
vwbk enroll [filepath] [mode]
```
- **`filepath`**: Optional. Path to save the keys (e.g. `./keys/today`).
  - If it ends with a slash `/` or is omitted, keys are generated inside the folder with the name `identity`.
  - Generates `.key` (private key), `.pub` (public key), and `.passkey` (if hardware token is used).
- **`mode`**: Optional. `password` or `passkey`.
  - **`password`**: Prompts you for a passphrase to encrypt the post-quantum private key using `age -p`.
  - **`passkey`**: Automatically detects and uses `age-plugin-yubikey` or `age-plugin-fido2-hmac`. It generates a hardware configuration (`.passkey` file) and encrypts the post-quantum private key with it.

### 2. Encryption (`vwbk encrypt`)
Tars, compresses, and encrypts a folder or file.

```bash
vwbk encrypt [key_path] [input_path] [output_folder]
```
- **`key_path`**: Path to the public key file (`.pub`).
- **`input_path`**: Path to the folder or file to backup.
- **`output_folder`**: Directory where the backup directory will be created.

**Resulting Structure:**
The backup creates a self-contained folder under the output folder named `YYYYMMDD_HHMMSS-<keyname>.vwbk/`:
```
20260612_180000-todaykeys.vwbk/
├── meta.txt           <-- Plaintext metadata (version, key name, timestamp)
└── data.tar.gz.age    <-- Encrypted backup payload
```

### 3. Decryption (`vwbk decrypt`)
Decrypts, decompresses, and extracts the backup.

```bash
vwbk decrypt [key_path] [input_path] [output_folder]
```
- **`key_path`**: Path to the private key file (`.key`). If a `.passkey` companion file exists, it is used automatically.
- **`input_path`**: Path to the `.vwbk` backup folder.
- **`output_folder`**: Directory to extract the backup contents.

This will export `vwbk-meta.txt` into the output folder for audit purposes.

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
- `/keys`: Mount the directory containing your public keys (`*.pub`). A backup will be generated for every key.
- `/encrypted`: Mount your target backup directory here.
- `/rclone.conf` *(Optional)*: Mount your `rclone.conf` config file here. If present, backups are synced to the remote named `main`.

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
      # Optional rclone config mapping
      - /path/to/rclone.conf:/rclone.conf:ro
    environment:
      - KEEP_LAST=10
      - BACKUP_INTERVAL=1440 # 24 hours (in minutes)
```

---

## Recovery and Compatibility Instructions

### decrypting 10 Years from Now
To ensure that you can read your backups decades in the future, follow these instructions:
1. Locate the `vwbk_version` in the plaintext `meta.txt` file of the backup directory (e.g. `v1.0.0`).
2. Run the `install.sh` matching that specific version tag:
   ```bash
   curl -sSfL https://github.com/cwhde/vwbk/releases/download/v1.0.0/install.sh | bash
   ```
   This will download the exact corresponding version of the `vwbk` script and pin all system components to the validated `v1.0.0` configuration.
3. Perform standard decryption:
   ```bash
   vwbk decrypt /path/to/private.key /path/to/backup.vwbk /path/to/restore
   ```

---

## License

This project is licensed under the **BSD 3-Clause License** - see the [LICENSE](LICENSE) file for details.
