# steamos recovery tools

Force-close tools for the headless **sway + nested gamescope** box, so a
frozen fullscreen game can be killed from Moonlight without rebooting the
machine.

Recovery actions are exposed three ways:

1. **Sway hotkeys** (work even over a frozen fullscreen game, since Sunshine's
   input is a uinput device that sway's libinput backend sees):
   `Mod4+Ctrl+Shift+Q` close, `+R` force-restart, `+X` kill Steam,
   `+B` reveal the waybar toolbar (un-fullscreens the gamescope surface).
2. **Waybar toolbar** (layer-top, bottom): `[X] Close`, `[R] Restart`,
   `[S] Kill Steam`, `[M] Minimize` buttons — clickable once revealed.
3. **Sunshine apps** launched straight from the Moonlight client app list.

| App (Moonlight) | Script | Action |
|---|---|---|
| `Close Game` | `close-game.sh` | Force-kill the running game's Proton process tree → back to Steam Gamepad UI |
| `Restart Steam` | `restart-game.sh` | Same engine, labelled as a hard restart (frozen games) |
| `Kill Steam` | `kill-steam.sh` | Quit Steam → gamescope exits → container stops (start from TrueNAS Apps UI) |

## How it works

- `common.sh` — `kill_tree` walks `/proc` up to the `SteamLaunch AppId=`
  reaper root and takes the whole Proton tree down (leaving Steam itself
  running). `get_game_pid` scans `/proc` for the most recently started
  `SteamLaunch AppId=` process — Steam runs inside a nested gamescope, so
  there is no sway window list of game windows to query; Steam's own client
  process never has `SteamLaunch AppId=` in its cmdline, so it is never
  matched.
- The three apps are merged into Sunshine's `apps.json` on first boot by the
  entrypoint (never clobbering apps you added in the Sunshine web UI).
- Logs: `/tmp/steamtools.log` inside the container.

## Deployment

The image ships the scripts under `/usr/local/lib/steamtools/`; the entrypoint
copies them into the bind-mounted `$HOME/steamtools` on boot (`cp -n`, never
overwrites edits) so they can be hot-patched without a rebuild.

The scripts run as the `steam` user (Sunshine's runtime user), so they can read
`/proc` of games/Steam (same owner) to walk the tree.
