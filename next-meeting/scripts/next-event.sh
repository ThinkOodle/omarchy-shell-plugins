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
  printf '{"text":"","class":"off","events":[]}'"\n"
}

emit_schedule_clear() {
  local escaped_text
  escaped_text=$(json_escape "$schedule_clear_text")
  printf '{"text":"%s","tooltip":"%s","hasMeeting":false,"events":[]}'"\n" "$escaped_text" "$escaped_text"
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
parser="$script_dir/agenda-to-json.py"

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

if ! command -v gcalcli >/dev/null 2>&1; then
  emit_off
  exit 0
fi

if [ ! -x "$parser" ]; then
  emit_schedule_clear
  exit 0
fi

# Fetch from the start of today so the panel can render the whole day, but
# extend through the configured lookahead window so the bar can determine
# whether the next joinable meeting is still today.
start_time=$(date '+%Y-%m-%d 00:00')
end_time=$(date -d "+${lookahead_days} days" '+%Y-%m-%d 00:00')
today=$(date '+%Y-%m-%d')

calendar_args=()
for cal in "${calendars[@]}"; do
  [ -n "$cal" ] && calendar_args+=(--calendar "$cal")
done

agenda=$(gcalcli --nocolor "${calendar_args[@]}" agenda "$start_time" "$end_time" \
  --nodeclined \
  --tsv \
  --details title \
  --details conference \
  --details url \
  --details description \
  --details location \
  2>/dev/null || true)

if [ -z "$agenda" ]; then
  emit_schedule_clear
  exit 0
fi

NEXT_MEETING_TODAY="$today" printf '%s\n' "$agenda" \
  | NEXT_MEETING_TODAY="$today" python3 "$parser" "$schedule_clear_text" "$max_display_chars" \
  || emit_schedule_clear
