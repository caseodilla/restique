#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/restic-backup"
CONFIG_FILE="$CONFIG_DIR/config"
STATE_DIR="/var/lib/restic-backup"
PRE_HOOKS_DIR="$CONFIG_DIR/pre-backup.d"

STATUS_FILE="$STATE_DIR/status"
MOTD_WARNING_FILE="$STATE_DIR/motd-warning"

DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)
      DRY_RUN=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run|-n]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Defaults if not set
EXCLUDES_FILE="${EXCLUDES_FILE:-}"
INCLUDE_PATHS="${INCLUDE_PATHS:-/home /root /etc /opt /var/www}"
PRUNE_ARGS="${PRUNE_ARGS:-"--keep-last 5 --keep-weekly 4 --keep-monthly 3"}"
HEARTBEAT_URL="${HEARTBEAT_URL:-}"

# Validate required config
missing=()
[[ -z "${RESTIC_REPOSITORY:-}" ]] && missing+=("RESTIC_REPOSITORY")
[[ -z "${RESTIC_PASSWORD:-}" ]] && missing+=("RESTIC_PASSWORD")
[[ -z "${B2_ACCOUNT_ID:-}" ]] && missing+=("B2_ACCOUNT_ID")
[[ -z "${B2_ACCOUNT_KEY:-}" ]] && missing+=("B2_ACCOUNT_KEY")
[[ -z "${NTFY_URL:-}" ]] && missing+=("NTFY_URL")
[[ -z "${NTFY_AUTH_KEY:-}" ]] && missing+=("NTFY_AUTH_KEY")

if (( ${#missing[@]} > 0 )); then
  echo "Missing required config values: ${missing[*]}" >&2
  exit 1
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD B2_ACCOUNT_ID B2_ACCOUNT_KEY

mkdir -p "$STATE_DIR"

now_ms() {
  date +%s%3N
}

send_ntfy() {
  local status="$1"
  local priority="$2"
  local ta_header="$3"
  local msg="$4"

  if $DRY_RUN; then
    echo "[DRY RUN] Would send ntfy: status=$status p=$priority ta=$ta_header msg=$msg"
    return 0
  fi

  curl -fsS -X POST \
    -H "Authorization: Bearer $NTFY_AUTH_KEY" \
    -H "p: $priority" \
    -H "ta: $ta_header" \
    -d "$msg" \
    "$NTFY_URL" || true
}

update_motd() {
  local status="$1"
  local short_msg="$2"

  if $DRY_RUN; then
    echo "[DRY RUN] Would update MOTD ($status): $short_msg"
    return 0
  fi

  if [[ "$status" == "success" ]]; then
    rm -f "$MOTD_WARNING_FILE"
  else
    cat >"$MOTD_WARNING_FILE" <<EOF
$short_msg
See: journalctl -u restic-backup.service
EOF
  fi
}

write_status() {
  local status="$1"
  local last_run_epoch="$2"
  local last_success_epoch="$3"
  local message="$4"

  if $DRY_RUN; then
    echo "[DRY RUN] Would write status: status=$status last_run=$last_run_epoch last_success=$last_success_epoch msg=$message"
    return 0
  fi

  cat >"$STATUS_FILE" <<EOF
STATUS=$status
LAST_RUN_EPOCH=$last_run_epoch
LAST_SUCCESS_EPOCH=$last_success_epoch
MESSAGE=$message
EOF
}

heartbeat_ping() {
  local status="$1"

  if $DRY_RUN; then
    echo "[DRY RUN] Would ping heartbeat ($status) to $HEARTBEAT_URL"
    return 0
  fi

  [[ -z "$HEARTBEAT_URL" ]] && return 0

  if [[ "$status" == "success" || "$status" == "warning" ]]; then
    curl -fsS "$HEARTBEAT_URL" >/dev/null 2>&1 || true
  fi
}

run_pre_hooks() {
  if $DRY_RUN; then
    echo "[DRY RUN] Skipping pre-backup hooks (no side effects)."
    return 0
  fi

  if [[ ! -d "$PRE_HOOKS_DIR" ]]; then
    return 0
  fi

  local hook
  for hook in "$PRE_HOOKS_DIR"/*.sh; do
    [[ ! -e "$hook" ]] && continue
    [[ ! -x "$hook" ]] && continue
    echo "Running pre-backup hook: $hook"
    if ! "$hook"; then
      echo "Pre-backup hook failed: $hook" >&2
      return 1
    fi
  done
}

human_duration() {
  awk -v ms="$1" '
    BEGIN {
      if (ms < 1000) {
        printf "%dms\n", ms
        exit
      }

      s = ms / 1000.0
      if (s < 60) {
        printf "%.1fs\n", s
        exit
      }

      m = s / 60.0
      if (m < 60) {
        printf "%.1fm\n", m
        exit
      }

      h = m / 60.0
      printf "%.1fh\n", h
    }
  '
}

start_ts_ms="$(now_ms)"
start_ts_epoch="$(date +%s)"

echo "Starting restic backup at $(date -Iseconds)"

if ! run_pre_hooks; then
  status="failure"
  msg="FAILURE: Pre-backup hook failed on $HOSTNAME."
  send_ntfy "$status" "5" "x" "$msg"
  update_motd "$status" "$msg"
  write_status "$status" "$start_ts_epoch" "" "$msg"
  heartbeat_ping "$status"
  exit 2
fi

BACKUP_LOG="$(mktemp /tmp/restic-backup-log.XXXXXX)"

backup_cmd=(restic backup --verbose)
if [[ -n "$EXCLUDES_FILE" ]]; then
  backup_cmd+=(--exclude-file "$EXCLUDES_FILE")
fi

for p in $INCLUDE_PATHS; do
  backup_cmd+=("$p")
done

if $DRY_RUN; then
  backup_cmd+=(--dry-run)
fi

echo "Running backup command: ${backup_cmd[*]}"
set +e
"${backup_cmd[@]}" | tee "$BACKUP_LOG"
backup_rc=$?
set -e

if [[ $backup_rc -eq 0 ]]; then
  status="success"
elif [[ $backup_rc -eq 1 ]]; then
  status="warning"
else
  status="failure"
fi

if [[ "$status" == "success" || "$status" == "warning" ]] && ! $DRY_RUN; then
  prune_cmd=(restic forget --prune)
  # shellcheck disable=SC2206
  prune_cmd+=($PRUNE_ARGS)

  echo "Running prune command: ${prune_cmd[*]}"
  set +e
  "${prune_cmd[@]}" | tee -a "$BACKUP_LOG"
  prune_rc=$?
  set -e

  if [[ $prune_rc -ne 0 ]]; then
    echo "Prune failed with exit code $prune_rc" >&2
    status="failure"
  fi
fi

end_ts_ms="$(now_ms)"
end_ts_epoch="$(date +%s)"

elapsed_ms=$((end_ts_ms - start_ts_ms))
elapsed_human="$(human_duration "$elapsed_ms")"

summary_tail="$(tail -n 10 "$BACKUP_LOG" || true)"
rm -f "$BACKUP_LOG"

case "$status" in
  success)
    priority="1"
    ta="white_check_mark"
    msg="OK: restic backup on $HOSTNAME finished in ${elapsed_human} to $RESTIC_REPOSITORY"
    short_motd=""
    last_success_epoch="$end_ts_epoch"
    ;;
  warning)
    priority="3"
    ta="warning"
    msg="Warning: restic backup on $HOSTNAME completed with warnings in ${elapsed_human}. Last lines:\n${summary_tail}"
    short_motd="⚠ Restic backup on this server completed with warnings. See logs."
    last_success_epoch="$end_ts_epoch"
    ;;
  failure)
    priority="5"
    ta="x"
    msg="FAILURE: restic backup on $HOSTNAME failed after ${elapsed_human}. Last lines:\n${summary_tail}"
    short_motd="❌ Restic backup on this server FAILED. See logs."
    last_success_epoch=""
    ;;
esac

send_ntfy "$status" "$priority" "$ta" "$msg"
[[ -n "$short_motd" ]] && update_motd "$status" "$short_motd" || update_motd "$status" ""
write_status "$status" "$end_ts_epoch" "$last_success_epoch" "$msg"
heartbeat_ping "$status"

case "$status" in
  success) exit 0 ;;
  warning) exit 1 ;;
  failure) exit 2 ;;
esac
