#!/usr/bin/env bash

set -u

lookahead_days=${1-7}
meet_open_mode=${2-chrome-app}
meet_open_command=${3-}

case "$lookahead_days" in
  ''|*[!0-9]*) lookahead_days=7 ;;
esac

if [ "$lookahead_days" -lt 1 ]; then lookahead_days=1; fi
if [ "$lookahead_days" -gt 30 ]; then lookahead_days=30; fi

if ! command -v gcalcli >/dev/null 2>&1; then
  exit 0
fi

start_time=$(date -d '-5 minutes' '+%Y-%m-%d %H:%M')
end_time=$(date -d "+${lookahead_days} days" '+%Y-%m-%d %H:%M')

agenda=$(gcalcli agenda "$start_time" "$end_time" --nodeclined --tsv --details title --details conference --details url 2>/dev/null || true)

if [ -z "$agenda" ]; then
  exit 0
fi

url=$(printf '%s\n' "$agenda" | awk -F '\t' -v cutoff="$start_time" '
  NR == 1 { next }
  {
    event_date = $1
    start = $2
    hangout_link = $6
    conference_uri = $8

    if (start == "") next
    if ((event_date " " start) < cutoff) next
    if (conference_uri ~ /^https:\/\/meet\.google\.com\//) print conference_uri
    else if (hangout_link ~ /^https:\/\/meet\.google\.com\//) print hangout_link
    else next
    exit
  }
')

if [ -z "$url" ]; then
  exit 0
fi

case "$meet_open_mode" in
  chrome-app|system-browser|custom-command) ;;
  *) meet_open_mode=chrome-app ;;
esac

open_with_system_browser() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  fi
}

case "$meet_open_mode" in
  system-browser)
    open_with_system_browser
    exit 0
    ;;
  custom-command)
    if [ -n "$meet_open_command" ]; then
      NEXT_MEETING_URL="$url" bash -c "$meet_open_command" >/dev/null 2>&1 &
    else
      open_with_system_browser
    fi
    exit 0
    ;;
esac

chrome_cmd=$(command -v google-chrome-stable 2>/dev/null || true)
if [ -z "$chrome_cmd" ]; then
  open_with_system_browser
  exit 0
fi

"$chrome_cmd" --new-window --ozone-platform=x11 --disable-features=WaylandWpColorManagerV1 --disable-gpu-compositing --app="$url" >/dev/null 2>&1 &

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
