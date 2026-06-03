#!/usr/bin/env bash

set -u

url=${1-}
meeting_open_mode=${2-system-browser}
meeting_open_command=${3-}

if [ -z "$url" ]; then
  exit 0
fi

# `chrome-app` is accepted only for backwards compatibility with older
# NextMeeting settings. The supported choices are now the default browser or a
# custom command.
case "$meeting_open_mode" in
  system-browser|custom-command) ;;
  chrome-app) meeting_open_mode=system-browser ;;
  *) meeting_open_mode=system-browser ;;
esac

open_with_system_browser() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  fi
}

case "$meeting_open_mode" in
  custom-command)
    if [ -n "$meeting_open_command" ]; then
      NEXT_MEETING_URL="$url" MEETING_URL="$url" bash -c "$meeting_open_command" >/dev/null 2>&1 &
    else
      open_with_system_browser
    fi
    ;;
  *)
    open_with_system_browser
    ;;
esac
