"""Event bucketing for dashboard (timezone-safe vs stored datetimes)."""
from datetime import datetime, timedelta, timezone
from typing import Any


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def categorize_events(events: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Bucket events by urgency / timeline. ``events`` are plain dicts (e.g. from Mongo)."""
    now = datetime.now(timezone.utc)
    grouped: dict[str, list[dict[str, Any]]] = {"urgent": [], "ongoing": [], "upcoming": [], "academic": []}
    seen: dict[str, set[int]] = {key: set() for key in grouped}

    for event in events:
        eid = int(event["id"])
        start = _as_utc(event["start_time"])
        end = _as_utc(event["end_time"])
        grace_hours = max(0, int(event.get("auto_remove_after_hours") or 0))
        remove_at = end + timedelta(hours=grace_hours)
        if now > remove_at:
            continue

        priority = str(event.get("priority") or "").lower()
        category = str(event.get("category") or "").lower()

        def _add(bucket: str) -> None:
            if eid not in seen[bucket]:
                grouped[bucket].append(event)
                seen[bucket].add(eid)

        if priority == "urgent":
            _add("urgent")
        if priority == "academic" or category == "academic":
            _add("academic")
        if priority == "ongoing":
            _add("ongoing")
        elif priority == "upcoming":
            _add("upcoming")

        if start <= now <= end:
            _add("ongoing")
        elif start > now:
            _add("upcoming")

    return grouped
