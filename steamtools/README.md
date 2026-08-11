# steamos recovery toolbar

Kill/restart buttons + hotkeys for the headless sway session, so a frozen
fullscreen game can be closed from Moonlight without rebooting the box.

## Buttons (bottom bar, always on top)

| Button | Action |
|---|---|
| `[X] Close` | Graceful window close (`swaymsg kill`), force-kill the game tree after 10s |
| `[R] Restart` | Emergency force-close of the focused game → back to Steam Big Picture |
| `[S] Kill Steam` | Quit Steam → container stops (restart from TrueNAS Apps UI) |
| `[B] Hide Bar` | Toggle bar overlay ↔ hidden |

## Hotkeys (same actions, work even over a frozen fullscreen game)

| Combo | Action |
|---|---|
| `Mod4+Ctrl+Shift+Q` | Close focused game |
| `Mod4+Ctrl+Shift+R` | Force-restart focused game (back to Steam) |
| `Mod4+Ctrl+Shift+X` | Kill Steam / stop the box |
| `Mod4+Ctrl+Shift+B` | Toggle bar visibility |

`Mod4` = the Super/Windows key. Keys reach sway because Sunshine's virtual
input is a uinput device picked up by sway's libinput backend.

## How it works

- `toolbar-status.sh` — swaybar `status_command`; renders the clickable blocks
  and dispatches clicks to the action scripts.
- `close-game.sh` — graceful close, escalates to a force-kill.
- `restart-game.sh` — force-kills the focused game's whole Proton process tree
  (walks /proc up to the `SteamLaunch AppId=` root), leaving Steam running.
- `kill-steam.sh` — quits Steam, which ends the entrypoint and stops the box.
- `common.sh` — shared sway-IPC helpers.

Logs: `/tmp/steamtools.log` inside the container.

## Deployment

The image ships these under `/usr/local/lib/steamtools/`; the entrypoint
copies them into `$HOME/steamtools` on boot (`cp -n`, never overwrites edits).
sway.config references `/home/steam/steamtools/...`.
