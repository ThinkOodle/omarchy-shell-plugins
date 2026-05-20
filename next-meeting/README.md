# NextMeeting

NextMeeting is an Omarchy shell bar widget that shows your next Google Calendar event and opens its Google Meet link on click.

It uses [`gcalcli`](https://github.com/insanum/gcalcli) to read your calendar from the command line.

## Features

- Shows the next non-declined calendar event for today that has a Google Meet link.
- Ignores calendar events without a `https://meet.google.com/...` link.
- Shows configurable schedule-clear text when there are no more meetings today.
- Left-click opens the next Google Meet link, when one is available.
- Right-click refreshes the calendar immediately.
- Auto-refresh interval is configurable.

## Requirements

- Omarchy shell with plugin support.
- `gcalcli` installed and authenticated.
- `jq` if you want to use the included TUI configuration script.
- `jq` and `hyprctl` are optional for nudging the opened Meet window into Hyprland tiling.
- `gum` is optional for nicer TUI prompts.
- `google-chrome-stable` is recommended for the default Chrome app launch mode. If it is not installed, NextMeeting falls back to your system browser.

## Install

Place this plugin at:

```text
~/.config/omarchy/plugins/next-meeting
```

Then add `next-meeting` to your bar layout in `~/.config/omarchy/shell.json`:

```json
{
  "id": "next-meeting"
}
```

Example left-side layout:

```json
"left": [
  { "id": "omarchy" },
  { "id": "workspaces" },
  { "id": "next-meeting" }
]
```

Restart the shell if it does not appear automatically:

```bash
omarchy restart shell
```

## gcalcli Setup

NextMeeting depends on `gcalcli agenda`, so `gcalcli` must work before the widget can show meetings.

Follow the upstream `gcalcli` authentication guide:

https://github.com/insanum/gcalcli/blob/HEAD/docs/api-auth.md

After setup, verify this command works in a terminal:

```bash
gcalcli agenda "$(date '+%Y-%m-%d 00:00')" "$(date -d '+1 day' '+%Y-%m-%d 00:00')" --nodeclined
```

If that command cannot read your calendar, NextMeeting will stay hidden.

## Usage

- Left-click: open the next event's Google Meet link.
- Right-click: refresh calendar data immediately.

By default, NextMeeting auto-refreshes every 30 minutes. Right-click is useful when you just added or changed a meeting and do not want to wait for the next automatic refresh.

## Configure With The Omarchy GUI

NextMeeting exposes a settings schema to Omarchy's bar settings panel.

Open the bar settings panel:

```bash
omarchy launch bar settings
```

Select `NextMeeting` and edit its settings. The panel writes changes to `~/.config/omarchy/shell.json`.

## Configure With The TUI

Run:

```bash
~/.config/omarchy/plugins/next-meeting/scripts/configure.sh
```

If `gum` is installed, the script uses `gum input` prompts. Otherwise it falls back to plain terminal prompts.

The script updates the `next-meeting` entry in `~/.config/omarchy/shell.json` and creates a timestamped backup first.

## Manual Configuration

You can also edit the `next-meeting` entry in `~/.config/omarchy/shell.json` directly:

```json
{
  "id": "next-meeting",
  "refreshIntervalSec": 1800,
  "scheduleClearText": "No more meetings today ✅",
  "lookaheadDays": 7,
  "maxDisplayChars": 42,
  "meetOpenMode": "chrome-app",
  "meetOpenCommand": ""
}
```

Settings:

| Setting | Default | Description |
| --- | ---: | --- |
| `refreshIntervalSec` | `1800` | Seconds between automatic calendar checks. Minimum `60`, maximum `86400`. |
| `scheduleClearText` | `No more meetings today ✅` | Text shown when there are no more meetings today. |
| `lookaheadDays` | `7` | How many days `gcalcli` scans for the next event. |
| `maxDisplayChars` | `42` | Maximum meeting label length before truncating with `...`. |
| `meetOpenMode` | `chrome-app` | How to open Meet links: `chrome-app`, `system-browser`, or `custom-command`. |
| `meetOpenCommand` | empty | Command used only when `meetOpenMode` is `custom-command`. The Meet URL is available as `$NEXT_MEETING_URL`. |

## Meeting Launch Modes

By default, NextMeeting opens meetings with google-chrome-stable in Chrome app mode. Google Meet background effects (and sometimes device handling) are generally more reliable in Google Chrome Stable on Linux.

For alternative setups, set meetOpenMode to system-browser or custom-command in NextMeeting settings. The Meet URL is available as $NEXT_MEETING_URL.

```json
{
  "id": "next-meeting",
  "meetOpenMode": "custom-command",
  "meetOpenCommand": "firefox --new-window \"$NEXT_MEETING_URL\""
}
```

The Hyprland tiling nudge only runs for the default `chrome-app` mode, and only when both `jq` and `hyprctl` are installed.

## How It Works

Every refresh runs:

```bash
gcalcli agenda <start> <end> --nodeclined --tsv --details title --details conference --details url
```

The widget scans for events within the configured lookahead window, but it only displays events that include a Google Meet link. A meeting will remain in the widget for 5 minutes past its start time, after which the next Google Meet event on your calendar will take its place.

If the next event is not today, NextMeeting shows the no-more-meetings text instead.

## Files

- `manifest.json`: plugin metadata and GUI settings schema.
- `Widget.qml`: visible bar widget and click handling.
- `Main.qml`: refresh timer, settings, and process wiring.
- `scripts/next-event.sh`: fetches and formats the next calendar event.
- `scripts/next-event-open.sh`: opens the next event's Google Meet link using the configured launch mode. If `jq` and `hyprctl` are available in `chrome-app` mode, it also tries to nudge the Chrome app window into Hyprland tiling.
- `scripts/configure.sh`: optional TUI for editing widget settings.

## Troubleshooting

If the widget does not show anything:

1. Confirm `gcalcli` is installed: `command -v gcalcli`
2. Confirm `gcalcli agenda ...` works from a terminal.
3. Confirm `next-meeting` is present in `~/.config/omarchy/shell.json`.
4. Restart the shell: `omarchy restart shell`

If left-click does not open Meet:

1. Confirm the event has a Google Meet link.
2. Confirm `google-chrome-stable` is installed.
3. Right-click the widget to refresh, then left-click again.
