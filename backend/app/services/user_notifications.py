"""Create per-user notifications in MongoDB and optionally send FCM."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from pymongo.database import Database

from app.db.mongo import next_sequence
from app.services.notification_service import send_push as send_fcm_push

NOTIFICATION_TYPES = frozenset({"academic", "event", "club", "dashboard", "system"})


def normalize_priority(raw: str | None) -> str:
    """Map legacy and UI values to low | normal | high."""
    p = (raw or "normal").lower()
    if p in ("high", "urgent"):
        return "high"
    if p == "low":
        return "low"
    return "normal"


def default_notification_type_from_kind(kind: str | None) -> str:
    k = (kind or "update").lower()
    if k == "community_reply":
        return "club"
    if k == "update":
        return "dashboard"
    return "system"


def prepare_notification_document(doc: dict[str, Any]) -> dict[str, Any]:
    """Fill defaults for API responses / validation from legacy Mongo docs."""
    out = dict(doc)
    if not out.get("notification_type"):
        out["notification_type"] = default_notification_type_from_kind(out.get("kind"))
    out["priority"] = normalize_priority(str(out.get("priority", "normal")))
    return out


def create_user_notification(
    db: Database,
    user_id: int,
    title: str,
    message: str,
    notification_type: str,
    priority: str,
    *,
    route: str | None = "/notifications",
    source_role: str = "system",
    kind: str | None = None,
    send_push: bool = True,
) -> int:
    """
    Insert one notification row and optionally push to the user's devices.

    Student feed still filters on ``kind == "update"`` for compatibility; callers
    should leave ``kind`` as default ``"update"`` for student-visible items.
    """
    nt = (notification_type or "dashboard").lower()
    if nt not in NOTIFICATION_TYPES:
        nt = "system"
    pr = normalize_priority(priority)
    kind_val = kind if kind is not None else "update"
    nid = next_sequence(db, "notifications")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": nid,
        "id": nid,
        "user_id": user_id,
        "title": title,
        "body": message,
        "priority": pr,
        "kind": kind_val,
        "notification_type": nt,
        "source_role": source_role,
        "is_read": False,
        "route": route or "/notifications",
        "created_at": now,
    }
    db.notifications.insert_one(doc)
    if send_push:
        tokens = [t["token"] for t in db.device_tokens.find({"user_id": user_id}, {"token": 1})]
        send_fcm_push(tokens, title, message, pr, doc["route"], notification_type=nt)
    return int(nid)
