#!/usr/bin/env bash

# Start pcscd daemon for smartcard/passkey support
if which pcscd >/dev/null 2>&1; then
  pcscd --hotplug &
  sleep 0.5
fi

# docker-entrypoint.sh - Daemon loop for containerized vwbk backups
# If a custom command is provided as arguments, execute it instead of running the daemon loop
if [ $# -gt 0 ]; then
  exec "$@"
fi

# Defaults
KEEP_LAST=${KEEP_LAST:-10}
BACKUP_INTERVAL=${BACKUP_INTERVAL:-1440} # Default 24 hours (in minutes)

echo "=== Starting vwbk Backup Daemon ==="
echo "Configuration:"
echo "  KEEP_LAST: ${KEEP_LAST}"
echo "  BACKUP_INTERVAL: ${BACKUP_INTERVAL} minutes"

while true; do
  echo "--- Starting backup run: $(date) ---"

  # 1. Validation checks
  if [[ ! -d /keys ]] || [[ -z "$(ls -A /keys 2>/dev/null)" ]]; then
    echo "Warning: /keys directory is empty. No public keys found. Skipping backup run..."
  elif [[ ! -d /encrypt ]] || [[ -z "$(ls -A /encrypt 2>/dev/null)" ]]; then
    echo "Warning: /encrypt directory is empty. Nothing to backup. Skipping backup run..."
  else
    # 2. Perform backups for each public key found in /keys
    for key_file in /keys/*.pub; do
      if [[ -f "$key_file" ]]; then
        echo "Performing backup with key: $(basename "$key_file")"
        vwbk encrypt "$key_file" /encrypt /encrypted
      fi
    done

    # 3. Rotate old backups per key
    echo "Running backup rotation (keeping last ${KEEP_LAST} backups per key)..."
    declare -A backups_by_key

    # Scan for .vwbk directories in /encrypted
    for d in /encrypted/*.vwbk; do
      if [[ -d "$d" ]]; then
        key_name=""
        if [[ -f "$d/meta.txt" ]]; then
          key_name=$(grep "^key_name:" "$d/meta.txt" | cut -d' ' -f2)
        fi
        # Fallback to directory name pattern if meta.txt key_name isn't found
        if [[ -z "$key_name" ]]; then
          base_dir=$(basename "$d")
          key_name="${base_dir#*-}"
          key_name="${key_name%.vwbk}"
        fi

        if [[ -n "$key_name" ]]; then
          backups_by_key["$key_name"]="${backups_by_key["$key_name"]}"$'\n'"$d"
        fi
      fi
    done

    # Perform rotation per key group
    for key in "${!backups_by_key[@]}"; do
      sorted_backups=$(echo "${backups_by_key["$key"]}" | grep -v '^$' | sort)
      count=$(echo "$sorted_backups" | wc -l)
      if (( count > KEEP_LAST )); then
        to_delete_count=$(( count - KEEP_LAST ))
        echo "Key '$key' has $count backups. Deleting oldest $to_delete_count..."
        echo "$sorted_backups" | head -n "$to_delete_count" | while read -r del_dir; do
          if [[ -d "$del_dir" ]]; then
            echo "Deleting old backup: $del_dir"
            rm -rf "$del_dir"
          fi
        done
      else
        echo "Key '$key' has $count backups (limit ${KEEP_LAST}). No rotation needed."
      fi
    done
  fi

  # 4. Sync to rclone if config is provided
  if [[ -f /rclone.conf ]]; then
    echo "Found rclone configuration at /rclone.conf. Syncing to remote 'main'..."
    rclone sync /encrypted main: --config /rclone.conf --delete-during
    if [[ $? -eq 0 ]]; then
      echo "rclone sync completed successfully."
    else
      echo "Error: rclone sync failed." >&2
    fi
  fi

  echo "--- Backup run finished: $(date) ---"
  echo "Sleeping for ${BACKUP_INTERVAL} minutes..."
  sleep $(( BACKUP_INTERVAL * 60 ))
done
