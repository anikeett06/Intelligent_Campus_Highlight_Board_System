"""User IDs to notify for a club/community (members + followers)."""

from pymongo.database import Database


def notification_recipient_user_ids(db: Database, community_id: int) -> list[int]:
    members = [m["user_id"] for m in db.community_members.find({"community_id": community_id}, {"user_id": 1})]
    followers = [f["user_id"] for f in db.community_follows.find({"community_id": community_id}, {"user_id": 1})]
    return list(set(members + followers))
