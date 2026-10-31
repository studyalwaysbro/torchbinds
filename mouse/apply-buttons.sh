#!/usr/bin/env bash
# Keeps the Scimitar's buttons the way Torch Binds expects, whenever the mouse (re)appears:
#   the two buttons behind the wheel = mouse 5 and mouse 4 (no more sensitivity switching)
#   thumb buttons 1 and 2 = mouse 4 and mouse 5 (Dota Inventory1/Inventory2); the other ten = 3 4 5 6 7 8 9 0 - =
# No DPI command is ever sent, so the sensitivity stays whatever the mouse already has.
# To go back to the mouse's own behaviour: systemctl --user disable --now scimitar-buttons, then
#   echo idle > /dev/input/ckb1/cmd
last=""
while true; do
  for dev in /dev/input/ckb[1-9]; do
    cmd="$dev/cmd"
    [ -p "$cmd" ] || continue
    grep -qi "scimitar" "$dev/model" 2>/dev/null || continue
    stamp="$dev $(stat -c '%i %Y' "$dev/model" 2>/dev/null)"   # changes when the mouse is replugged or the daemon restarts
    if [ "$stamp" != "$last" ]; then
      sleep 2
      {
        echo "active"
        echo "bind dpiup:mouse5 dpidn:mouse4 thumb1:mouse4 thumb2:mouse5 thumb3:3 thumb4:4 thumb5:5 thumb6:6 thumb7:7 thumb8:8 thumb9:9 thumb10:0 thumb11:minus thumb12:equal"
      } > "$cmd" 2>/dev/null && last="$stamp" && echo "$(date '+%F %T') applied to $dev"
    fi
  done
  sleep 5
done
