# Tailscale Omarchy Widget

Native Omarchy bar widget for Tailscale.

## Features

- Shows Tailscale connection state in the bar
- Left click opens a keyboard-friendly panel
- Right click toggles Tailscale on/off
- Switch between logged-in Tailscale accounts when multiple are available
- Browse peers from `tailscale status --json`
- Copy a peer's Tailscale IP, host name, or DNS name

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row
- `c`: copy selected peer IP
- `n`: copy selected peer name
- `d`: copy selected peer DNS name
- `t`: toggle Tailscale
- `r`: refresh status
- `esc`: close

## Requirements

- `tailscale` CLI on `PATH`
- `wl-copy` for clipboard copy actions

## Icon

Renders the Tailscale mark natively as a theme-colored 3×3 dot grid, matching the official SVG silhouette while avoiding tiny-SVG rendering quirks in the bar.

## Install locally

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Work/omarchy-shell-plugins/tailscale ~/.config/omarchy/plugins/tailscale
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled tailscale true
```

Then add `{ "id": "tailscale" }` to one of the `bar.layout` sections in `~/.config/omarchy/shell.json` (or add it through Omarchy's bar settings UI) and restart the shell.
