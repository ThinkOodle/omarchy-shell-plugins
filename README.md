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

### `omarchy-screen-toolkit`

Screen-tool bar widget: color picker (HEX/RGB/HSL/HSV with history), palette extraction, OCR, QR / barcode, Google Lens, screenshot, mp4 + GIF screen recording, and overlay stubs for pin/measure/mirror.

See [`omarchy-screen-toolkit/README.md`](omarchy-screen-toolkit/README.md) for the dependency list and settings.

## Install locally

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Code/omarchy-shell-plugins/<plugin> ~/.config/omarchy/plugins/<plugin>
omarchy-shell shell setPluginEnabled <plugin> true
omarchy restart shell
```

If a plugin directory already exists, remove it first:

```bash
rm -rf ~/.config/omarchy/plugins/<plugin>
```
