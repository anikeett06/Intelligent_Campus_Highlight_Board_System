"""Who may use staff-only campus tools (events, polls, registrations, broadcasts)."""

from types import SimpleNamespace

from fastapi import HTTPException, status
from pymongo.database import Database


def _role(user: SimpleNamespace) -> str:
    return str(getattr(user, "role", "") or "")


def academic_posting_allowed(user: SimpleNamespace) -> bool:
    """Faculty may edit the academic board only when campus admin enables this flag."""
    if _role(user) == "admin":
        return True
    return bool(getattr(user, "academic_posting_allowed", False))


def is_student_campus_lead(user: SimpleNamespace) -> bool:
    """Student appointed to help run non-academic campus content (never the academic board)."""
    return _role(user) == "student" and bool(getattr(user, "student_admin", False))


def can_manage_academic_shortcuts(user: SimpleNamespace) -> bool:
    """Academic dashboard file slots — admin or granted faculty only."""
    r = _role(user)
    if r == "admin":
        return True
    return r == "faculty" and academic_posting_allowed(user)


def can_create_community(user: SimpleNamespace) -> bool:
    """New clubs live on the non-academic side — campus admin or appointed student leads."""
    r = _role(user)
    if r == "admin":
        return True
    return is_student_campus_lead(user)


def can_staff_campus_dashboard_tools(user: SimpleNamespace) -> bool:
    """Polls, event admin forms, registration exports, targeted notifications."""
    r = _role(user)
    if r == "admin":
        return True
    if r == "faculty" and academic_posting_allowed(user):
        return True
    if is_student_campus_lead(user):
        return True
    return False


def _event_segment(ev: dict | None) -> str:
    if not ev:
        return "non_academic"
    s = (ev.get("dashboard_segment") or "non_academic").strip().lower()
    return s if s in ("academic", "non_academic") else "non_academic"


def can_view_event_registrations(db: Database, user: SimpleNamespace, event_id: int) -> bool:
    ev = db.events.find_one({"id": event_id})
    if not ev:
        return False
    seg = _event_segment(ev)
    r = _role(user)
    if r == "admin":
        return True
    if r == "faculty" and academic_posting_allowed(user):
        return seg == "academic"
    if is_student_campus_lead(user):
        return seg == "non_academic"
    return False


def assert_staff_dashboard_tools(user: SimpleNamespace) -> None:
    if not can_staff_campus_dashboard_tools(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Campus administrator has not enabled posting tools for your account, or student lead access is required.",
        )


def assert_academic_shortcuts(user: SimpleNamespace) -> None:
    if not can_manage_academic_shortcuts(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only campus administrators or faculty with academic posting enabled may change these files.",
        )


def assert_can_create_community(user: SimpleNamespace) -> None:
    if not can_create_community(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only campus administrators or appointed student campus leads may create clubs.",
        )
