#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/restic-backup/config"

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
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
  exit 1
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD B2_ACCOUNT_ID B2_ACCOUNT_KEY

echo
echo "Opened a restic-ready root shell."
echo "Examples:"
echo "  restic snapshots"
echo "  restic check"
echo "  restic restore <id> --target /restore --include /etc"
echo
echo "Type 'exit' to leave."
echo

# Drop into a subshell with these env vars
bash --noprofile --norc
