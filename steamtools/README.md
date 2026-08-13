# steamos recovery toolbar

Kill/restart buttons + hotkeys for the headless sway session, so a frozen
fullscreen game can be closed from Moonlight without rebooting the box.

The toolbar is **Waybar** (`extra/waybar`, gtk-layer-shell — Wayland-native,
no i3bar/JSON status protocol). It sits on layer **top** at the bottom, so it
is hidden behind fullscreen games and never covers them; it is visible over
Steam Big Picture / the desktop. Use the hotkeys (always work, even over a
frozen game) or reveal the bar over a game with `Mod4+Ctrl+Shift+B`.

## Buttons (bottom bar)

| Button | Action |
|---|---|
| `[X] Close` | Graceful window close (`swaymsg kill`), force-kill the game tree after 10s |
| `[R] Restart` | Emergency force-close of the focused game → back to Steam Big Picture |
| `[S] Kill Steam` | Quit Steam → container stops (restart from TrueNAS Apps UI) |
| `[M] Minimize` | Hide the bar (SIGUSR1 toggle; show again with `Mod4+Ctrl+Shift+B`) |

## Hotkeys (same actions, work even over a frozen fullscreen game)

| Combo | Action |
|---|---|
| `Mod4+Ctrl+Shift+Q` | Close focused game |
| `Mod4+Ctrl+Shift+R` | Force-restart focused game (back to Steam) |
| `Mod4+Ctrl+Shift+X` | Kill Steam / stop the box |
| `Mod4+Ctrl+Shift+B` | Reveal the bar over the current game (un-fullscreens it) |

`Mod4` = the Super/Windows key. Keys reach sway because Sunshine's virtual
input is a uinput device picked up by sway's libinput backend.

## How it works

- `waybar/config.jsonc` + `waybar/style.css` — toolbar definition: custom
  modules with native `on-click` handlers calling the scripts (detached via
  `sh -c '... & disown'` to avoid the waybar pointer-grab re-fire issue).
- `reveal-bar.sh` — un-fullscreens the focused game (if `steam_app_*`) so the
  top-layer bar becomes visible over it, and un-hides the bar if minimized.
- `close-game.sh` — graceful close, escalates to a force-kill.
- `restart-game.sh` — force-kills the focused game's whole Proton process tree
  (walks /proc up to the `SteamLaunch AppId=` root), leaving Steam running.
- `kill-steam.sh` — quits Steam, which ends the entrypoint and stops the box.
- `common.sh` — shared sway-IPC helpers (focused-window parser, kill_tree).

Logs: `/tmp/steamtools.log` inside the container.

## Why not swaybar?

swaybar's `status_command` sends **SIGTERM to the status child's process group**
a few seconds after spawn (`status_line_free` in sway 1.12), killing any status
script — even a perfect i3bar one — which is why the first attempt showed
`[invalid i3bar json]`. Waybar renders natively via gtk-layer-shell and has no
such status-command lifecycle, so buttons/clicks are reliable.

## Deployment

The image ships the scripts under `/usr/local/lib/steamtools/` and the waybar
config under `/usr/local/lib/steamos-waybar/`; the entrypoint copies both into
`$HOME/steamtools` and `$HOME/.config/waybar` on boot (`cp -n`, never
overwrites edits). sway.config launches `waybar` via `exec_always` and has no
`bar {}` block (so swaybar never runs).
