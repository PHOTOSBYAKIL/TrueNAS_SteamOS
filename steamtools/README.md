# steamos title bar + window controls

The headless sway session presents a **top title bar** over the streamed
Steam Big Picture / game UI (Windows-style): the focused window's title on the
left, and window control buttons on the right. It replaces the old bottom
"recovery toolbar", which didn't work as intended (sway hides layer-top bars
behind fullscreen windows, so the bar vanished during games).

## Why the bar is always visible

The sway config uses a **tabbed workspace layout** and does NOT force anything
compositor-fullscreen. A launched game becomes a new tab that fills the output
below the title bar, so the bar is never covered. The sway tab strip (styled in
`sway.config`) doubles as a lightweight taskbar: click a tab to switch apps,
drag a tab to reorder.

## Title bar (waybar, layer top, position top)

| Module | Control | Action |
|---|---|---|
| `sway/window` (left) | — | Live title of the focused app |
| `custom/hidden` (left) | — | "minimized — click – to restore" hint, shown only while the app is hidden |
| `[–]` minimize | button | Toggle: hide focused app (sway scratchpad), click again (or the hint) to restore |
| `[▢]` maximize | button | Fill the entire screen (compositor-fullscreen; bar hides) |
| `[✕]` close | button | Game focused → graceful close (force-kill after 10s) and back to Steam BP. Steam focused (or no game focused) → quit Steam, which stops the container, drops the stream, and returns the Moonlight client to its selection screen. |

`waybar/config.jsonc` + `waybar/style.css` — title bar definition (custom
modules with native `on-click` handlers calling the scripts, detached via
`sh -c '... & disown'` to avoid the waybar pointer-grab re-fire issue).

## Hotkeys (same actions, work even when a maximized window covers the bar)

| Combo | Action |
|---|---|
| `Mod4+Ctrl+Shift+Q` | Close focused app (game → back to Steam; Steam → end session / Moonlight selection) |
| `Mod4+Ctrl+Shift+R` | Force-restart focused app (back to Steam) |
| `Mod4+Ctrl+Shift+X` | Kill Steam / stop the box |
| `Mod4+Ctrl+Shift+M` | Restore the minimized (scratchpad) app |
| `Mod4+Ctrl+Shift+B` | Un-maximize focused app + show the title bar |

`Mod4` = the Super/Windows key. Keys reach sway because Sunshine's virtual
input is a uinput device picked up by sway's libinput backend.

## Scripts

- `common.sh` — shared sway-IPC helpers (focused-window parser, `kill_tree`).
- `close-game.sh` — graceful close, escalates to a force-kill.
- `restart-game.sh` — force-kills the focused game's whole Proton process tree
  (walks /proc up to the `SteamLaunch AppId=` root), leaving Steam running.
- `kill-steam.sh` — quits Steam, which ends the entrypoint and stops the box.
- `minimize-toggle.sh` — toggle: hide the focused app (scratchpad) or restore it.
- `minimize-restore.sh` — `swaymsg scratchpad show` + re-tile Steam (hotkey M).
- `hidden-indicator.sh` — prints the "minimized — click – to restore" hint when
  the focused app is hidden (polled by the waybar `custom/hidden` module).
- `reveal-bar.sh` — un-fullscreens the focused app + shows the title bar
  (maximize recovery).

Logs: `/tmp/steamtools.log` inside the container.

## Why not swaybar?

swaybar's `status_command` sends **SIGTERM to the status child's process group**
a few seconds after spawn (`status_line_free` in sway 1.12), killing any status
script. Waybar renders natively via gtk-layer-shell and has no such
status-command lifecycle, so buttons/clicks are reliable.

## Deployment

The image ships the scripts under `/usr/local/lib/steamtools/` and the waybar
config under `/usr/local/lib/steamos-waybar/`; the entrypoint copies both into
`$HOME/steamtools` and `$HOME/.config/waybar` on boot (`cp -n`, never
overwrites edits). sway.config launches `waybar` via `exec_always` and has no
`bar {}` block (so swaybar never runs).
