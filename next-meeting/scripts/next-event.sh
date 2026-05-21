#!/usr/bin/env bash

set -u

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

emit_off() {
  printf '{"text":"","class":"off"}\n'
}

schedule_clear_text=${1-"No more meetings today ✅"}
lookahead_days=${2-7}
max_display_chars=${3-42}

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

agenda=$(gcalcli agenda "$start_time" "$end_time" --nodeclined --tsv --details title --details conference --details url 2>/dev/null || true)

if [ -z "$agenda" ]; then
  emit_schedule_clear
  exit 0
fi

next_event=$(printf '%s\n' "$agenda" | awk -F '\t' -v cutoff="$start_time" '
  NR == 1 { next }
  {
    event_date = $1
    start = $2
    hangout_link = $6
    conference_uri = $8
    title = $9
    if (start == "") next
    if ((event_date " " start) < cutoff) next
    if (conference_uri !~ /^https:\/\/meet\.google\.com\// && hangout_link !~ /^https:\/\/meet\.google\.com\//) next
    gsub(/\t/, " ", title)
    if (title == "") title = "(Untitled)"

    slot = event_date "\t" start
    if (!(slot in seen)) {
      seen[slot] = 1
      order[++count] = slot
    }

    event_count[slot]++
    if (titles[slot] == "") titles[slot] = title
    else titles[slot] = titles[slot] "\034" title
  }
  END {
    for (i = 1; i <= count; i++) {
      slot = order[i]
      print slot "\t" event_count[slot] "\t" titles[slot]
      exit
    }
  }
')

today=$(date '+%Y-%m-%d')

if [ -z "$next_event" ]; then
  emit_schedule_clear
  exit 0
fi

event_date=${next_event%%$'\t'*}
rest=${next_event#*$'\t'}
event_time=${rest%%$'\t'*}
rest=${rest#*$'\t'}
event_count=${rest%%$'\t'*}
event_titles=${rest#*$'\t'}

case "$event_count" in
  ''|*[!0-9]*) event_count=1 ;;
esac

if [ "$event_date" != "$today" ]; then
  emit_schedule_clear
  exit 0
fi

pretty_time=$(date -d "today $event_time" '+%-I:%M%P' 2>/dev/null || printf '%s' "$event_time")

if [ "$event_count" -ge 2 ]; then
  display=$(printf '⚠️ %d meetings at %s' "$event_count" "$pretty_time")
  state_class="conflict"
else
  event_title=${event_titles%%$'\034'*}
  display=$(printf '%s %s' "$pretty_time" "$event_title" | tr -s ' ' | sed 's/^ //')
  state_class="on"
fi
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
  time_tooltip=$(printf '⚠️ Started %dm ago' "$started_ago_min")
else
  starts_in_hours=$((starts_in_min / 60))
  starts_in_remainder_min=$((starts_in_min % 60))
  if [ "$starts_in_hours" -gt 0 ] && [ "$starts_in_remainder_min" -gt 0 ]; then
    time_tooltip=$(printf 'Starts in %dh %dm' "$starts_in_hours" "$starts_in_remainder_min")
  elif [ "$starts_in_hours" -gt 0 ]; then
    time_tooltip=$(printf 'Starts in %dh' "$starts_in_hours")
  else
    time_tooltip=$(printf 'Starts in %dm' "$starts_in_remainder_min")
  fi
fi

tooltip=$time_tooltip
if [ "$event_count" -ge 2 ]; then
  conflict_lines=$(printf '%s' "$event_titles" | tr '\034' '\n' | sed 's/^/• /' | awk '
    { lines[NR] = $0; if (length($0) > max) max = length($0) }
    END {
      for (i = 1; i <= NR; i++) {
        printf "%-" max "s", lines[i]
        if (i < NR) printf "\n"
      }
    }
  ')
  if [ -n "$conflict_lines" ]; then
    tooltip=$(printf '%s\n%s' "$time_tooltip" "$conflict_lines")
  fi
fi

escaped_text=$(json_escape "${display}")
escaped_tooltip=$(json_escape "${tooltip}")

printf '{"text":"%s","tooltip":"%s","class":"%s","hasMeeting":true}\n' "$escaped_text" "$escaped_tooltip" "$state_class"
