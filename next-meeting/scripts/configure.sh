#!/usr/bin/env bash

set -euo pipefail

config_file="${OMARCHY_SHELL_CONFIG:-$HOME/.config/omarchy/shell.json}"

if ! command -v jq >/dev/null 2>&1; then
  printf 'NextMeeting configuration requires jq.\n' >&2
  exit 1
fi

if [ ! -f "$config_file" ]; then
  printf 'Config file not found: %s\n' "$config_file" >&2
  exit 1
fi

current_value() {
  local key="$1" fallback="$2"
  jq -r --arg key "$key" --arg fallback "$fallback" '
    def nextmeeting:
      (.bar.layout.left // []), (.bar.layout.center // []), (.bar.layout.right // [])
      | .[]
      | select(.id == "next-meeting");
    (first(nextmeeting | .[$key]) // $fallback)
  ' "$config_file"
}

prompt_value() {
  local label="$1" current="$2"
  if [ "${NEXT_MEETING_NO_GUM:-}" != "1" ] && command -v gum >/dev/null 2>&1; then
    gum input --prompt "$label: " --value "$current"
  else
    local value
    printf '%s [%s]: ' "$label" "$current" >&2
    IFS= read -r value
    printf '%s\n' "${value:-$current}"
  fi
}

validate_integer() {
  local label="$1" value="$2" min="$3" max="$4"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf '%s must be a number.\n' "$label" >&2
    exit 1
  fi
  if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
    printf '%s must be between %s and %s.\n' "$label" "$min" "$max" >&2
    exit 1
  fi
}

refresh_interval=$(prompt_value "Auto-fetch interval in seconds" "$(current_value refreshIntervalSec 1800)")
schedule_clear_text=$(prompt_value "Schedule clear text" "$(current_value scheduleClearText 'No more meetings today ✅')")
lookahead_days=$(prompt_value "Lookahead window in days" "$(current_value lookaheadDays 7)")
max_display_chars=$(prompt_value "Maximum display characters" "$(current_value maxDisplayChars 42)")
meet_open_mode=$(prompt_value "Meet open mode (chrome-app, system-browser, custom-command)" "$(current_value meetOpenMode chrome-app)")
meet_open_command=$(prompt_value "Custom open command" "$(current_value meetOpenCommand '')")

validate_integer "Auto-fetch interval" "$refresh_interval" 60 86400
validate_integer "Lookahead window" "$lookahead_days" 1 30
validate_integer "Maximum display characters" "$max_display_chars" 12 120
case "$meet_open_mode" in
  chrome-app|system-browser|custom-command) ;;
  *)
    printf 'Meet open mode must be chrome-app, system-browser, or custom-command.\n' >&2
    exit 1
    ;;
esac

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

jq \
  --argjson refreshIntervalSec "$refresh_interval" \
  --arg scheduleClearText "$schedule_clear_text" \
  --argjson lookaheadDays "$lookahead_days" \
  --argjson maxDisplayChars "$max_display_chars" \
  --arg meetOpenMode "$meet_open_mode" \
  --arg meetOpenCommand "$meet_open_command" '
    def settings:
      .refreshIntervalSec = $refreshIntervalSec
      | .scheduleClearText = $scheduleClearText
      | .lookaheadDays = $lookaheadDays
      | .maxDisplayChars = $maxDisplayChars
      | .meetOpenMode = $meetOpenMode
      | .meetOpenCommand = $meetOpenCommand;

    def update_section(section):
      .bar.layout[section] = ((.bar.layout[section] // []) | map(if .id == "next-meeting" then (. | settings) else . end));

    .bar.layout.left = (.bar.layout.left // [])
    | .bar.layout.center = (.bar.layout.center // [])
    | .bar.layout.right = (.bar.layout.right // [])
    | if ([.bar.layout.left[], .bar.layout.center[], .bar.layout.right[]] | any(.id == "next-meeting")) then
        update_section("left") | update_section("center") | update_section("right")
      else
        .bar.layout.right += [{ id: "next-meeting" } | settings]
      end
  ' "$config_file" > "$tmp"

cp "$config_file" "$config_file.bak.$(date +%s)"
mv "$tmp" "$config_file"

printf 'NextMeeting settings updated in %s\n' "$config_file"
printf 'The Omarchy shell should hot-reload automatically.\n'
