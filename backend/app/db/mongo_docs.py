"""Helpers for Mongo documents used by API layers."""

from datetime import datetime
from typing import Any


def strip_mongo_id(doc: dict[str, Any] | None) -> dict[str, Any] | None:
    if doc is None:
        return None
    out = dict(doc)
    out.pop("_id", None)
    return out


def strip_mongo_ids(docs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [strip_mongo_id(d) or {} for d in docs]


def public_user_fields(doc: dict[str, Any] | None) -> dict[str, Any] | None:
    """Strip Mongo `_id`, password hash, and normalize ``birth_date`` for API / Pydantic."""
    out = strip_mongo_id(doc)
    if out is None:
        return None
    out.pop("hashed_password", None)
    bd = out.get("birth_date")
    if isinstance(bd, datetime):
        out["birth_date"] = bd.date()
    if "student_admin" not in out:
        out["student_admin"] = False
    if "academic_posting_allowed" not in out:
        out["academic_posting_allowed"] = out.get("role") == "admin"
    return out
