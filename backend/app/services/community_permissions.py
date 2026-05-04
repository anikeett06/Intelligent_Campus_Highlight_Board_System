"""Who may read or manage a club/community (not global campus admin)."""

from types import SimpleNamespace

from pymongo.database import Database


def is_community_moderator(db: Database, user_id: int, community_id: int) -> bool:
    row = db.community_members.find_one({"user_id": int(user_id), "community_id": int(community_id)})
    return bool(row and row.get("is_moderator"))


def can_manage_community(db: Database, user: SimpleNamespace, community_id: int) -> bool:
    role = getattr(user, "role", None) or ""
    if role == "admin":
        return True
    uid = getattr(user, "id", None)
    if uid is None:
        return False
    return is_community_moderator(db, int(uid), int(community_id))


def can_read_community_content(db: Database, user: SimpleNamespace, community_id: int) -> bool:
    """View club posts/announcements: member, follower, club manager, or campus admin."""
    role = getattr(user, "role", None) or ""
    if role == "admin":
        return True
    uid = getattr(user, "id", None)
    if uid is None:
        return False
    uid_int = int(uid)
    if is_community_moderator(db, uid_int, community_id):
        return True
    if db.community_members.find_one({"user_id": uid_int, "community_id": int(community_id)}):
        return True
    if db.community_follows.find_one({"user_id": uid_int, "community_id": int(community_id)}):
        return True
    return False
