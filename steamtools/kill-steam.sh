#!/bin/bash
# Stop the whole box: quits Steam, which ends the entrypoint and stops the
# container. Start it again from the TrueNAS Apps UI (Start button).
LOG=/tmp/steamtools.log
echo "$(date) kill-steam: stopping Steam / container" >> "$LOG"
pkill -TERM -f 'steam -tenfoot' 2>/dev/null
sleep 5
pkill -KILL -f 'steam -tenfoot' 2>/dev/null
exit 0
