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

### `next-meeting`

Shows your next calendar event in the Omarchy bar and opens the Google Meet link on click.

Features:

- Uses `gcalcli` agenda data for upcoming events
- Only includes calendar events that have a Google Meet link
- Shows the next event for today, then falls back to a schedule-clear message
- Opens Google Meet in a Chrome app window by default and nudges it into Hyprland tiling if possible
- Can use the system browser or a custom command instead

Dependencies:

- `gcalcli`
- `google-chrome-stable` is recommended for the default Chrome app launch mode because Google Meet background effects are more reliable there on many Linux setups
- Optional: `jq` and `hyprctl` for nudging the opened Meet window into Hyprland tiling

Settings live in `~/.config/omarchy/shell.json` and can be edited via `omarchy launch bar settings`. Exposes `refresh` and `open` over Omarchy shell IPC on the `next-meeting` target.

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

Install `next-meeting` locally:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/next-meeting ~/.config/omarchy/plugins/next-meeting
omarchy shell shell setPluginEnabled next-meeting true
omarchy restart shell
```

If the plugin already exists, remove it first:

```bash
rm -rf ~/.config/omarchy/plugins/next-meeting
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
