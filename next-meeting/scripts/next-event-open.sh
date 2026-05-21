#!/usr/bin/env bash

set -u

lookahead_days=${1-7}
meet_open_mode=${2-chrome-app}
meet_open_command=${3-}
landing_url="https://meet.google.com/landing"

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

event_pick=$(printf '%s\n' "$agenda" | awk -F '\t' -v cutoff="$start_time" '
  NR == 1 { next }
  {
    event_date = $1
    start = $2
    hangout_link = $6
    conference_uri = $8

    if (start == "") next
    if ((event_date " " start) < cutoff) next
    if (conference_uri ~ /^https:\/\/meet\.google\.com\//) url = conference_uri
    else if (hangout_link ~ /^https:\/\/meet\.google\.com\//) url = hangout_link
    else next

    slot = event_date "\t" start
    if (!(slot in seen)) {
      seen[slot] = 1
      order[++count] = slot
    }

    event_count[slot]++
    if (!(slot in first_url)) first_url[slot] = url
  }
  END {
    for (i = 1; i <= count; i++) {
      slot = order[i]
      print event_count[slot] "\t" first_url[slot]
      exit
    }
  }
')

if [ -z "$event_pick" ]; then
  exit 0
fi

event_count=${event_pick%%$'\t'*}
url=${event_pick#*$'\t'}

case "$event_count" in
  ''|*[!0-9]*) event_count=1 ;;
esac

if [ "$event_count" -ge 2 ]; then
  url="$landing_url"
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
        or (.initialTitle // "" | contains("meet.google.com"))
        or ((.title // "" | test("Google Meet|Meet$|meet\\.google\\.com|Your meetings"; "i")) and (.class // "" | test("chrome|chromium"; "i")))
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
