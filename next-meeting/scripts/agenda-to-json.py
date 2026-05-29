#!/usr/bin/env python3
"""Convert gcalcli agenda --tsv output into NextMeeting JSON.

The shell widget keeps its process wiring small by letting gcalcli do the
calendar fetch and this helper do the TSV/URL parsing.  It intentionally
pattern-matches common conference links in every text-ish column because Zoom
links are often stored in event descriptions instead of Google Calendar's
canonical conference fields.
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import sys
from datetime import datetime, timedelta
from typing import Any
from urllib.parse import urlparse

URL_RE = re.compile(r"https?://[^\s<>'\"\])}]+", re.IGNORECASE)
TRAILING_URL_CHARS = ".,;:!?)]}"

CONFERENCE_HOST_HINTS = (
    "meet.google.com",
    "zoom.us",
    "zoom.com",
    "zoomgov.com",
    "teams.microsoft.com",
    "teams.live.com",
    "webex.com",
    "whereby.com",
)


def parse_dt(date_str: str, time_str: str) -> datetime | None:
    if not date_str or not time_str:
        return None
    try:
        return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    except ValueError:
        return None


def fmt_time(time_str: str) -> str:
    if not time_str:
        return "All day"
    try:
        dt = datetime.strptime(time_str, "%H:%M")
    except ValueError:
        return time_str
    return dt.strftime("%-I:%M%p").lower()


def fmt_range(row: dict[str, str]) -> str:
    start = row.get("start_time", "")
    end = row.get("end_time", "")
    if not start:
        return "All day"
    if not end:
        return fmt_time(start)
    return f"{fmt_time(start)}–{fmt_time(end)}"


def provider_for_url(url: str) -> str:
    if not url:
        return ""
    try:
        parsed = urlparse(url)
    except Exception:
        return "video"
    host = (parsed.netloc or "").lower()
    path = (parsed.path or "").lower()

    if host == "meet.google.com" or host.endswith(".meet.google.com"):
        return "meet"
    if host.endswith("zoom.us") or host.endswith("zoom.com") or host.endswith("zoomgov.com"):
        # Normal join URLs are /j/<id>, /my/<name>, /w/<id>, or web-client /wc/...
        # but classify any Zoom host as joinable because invite URLs vary.
        return "zoom"
    if "teams.microsoft.com" in host or "teams.live.com" in host:
        return "teams"
    if host.endswith("webex.com") or ".webex.com" in host:
        return "webex"
    if host.endswith("whereby.com"):
        return "whereby"
    if any(hint in host for hint in CONFERENCE_HOST_HINTS):
        return "video"
    if "/j/" in path and "zoom" in host:
        return "zoom"
    return ""


def clean_url(raw: str) -> str:
    url = raw.strip().rstrip(TRAILING_URL_CHARS)
    # gcalcli/Calendar sometimes appends HTML-ish escapes in description text.
    return url.replace("&amp;", "&")


def iter_urls(text: str):
    for match in URL_RE.finditer(text or ""):
        yield clean_url(match.group(0))


def conference_url(row: dict[str, str]) -> tuple[str, str]:
    # Prefer canonical conference columns when gcalcli has them.
    for key in ("conference_uri", "hangout_link"):
        value = clean_url(row.get(key, ""))
        provider = provider_for_url(value)
        if provider:
            return value, provider

    # Zoom links are commonly in description/location rather than conference_uri.
    # Search every non-calendar-url text column so we catch those without turning
    # the Google Calendar event-detail page into a join button.
    for key, value in row.items():
        if key in ("html_link", "calendar_url", "event_url"):
            continue
        for url in iter_urls(value or ""):
            provider = provider_for_url(url)
            if provider:
                return url, provider
    return "", ""


def human_delta(target: datetime, now: datetime) -> str:
    seconds = int((target - now).total_seconds())
    if seconds <= 0:
        minutes = max(1, int((-seconds + 59) // 60))
        return f"Started {minutes}m ago"
    minutes = int((seconds + 59) // 60)
    hours, mins = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    if days and hours:
        return f"Starts in {days}d {hours}h"
    if days:
        return f"Starts in {days}d"
    if hours and mins:
        return f"Starts in {hours}h {mins}m"
    if hours:
        return f"Starts in {hours}h"
    return f"Starts in {mins}m"


def provider_label(provider: str) -> str:
    return {
        "meet": "Google Meet",
        "zoom": "Zoom",
        "teams": "Teams",
        "webex": "Webex",
        "whereby": "Whereby",
        "video": "Video meeting",
    }.get(provider, "Meeting")


def fmt_date_label(date_str: str) -> str:
    try:
        return datetime.strptime(date_str, "%Y-%m-%d").strftime("%A, %B %-d")
    except ValueError:
        return date_str


def event_sort_key(event: dict[str, Any]) -> tuple[str, int, str, str]:
    # Date first, then all-day, then timed events.
    start = event.get("startTime") or ""
    return (event.get("date", ""), 0 if event.get("allDay") else 1, start, event.get("title", ""))


def display_text_for(event: dict[str, Any], max_chars: int) -> str:
    display = f"{event.get('timeLabel', '')} {event.get('title', '')}".strip()
    if len(display) > max_chars:
        display = display[: max(0, max_chars - 3)] + "..."
    return display


def main() -> int:
    schedule_clear_text = sys.argv[1] if len(sys.argv) > 1 else "No more meetings today ✅"
    try:
        max_display_chars = int(sys.argv[2]) if len(sys.argv) > 2 else 42
    except ValueError:
        max_display_chars = 42
    max_display_chars = max(12, min(max_display_chars, 120))

    today = os.environ.get("NEXT_MEETING_TODAY") or datetime.now().strftime("%Y-%m-%d")
    now = datetime.now()
    raw = sys.stdin.read()

    events: list[dict[str, Any]] = []
    reader = csv.DictReader(io.StringIO(raw), delimiter="\t")
    for row in reader:
        start_date = (row.get("start_date") or "").strip()
        if not start_date:
            continue

        title = (row.get("title") or "").strip()
        # gcalcli can emit all-day calendar/category placeholders.
        if title == "Home" and not (row.get("start_time") or "").strip():
            continue

        start_time = (row.get("start_time") or "").strip()
        end_date = (row.get("end_date") or start_date).strip()
        end_time = (row.get("end_time") or "").strip()
        start_dt = parse_dt(start_date, start_time)
        end_dt = parse_dt(end_date, end_time)
        meeting_url, provider = conference_url(row)

        all_day = not start_time
        if end_dt is not None:
            past = end_dt < now
        elif start_dt is not None:
            past = start_dt < now - timedelta(minutes=5)
        else:
            past = False
        ongoing = bool(start_dt and end_dt and start_dt <= now <= end_dt)

        starts_text = ""
        if start_dt is not None and (ongoing or not past):
            starts_text = "In progress" if ongoing else human_delta(start_dt, now)

        events.append(
            {
                "date": start_date,
                "dateLabel": fmt_date_label(start_date),
                "startTime": start_time,
                "endDate": end_date,
                "endTime": end_time,
                "title": title or "(untitled)",
                "timeLabel": fmt_time(start_time),
                "timeRange": fmt_range(row),
                "url": meeting_url,
                "provider": provider,
                "providerLabel": provider_label(provider) if provider else "",
                "hasMeeting": bool(meeting_url),
                "allDay": all_day,
                "past": past,
                "ongoing": ongoing,
                "startsText": starts_text,
            }
        )

    events.sort(key=event_sort_key)

    next_meeting = None
    for event in events:
        if event.get("date") == today and event.get("hasMeeting") and not event.get("past") and not event.get("allDay"):
            next_meeting = event
            break

    if next_meeting:
        tooltip = next_meeting.get("startsText") or "Join meeting"
        label = next_meeting.get("providerLabel") or "Meeting"
        if label:
            tooltip = f"{tooltip} · {label}"
        payload: dict[str, Any] = {
            "text": display_text_for(next_meeting, max_display_chars),
            "tooltip": tooltip,
            "url": next_meeting.get("url", ""),
            "provider": next_meeting.get("provider", ""),
            "hasMeeting": True,
            "class": "on",
            "events": events,
        }
    else:
        payload = {
            "text": schedule_clear_text,
            "tooltip": schedule_clear_text,
            "url": "",
            "provider": "",
            "hasMeeting": False,
            "class": "on" if schedule_clear_text else "off",
            "events": events,
        }

    payload["today"] = today
    payload["todayLabel"] = fmt_date_label(today)
    payload["generatedAt"] = now.isoformat(timespec="seconds")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
