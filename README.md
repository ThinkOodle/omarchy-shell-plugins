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

## Install locally

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/model-usage ~/.config/omarchy/plugins/model-usage
omarchy shell shell setPluginEnabled model-usage true
omarchy restart shell
```

If the plugin already exists, remove it first:

```bash
rm -rf ~/.config/omarchy/plugins/model-usage
```

Install `tailscale` locally:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/tailscale ~/.config/omarchy/plugins/tailscale
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled tailscale true
```

Then add `{ "id": "tailscale" }` to one of the `bar.layout` sections in `~/.config/omarchy/shell.json` (or use Omarchy's bar settings UI), and restart the shell.

Install `orbit` locally:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/orbit ~/.config/omarchy/plugins/orbit
omarchy plugin rescan
omarchy plugin enable orbit
omarchy restart shell
```

Then sniff your mouse button and bind it:

```bash
~/.config/omarchy/plugins/orbit/scripts/sniff-button.sh
```

See `orbit/README.md` for the Hyprland binding and ring configuration.

Install `next-meeting` locally:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/next-meeting ~/.config/omarchy/plugins/next-meeting
omarchy shell shell setPluginEnabled next-meeting true
omarchy restart shell
```

If a plugin already exists, remove it first:

```bash
rm -rf ~/.config/omarchy/plugins/<plugin-id>
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
