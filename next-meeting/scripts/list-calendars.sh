#!/usr/bin/env bash

# Emit a JSON array of the user's gcalcli calendars, one option per unique
# title, with the access level as a description. Consumed by the
# `multiselect` field type in the bar settings panel.
#
# gcalcli is a Python tool, so python3 is always available wherever this
# plugin can do anything useful. We let Python handle JSON encoding so
# calendar names containing quotes, backslashes, or other awkward
# characters survive intact.

set -u

if ! command -v gcalcli >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

# gcalcli sometimes ignores --nocolor when stdout isn't a terminal, so we
# strip ANSI escapes defensively before parsing.
gcalcli list --nocolor 2>/dev/null \
  | sed -E 's/\x1B\[[0-9;]*[mK]//g' \
  | python3 -c '
import json, sys

out = []
seen = set()
for i, line in enumerate(sys.stdin):
    if i < 2:
        continue  # skip "Access Title" header + dash separator
    line = line.rstrip("\n").lstrip()
    if not line:
        continue
    parts = line.split(None, 1)
    if len(parts) != 2:
        continue
    access, title = parts[0], parts[1].strip()
    if not title or title in seen:
        continue
    seen.add(title)
    out.append({"value": title, "label": title, "description": access})
json.dump(out, sys.stdout)
sys.stdout.write("\n")
'
