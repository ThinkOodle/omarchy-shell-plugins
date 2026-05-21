#!/usr/bin/env bash

set -u

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

emit_off() {
  printf '{"text":"","class":"off"}\n'
}

schedule_clear_text=${1-"No more meetings today ✅"}
lookahead_days=${2-7}
max_display_chars=${3-42}
shift 3 || true
# Remaining args are calendar names, one per arg, passed through verbatim
# to gcalcli as `--calendar <name>` so names containing commas survive.
calendars=("$@")

case "$lookahead_days" in
  ''|*[!0-9]*) lookahead_days=7 ;;
esac

case "$max_display_chars" in
  ''|*[!0-9]*) max_display_chars=42 ;;
esac

if [ "$lookahead_days" -lt 1 ]; then lookahead_days=1; fi
if [ "$lookahead_days" -gt 30 ]; then lookahead_days=30; fi
if [ "$max_display_chars" -lt 12 ]; then max_display_chars=12; fi
if [ "$max_display_chars" -gt 120 ]; then max_display_chars=120; fi

emit_schedule_clear() {
  local escaped_text
  escaped_text=$(json_escape "$schedule_clear_text")
  printf '{"text":"%s"}\n' "$escaped_text"
}

if ! command -v gcalcli >/dev/null 2>&1; then
  emit_off
  exit 0
fi

start_time=$(date -d '-5 minutes' '+%Y-%m-%d %H:%M')
end_time=$(date -d "+${lookahead_days} days" '+%Y-%m-%d %H:%M')

calendar_args=()
for cal in "${calendars[@]}"; do
  [ -n "$cal" ] && calendar_args+=(--calendar "$cal")
done

agenda=$(gcalcli "${calendar_args[@]}" agenda "$start_time" "$end_time" --nodeclined --tsv --details title --details conference --details url 2>/dev/null || true)

if [ -z "$agenda" ]; then
  emit_schedule_clear
  exit 0
fi

# Read columns by header name so this survives gcalcli adding or reordering
# fields. The output line has the next Meet event as TAB-separated:
#   <event_date>\t<start_time>\t<title>\t<meet_url>
next_event=$(printf '%s\n' "$agenda" | awk -F '\t' -v cutoff="$start_time" '
  NR == 1 {
    for (i = 1; i <= NF; i++) {
      if ($i == "start_date") date_col = i
      else if ($i == "start_time") start_col = i
      else if ($i == "hangout_link") hangout_col = i
      else if ($i == "conference_uri") conf_col = i
      else if ($i == "title") title_col = i
    }
    if (!date_col || !start_col || !title_col) exit 1
    next
  }
  {
    event_date = $date_col
    start = $start_col
    title = $title_col
    hangout_link = hangout_col ? $hangout_col : ""
    conference_uri = conf_col ? $conf_col : ""

    if (start == "") next
    if ((event_date " " start) < cutoff) next

    url = ""
    if (conference_uri ~ /^https:\/\/meet\.google\.com\//) url = conference_uri
    else if (hangout_link ~ /^https:\/\/meet\.google\.com\//) url = hangout_link
    else next

    print event_date "\t" start "\t" title "\t" url
    exit
  }
')

today=$(date '+%Y-%m-%d')

if [ -z "$next_event" ]; then
  emit_schedule_clear
  exit 0
fi

IFS=$'\t' read -r event_date event_time event_title event_url <<<"$next_event"

if [ "$event_date" != "$today" ]; then
  emit_schedule_clear
  exit 0
fi

pretty_time=$(date -d "today $event_time" '+%-I:%M%P' 2>/dev/null || printf '%s' "$event_time")

display=$(printf '%s %s' "$pretty_time" "$event_title" | tr -s ' ' | sed 's/^ //')
if [ ${#display} -gt "$max_display_chars" ]; then
  display="${display:0:$((max_display_chars - 3))}..."
fi

event_epoch=$(date -d "$event_date $event_time" '+%s' 2>/dev/null || printf '0')
now_epoch=$(date '+%s')
starts_in_min=0
case "$event_epoch" in
  ''|*[!0-9]*) event_epoch=0 ;;
esac

if [ "$event_epoch" -gt "$now_epoch" ]; then
  starts_in_min=$(( (event_epoch - now_epoch + 59) / 60 ))
fi

if [ "$event_epoch" -gt 0 ] && [ "$event_epoch" -le "$now_epoch" ]; then
  started_ago_min=$(( (now_epoch - event_epoch + 59) / 60 ))
  if [ "$started_ago_min" -lt 1 ]; then started_ago_min=1; fi
  tooltip=$(printf '⚠️ Started %dm ago' "$started_ago_min")
else
  starts_in_hours=$((starts_in_min / 60))
  starts_in_remainder_min=$((starts_in_min % 60))
  if [ "$starts_in_hours" -gt 0 ] && [ "$starts_in_remainder_min" -gt 0 ]; then
    tooltip=$(printf 'Starts in %dh %dm' "$starts_in_hours" "$starts_in_remainder_min")
  elif [ "$starts_in_hours" -gt 0 ]; then
    tooltip=$(printf 'Starts in %dh' "$starts_in_hours")
  else
    tooltip=$(printf 'Starts in %dm' "$starts_in_remainder_min")
  fi
fi

escaped_text=$(json_escape "${display}")
escaped_tooltip=$(json_escape "${tooltip}")
escaped_url=$(json_escape "${event_url}")

printf '{"text":"%s","tooltip":"%s","url":"%s","hasMeeting":true}\n' "$escaped_text" "$escaped_tooltip" "$escaped_url"
