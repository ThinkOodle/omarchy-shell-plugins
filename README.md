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
