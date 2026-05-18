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
