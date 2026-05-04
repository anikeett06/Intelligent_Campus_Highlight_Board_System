"""Resolve user id lists for broadcast-style notifications."""

from pymongo.database import Database

# Align with ``get_current_user`` (missing ``is_active`` defaults to active). Plain
# ``{"is_active": True}`` omits users who have no field set in older documents.
USER_IS_ACTIVE_QUERY = {"is_active": {"$ne": False}}


def student_ids(db: Database) -> list[int]:
    return [int(u["id"]) for u in db.users.find({"role": "student", **USER_IS_ACTIVE_QUERY}, {"id": 1})]


def admin_faculty_ids(db: Database) -> list[int]:
    return [
        int(u["id"])
        for u in db.users.find({"role": {"$in": ["admin", "faculty"]}, **USER_IS_ACTIVE_QUERY}, {"id": 1})
    ]


def academic_faculty_ids(db: Database) -> list[int]:
    """Faculty enabled for academic posting (admin event copy targets)."""
    return [
        int(u["id"])
        for u in db.users.find(
            {"role": "faculty", "academic_posting_allowed": True, **USER_IS_ACTIVE_QUERY},
            {"id": 1},
        )
    ]


def club_staff_user_ids(db: Database, community_id: int) -> list[int]:
    """Users who should receive follower alerts: appointed club managers and campus admins."""
    staff: list[int] = []
    for row in db.community_members.find({"community_id": community_id}, {"user_id": 1, "is_moderator": 1}):
        uid = int(row["user_id"])
        user = db.users.find_one({"id": uid, **USER_IS_ACTIVE_QUERY})
        if not user:
            continue
        if row.get("is_moderator") or user.get("role") == "admin":
            staff.append(uid)
    return list(dict.fromkeys(staff))


def club_managers_for_follow_alerts(db: Database, community_id: int) -> list[int]:
    """Club managers for this community, else campus admins (fallback)."""
    s = club_staff_user_ids(db, community_id)
    if s:
        return s
    return [int(u["id"]) for u in db.users.find({"role": "admin", **USER_IS_ACTIVE_QUERY}, {"id": 1})]
