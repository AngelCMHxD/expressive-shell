#!/usr/bin/env python3
"""Fetch Google Calendar events via GNOME Online Accounts (GOA) OAuth2 tokens
and write a normalized JSON cache for Quickshell's CalendarShade."""

import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CACHE_PATH = Path.home() / ".cache" / "expressive-shell" / "calendar-events.json"


def api_get(url, token):
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=12) as resp:
        return json.loads(resp.read().decode("utf-8"))


def format_time(dt_str):
    try:
        dt = datetime.datetime.fromisoformat(dt_str.replace("Z", "+00:00")).astimezone()
        return dt.strftime("%Y-%m-%d"), dt.strftime("%H:%M")
    except Exception:
        return dt_str[:10], ""


def main():
    result = {
        "status": "no_accounts",
        "message": "",
        "accounts": [],
        "eventsByDate": {},
        "updatedAt": datetime.datetime.now().isoformat(timespec="seconds"),
    }

    try:
        import gi
        gi.require_version("Goa", "1.0")
        from gi.repository import Goa
    except Exception as e:
        result["status"] = "error"
        result["message"] = f"GOA unavailable: {e}"
        write_and_print(result)
        return

    try:
        client = Goa.Client.new_sync(None)
    except Exception as e:
        result["status"] = "error"
        result["message"] = f"GOA daemon error: {e}"
        write_and_print(result)
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    time_min = (now - datetime.timedelta(days=45)).isoformat().replace("+00:00", "Z")
    time_max = (now + datetime.timedelta(days=90)).isoformat().replace("+00:00", "Z")

    events_by_date = {}
    accounts = []
    errors = []

    for obj in client.get_accounts():
        acc = obj.get_account()
        if not acc or acc.props.provider_type != "google":
            continue
        cal_iface = obj.get_calendar()
        oauth2 = obj.get_oauth2_based()
        if not cal_iface or not oauth2:
            continue

        identity = acc.props.presentation_identity or acc.props.identity or "Google"
        accounts.append(identity)

        try:
            token, _expires = oauth2.call_get_access_token_sync(None)
        except Exception as e:
            errors.append(f"{identity}: token error ({e})")
            continue

        try:
            cal_list = api_get(
                "https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader",
                token,
            )
        except Exception as e:
            errors.append(f"{identity}: calendarList error ({e})")
            continue

        for cal in cal_list.get("items", []):
            if not cal.get("selected", True):
                continue
            cal_id = cal.get("id", "")
            if not cal_id:
                continue
            cal_name = cal.get("summaryOverride") or cal.get("summary") or "Calendar"
            cal_color = cal.get("backgroundColor") or "#4285F4"

            qs = urllib.parse.urlencode({
                "singleEvents": "true",
                "orderBy": "startTime",
                "timeMin": time_min,
                "timeMax": time_max,
                "maxResults": "250",
            })
            url = f"https://www.googleapis.com/calendar/v3/calendars/{urllib.parse.quote(cal_id, safe='')}/events?{qs}"
            try:
                ev_data = api_get(url, token)
            except Exception:
                continue

            for ev in ev_data.get("items", []):
                if ev.get("status") == "cancelled":
                    continue
                start = ev.get("start") or {}
                title = (ev.get("summary") or "(No title)").strip()
                location = (ev.get("location") or "").strip()

                if "date" in start:
                    day_key = start["date"][:10]
                    time_label = "All day"
                    all_day = True
                elif "dateTime" in start:
                    day_key, time_label = format_time(start["dateTime"])
                    all_day = False
                else:
                    continue

                events_by_date.setdefault(day_key, []).append({
                    "title": title,
                    "time": time_label,
                    "allDay": all_day,
                    "color": cal_color,
                    "calendar": cal_name,
                    "location": location,
                })

    for day_key, evs in events_by_date.items():
        evs.sort(key=lambda e: (0 if e["allDay"] else 1, e["time"], e["title"].lower()))

    result["accounts"] = accounts
    result["eventsByDate"] = events_by_date
    if accounts:
        result["status"] = "ok"
        if errors:
            result["message"] = "; ".join(errors)
    else:
        result["status"] = "no_accounts"
        result["message"] = "Sign into Google in Online Accounts to sync events"

    write_and_print(result)


def write_and_print(result):
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE_PATH.with_suffix(".json.tmp")
    payload = json.dumps(result, ensure_ascii=False)
    tmp.write_text(payload, encoding="utf-8")
    os.replace(tmp, CACHE_PATH)
    print(payload)


if __name__ == "__main__":
    main()
