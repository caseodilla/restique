# Restic Backup Suite for Ubuntu Servers

Automated, self-contained backup system for Ubuntu servers using:

- Restic to Backblaze B2
- Systemd timer (Mon & Thu @ 04:00)
- Self-hosted ntfy notifications (success / warning / failure)
- Optional heartbeat URL
- MOTD warnings for backup issues
- Pre-backup hook scripts (e.g., MySQL dumps)
- Idempotent curl-install
- Safe config handling (never overwritten unless requested)

This repo provides the scripts that the installer fetches and deploys automatically.

---

## Installation

Run on any Ubuntu server:

curl -sSL https://raw.githubusercontent.com/caseodilla/restique/main/install.sh | sudo bash

The installer will:

- Install dependencies (restic, curl)
- Prompt for:
  - B2 key ID / application key
  - Restic repo password
  - Self-hosted ntfy URL + auth key
  - Optional heartbeat URL
- Create /etc/restic-backup/
- Install backup script + systemd service + timer
- Install MOTD warning hook
- Install example MySQL pre-backup hook
- Generate /etc/restic-backup/README.md with version info
- Enable and start the timer

---

## First-time initialization

After installation, before the first backup, run:

  sudo /etc/restic-backup/init.sh

This will:

- Verify access to the Backblaze B2 repository.
- Initialize the restic repository if needed.
- Enable and start the restic-backup.timer systemd timer.


---

## Repo Contents

install.sh                    (installer)
backup.sh                     (main backup script)
systemd/restic-backup.service (systemd service)
systemd/restic-backup.timer   (systemd timer)
motd/90-restic-backup-status  (MOTD hook script)
examples/10-mysql-dump-example.sh (pre-backup hook example)

Installed system locations:

/etc/restic-backup/
/usr/local/bin/restic-backup.sh
/etc/systemd/system/restic-backup.service
/etc/systemd/system/restic-backup.timer
/etc/update-motd.d/90-restic-backup-status

---

## Features

### Automated backups  
Runs twice weekly at 04:00, with Persistent=true so missed runs trigger after boot.

### Notifications via ntfy  
- Success: priority 1  
- Warning: priority 3  
- Failure: priority 5  

### Optional heartbeat support  
If configured, heartbeat URL is pinged on success or warning.

### Pre-backup hooks  
Any executable .sh script in /etc/restic-backup/pre-backup.d/ will run before backup.

### MOTD error display  
Warnings and failures appear in MOTD. Success clears the MOTD entry.

### Pruning policy  
--keep-last 5  
--keep-weekly 4  
--keep-monthly 3  

Runs only after successful or warning backups.

### Idempotent installer  
Re-running install.sh updates scripts, not config, unless --force-config is used.

### Dry-run mode  
restic-backup.sh --dry-run  
restic-backup.sh -n

Simulates backup and prune without notifying or modifying state.

---

## Manual backup & logs

Run manually:

sudo systemctl start restic-backup.service

Check logs:

journalctl -u restic-backup.service

---

## Quick Restore Instructions

See /etc/restic-backup/README.md for complete details.

Source config:

source /etc/restic-backup/config

List snapshots:

restic snapshots

Restore a directory:

restic restore <snapshot-id> --target /restore --include /etc

Restore a file:

restic restore <snapshot-id> --target /restore --include /etc/nginx/nginx.conf

---

## License

MIT (or update as desired)

---

## Contributions

PRs welcome.
