#!/usr/bin/env bash

set -u

url=${1-}
meeting_open_mode=${2-chrome-app}
meeting_open_command=${3-}
chrome_app_flags=${4-}

if [ -z "$url" ]; then
  exit 0
fi

case "$meeting_open_mode" in
  chrome-app|system-browser|custom-command) ;;
  *) meeting_open_mode=chrome-app ;;
esac

open_with_system_browser() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  fi
}

case "$meeting_open_mode" in
  system-browser)
    open_with_system_browser
    exit 0
    ;;
  custom-command)
    if [ -n "$meeting_open_command" ]; then
      NEXT_MEETING_URL="$url" MEETING_URL="$url" bash -c "$meeting_open_command" >/dev/null 2>&1 &
    else
      open_with_system_browser
    fi
    exit 0
    ;;
esac

# Chrome app mode is specifically for Google Meet: it keeps the meeting in a
# dedicated window and preserves the historical Meet behaviour of this plugin.
# For Zoom (and other providers), prefer xdg-open so desktop URL handlers can
# hand the link to the native app when available.
case "$url" in
  https://meet.google.com/*|http://meet.google.com/*) ;;
  *)
    open_with_system_browser
    exit 0
    ;;
esac

chrome_cmd=$(command -v google-chrome-stable 2>/dev/null || command -v google-chrome 2>/dev/null || command -v chromium 2>/dev/null || true)
if [ -z "$chrome_cmd" ]; then
  open_with_system_browser
  exit 0
fi

# shellcheck disable=SC2206
extra_flags=( $chrome_app_flags )
"$chrome_cmd" --new-window "${extra_flags[@]}" --app="$url" >/dev/null 2>&1 &

if ! command -v jq >/dev/null 2>&1 || ! command -v hyprctl >/dev/null 2>&1; then
  exit 0
fi

(
  for _ in {1..40}; do
    sleep 0.25

    client=$(hyprctl clients -j 2>/dev/null | jq -r '
      map(select(
        (.class // "" | contains("meet.google.com"))
        or (.initialTitle // "" | startswith("meet.google.com"))
        or ((.title // "" | test("Google Meet|Meet$")) and (.class // "" | test("chrome|chromium"; "i")))
      ))
      | sort_by(.focusHistoryID)
      | .[0]
      | select(.address != null)
      | [.address, .floating]
      | @tsv
    ')

    if [ -n "$client" ]; then
      address=${client%%$'\t'*}
      floating=${client##*$'\t'}

      if [ "$floating" = "true" ]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1
        hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' >/dev/null 2>&1
      fi
      break
    fi
  done
) >/dev/null 2>&1 &
