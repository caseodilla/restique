#!/usr/bin/env bash
echo "Useful systemd timer commands:"
echo
echo "Edit timer:"
echo "  sudo nano /etc/systemd/system/restic-backup.timer"
echo
echo "Reload systemd after editing:"
echo "  sudo systemctl daemon-reload"
echo
echo "Restart the timer:"
echo "  sudo systemctl restart restic-backup.timer"
echo
echo "View next run time:"
echo "  systemctl list-timers | grep restic"
echo
echo "Run backup now:"
echo "  sudo systemctl start restic-backup.service"
