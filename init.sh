#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/restic-backup"
CONFIG_FILE="$CONFIG_DIR/config"
STATE_DIR="/var/lib/restic-backup"

SERVICE_FILE="/etc/systemd/system/restic-backup.service"
TIMER_FILE="/etc/systemd/system/restic-backup.timer"

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found at $CONFIG_FILE" >&2
  echo "Run install.sh first to create it." >&2
  exit 1
fi

if ! command -v restic >/dev/null 2>&1; then
  echo "restic is not installed. Run install.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

missing=()
[[ -z "${RESTIC_REPOSITORY:-}" ]] && missing+=("RESTIC_REPOSITORY")
[[ -z "${RESTIC_PASSWORD:-}" ]] && missing+=("RESTIC_PASSWORD")
[[ -z "${B2_ACCOUNT_ID:-}" ]] && missing+=("B2_ACCOUNT_ID")
[[ -z "${B2_ACCOUNT_KEY:-}" ]] && missing+=("B2_ACCOUNT_KEY")

if (( ${#missing[@]} > 0 )); then
  echo "Missing required config values: ${missing[*]}" >&2
  echo "Edit $CONFIG_FILE and re-run this script." >&2
  exit 1
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD B2_ACCOUNT_ID B2_ACCOUNT_KEY

echo "Testing connection to restic repository:"
set +e
restic snapshots >/dev/null 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "No usable repository found or access failed. Attempting 'restic init'..."
  set +e
  init_output="$(restic init 2>&1)"
  init_rc=$?
  set -e

  if [[ $init_rc -eq 0 ]]; then
    echo "Repository initialized successfully."
  else
    # If repo already exists, restic init typically prints 'config file already exists'
    if echo "$init_output" | grep -qi "config file already exists"; then
      echo "Repository already initialized (restic reported 'config file already exists')."
    else
      echo "restic init failed:"
      echo "$init_output"
      echo "Fix credentials / bucket / permissions and re-run this script."
      exit 1
    fi
  fi
else
  echo "Repository is already accessible (restic snapshots succeeded)."
fi

echo
echo "Reloading systemd units..."
systemctl daemon-reload

echo "Enabling and starting restic-backup.timer..."
systemctl enable --now restic-backup.timer

echo
echo "Init complete."

echo
echo "You can now run a backup manually with:"
echo "  sudo systemctl start restic-backup.service"
echo "And view logs with:"
echo "  journalctl -u restic-backup.service"
