# Omarchy Shell Plugins

A collection of third-party plugins for `omarchy-shell`.

## Plugins

### `model-usage`

Claude Code and Codex usage in the Omarchy bar, with a keyboard-friendly tabbed popup.

Features:

- Claude Code and Codex provider tabs
- Bar chips with provider icons and current usage percentage
- 5-hour / weekly rate-limit usage
- Pace indicators for reserve/deficit against reset timing
- Local usage summaries for today, the last 7 days, and all time
- Optional synced aggregation across multiple machines
- Keyboard controls: `←`/`→` or `h`/`l` to switch tabs, `j`/`k` to scroll, `r` to refresh, `Esc` to close

### `tailscale`

Tailscale controls and peer browser in the Omarchy bar.

Features:

- Toggle Tailscale on/off
- Switch between logged-in Tailscale accounts
- Browse peers reported by `tailscale status --json`
- Copy peer IPs, host names, and DNS names
- Keyboard controls: `j`/`k` move, `Enter` activates, `c` copies IP, `n` copies name, `d` copies DNS, `t` toggles, `r` refreshes, `Esc` closes

Dependencies:

- `tailscale`
- `wl-copy` for copy actions

### `orbit`

Cursor-centered radial launcher designed for mouse-button hold/release workflows.

Features:

- Opens an overlay ring at the current cursor position
- Hover-by-direction slice selection with release-to-activate behavior
- Configurable rings/actions via `~/.config/omarchy/orbit.json`
- Bundled default/example rings for everyday actions, window controls, and development tools
- Supports nested rings, shell commands, direct argv commands, and close-only slices
- Includes helper scripts to open at cursor, activate on release, and sniff mouse button codes

Dependencies:

- `wev` for button sniffing
- Python `evdev` module for physical-button release detection

### `neon-bar`

A full replacement bar option for Omarchy Shell. It uses the new `kind: "bar"`
plugin contract, renders the user's configured bar widgets inside a visibly
different floating neon pill/rail, and documents the compatibility surface for
building custom bars.

Features:

- Full-bar replacement selected with `omarchy config shell bar use demo.neon-bar`
- Floating translucent pill/rail chrome so it is visually distinct
- Reuses `bar.layout` widgets from `~/.config/omarchy/shell.json`
- Supports dragging widgets to reorder them in `shell.json`
- Respects `bar.position` and `omarchy toggle bar`
- Provides a documented minimal API for widget compatibility

### `next-meeting`

Shows your next joinable video meeting in the Omarchy bar, with a full-day agenda popup.

Features:

- Uses `gcalcli` agenda data for the configured lookahead window
- Shows the next Google Meet or Zoom meeting for today, then falls back to a schedule-clear message
- Left-click opens an agenda panel with day navigation and clickable Meet/Zoom/video join buttons on meeting rows
- Right-click opens inline plugin settings; middle-click refreshes
- Opens Google Meet in a Chrome app window by default and uses the system URL handler for Zoom unless custom mode is selected
- Can use the system browser or a custom command instead

Dependencies:

- `gcalcli`
- `python3` (already required by `gcalcli`)
- `google-chrome-stable`, `google-chrome`, or `chromium` is recommended for Google Meet chrome-app mode
- Optional: `jq` and `hyprctl` for nudging opened Meet windows into Hyprland tiling

Settings live in `~/.config/omarchy/shell.json` and can be edited inline by right-clicking the widget. Exposes `show`, `toggle`, `refresh`, `open`/`join`, and `settings` over Omarchy shell IPC on the `next-meeting` target.

## Install

Add this repository as a trusted Omarchy plugin source once:

```bash
omarchy plugin source add https://github.com/thinkoodle/omarchy-shell-plugins
omarchy plugin available
```

Then add and enable the plugin you want.

Install `orbit`:

```bash
omarchy plugin add orbit --enable
```

Then sniff your mouse button and bind it:

```bash
~/.config/omarchy/plugins/orbit/scripts/sniff-button.sh
```

See `orbit/README.md` for the Hyprland binding and ring configuration.

Install `neon-bar` and make it the active bar option:

```bash
omarchy plugin add demo.neon-bar --enable
```

Return to the built-in bar:

```bash
omarchy config shell bar reset
```

See `neon-bar/README.md` for the replacement-bar development contract.

Install `next-meeting`:

```bash
omarchy plugin add next-meeting --enable
```

Arrange it afterward if desired:

```bash
omarchy plugin bar move next-meeting --section left --after omarchy.workspaces
```

If a plugin does not appear immediately, reload the shell:

```bash
omarchy restart shell
```

## Optional synced aggregation

The plugin can aggregate local usage stats across multiple machines while leaving provider rate limits account-authoritative/local.

Set **Synced aggregation** to **On**, set **Sync folder** to a folder that is synced between machines (Syncthing, Dropbox, rsync, etc.), and optionally set **Snapshot file name**. Each machine writes one JSON snapshot into that folder and reads all snapshots back for merged today / 7-day / all-time totals.

Optional inline config example:

```json
{
  "id": "model-usage",
  "syncMode": "On",
  "syncDir": "~/Sync/omarchy-model-usage",
  "syncFileName": "laptop.json"
}
```

Use a different `syncFileName` per machine, or leave it blank to use `<hostname>.json`.
