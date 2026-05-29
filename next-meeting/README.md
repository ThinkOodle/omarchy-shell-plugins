# NextMeeting

NextMeeting is an Omarchy shell bar widget that shows your next joinable video meeting and opens a full-day calendar panel on click.

It uses [`gcalcli`](https://github.com/insanum/gcalcli) to read Google Calendar from the command line.

## Features

- Shows the next non-declined Google Meet or Zoom meeting for today in the bar.
- Left-click opens a keyboard-friendly agenda panel that can flip through the configured lookahead window.
- Meeting rows show a clickable **Meet**, **Zoom**, or generic video join button.
- Right-click opens inline plugin settings; no central settings pane required.
- Middle-click refreshes calendar data immediately.
- Google Meet can open in a Chrome app window; Zoom and other providers use the system URL handler by default.
- Exposes `show`, `toggle`, `refresh`, `open`/`join`, and `settings` over Omarchy shell IPC.

## Requirements

- Omarchy shell with plugin support.
- `gcalcli` installed and authenticated.
- `python3` (already required by `gcalcli`).
- `google-chrome-stable`, `google-chrome`, or `chromium` is recommended for Google Meet chrome-app mode. If none are installed, NextMeeting falls back to your system URL handler.
- Optional: `jq` and `hyprctl` for nudging Google Meet Chrome app windows into Hyprland tiling.

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

- Left-click: show the agenda panel.
- Click a row's **Meet**, **Zoom**, or video button: join that meeting.
- Right-click: open NextMeeting settings.
- Middle-click: refresh calendar data immediately.
- Keyboard in the panel: `h`/`l` changes day, `j`/`k` selects, `Enter` joins the selected video meeting, `r` refreshes, `s` opens/saves settings, `Esc` closes.

By default, NextMeeting auto-refreshes every 30 minutes. Middle-click is useful when you just added or changed a meeting and do not want to wait for the next automatic refresh.

### IPC

The widget exposes IPC functions on the `next-meeting` target:

```bash
omarchy-shell ipc call next-meeting show
omarchy-shell ipc call next-meeting toggle
omarchy-shell ipc call next-meeting refresh
omarchy-shell ipc call next-meeting open      # join the next meeting
omarchy-shell ipc call next-meeting settings
```

`open`/`join` is a no-op when there is no current joinable meeting.

## Configure

Right-click the widget, edit settings inline, then click **Save**. The widget writes changes to `~/.config/omarchy/shell.json` when the shell exposes `updateEntryInline`.

You can also edit the `next-meeting` entry directly:

```json
{
  "id": "next-meeting",
  "refreshIntervalSec": 1800,
  "scheduleClearText": "No more meetings today ✅",
  "lookaheadDays": 7,
  "maxDisplayChars": 42,
  "meetOpenMode": "chrome-app",
  "meetOpenCommand": "",
  "chromeAppFlags": "--ozone-platform=x11 --disable-features=WaylandWpColorManagerV1 --disable-gpu-compositing",
  "calendars": []
}
```

Settings:

| Setting | Default | Description |
| --- | ---: | --- |
| `refreshIntervalSec` | `1800` | Seconds between automatic calendar checks. |
| `scheduleClearText` | `No more meetings today ✅` | Text shown when there are no more joinable video meetings today. |
| `lookaheadDays` | `7` | How many days `gcalcli` fetches and how far the agenda panel can flip forward. |
| `maxDisplayChars` | `42` | Maximum bar label length before truncating with `...`. |
| `meetOpenMode` | `chrome-app` | `chrome-app`, `system-browser`, or `custom-command`. Chrome app mode applies to Google Meet; Zoom uses the system URL handler unless custom mode is selected. |
| `meetOpenCommand` | empty | Command used only in `custom-command` mode. `$NEXT_MEETING_URL` and `$MEETING_URL` contain the join URL. |
| `chromeAppFlags` | see above | Flags passed to Chrome for Google Meet chrome-app mode. |
| `calendars` | empty | Calendar names to consider. Empty means all calendars. Inline settings accepts comma-separated names; JSON may use an array. |

## Meeting Detection

Every refresh runs `gcalcli agenda` with TSV output and details for title, conference, URL, description, and location. NextMeeting treats these as joinable video meetings:

- Google Meet links (`meet.google.com`).
- Zoom links (`zoom.us`, `zoom.com`, `zoomgov.com`) from conference fields, descriptions, or locations.
- Common video providers such as Teams, Webex, and Whereby are shown with a generic join button.

The bar label shows the next joinable video meeting today. The panel starts on today and can flip through the lookahead window, with join buttons only on rows where a video link was found.

## Files

- `manifest.json`: plugin metadata and settings schema.
- `Widget.qml`: bar entry, day-agenda panel, and inline settings UI.
- `Main.qml`: refresh timer, process wiring, payload parsing, and meeting launching.
- `scripts/next-event.sh`: fetches agenda TSV from `gcalcli`.
- `scripts/agenda-to-json.py`: converts agenda TSV into the widget JSON payload.
- `scripts/next-event-open.sh`: opens a join URL using the configured launch mode.
- `scripts/list-calendars.sh`: emits calendar options for schema-based settings UIs.

## Troubleshooting

If the widget does not show anything:

1. Confirm `gcalcli` is installed: `command -v gcalcli`
2. Confirm `gcalcli agenda ...` works from a terminal.
3. Confirm `next-meeting` is present in `~/.config/omarchy/shell.json`.
4. Restart the shell: `omarchy restart shell`

If a meeting has no join button:

1. Confirm the event contains a Meet or Zoom URL in the conference field, description, or location.
2. Middle-click the widget to refresh.
3. Run the agenda command in a terminal and verify the link appears in `gcalcli` output.
