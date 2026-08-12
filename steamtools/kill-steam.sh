#!/bin/bash
# Stop the whole box: quits Steam, which makes gamescope exit, which ends the
# entrypoint and stops the container. Start it again from the TrueNAS Apps UI.
LOG=/tmp/steamtools.log
echo "$(date) kill-steam: stopping Steam / container" >> "$LOG"
pkill -TERM -x steam 2>/dev/null || true
sleep 5
pkill -KILL -x steam 2>/dev/null || true
exit 0
