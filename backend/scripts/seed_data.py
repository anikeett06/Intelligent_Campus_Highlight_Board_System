"""Seed MongoDB with demo users and sample content (idempotent)."""

from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.core.security import get_password_hash, verify_password
from app.db.mongo import ensure_indexes, get_database, next_sequence


def run() -> None:
    db = get_database()
    ensure_indexes(db)

    def ensure_user(*, full_name: str, email: str, role: str, password: str) -> dict:
        email = email.strip().lower()
        existing = db.users.find_one({"email": email})
        if existing:
            # Re-seed: reset demo password if this email was registered in-app with a different password or legacy hash.
            stored_hash = existing.get("hashed_password")
            need_update = True
            if isinstance(stored_hash, str) and stored_hash:
                try:
                    need_update = not verify_password(password, stored_hash)
                except (ValueError, TypeError):
                    need_update = True
            if need_update:
                db.users.update_one(
                    {"email": email},
                    {
                        "$set": {
                            "hashed_password": get_password_hash(password),
                            "full_name": full_name,
                            "role": role,
                            "student_admin": False,
                            "academic_posting_allowed": role in ("admin", "faculty"),
                        }
                    },
                )
                existing = db.users.find_one({"email": email}) or existing
            return existing
        uid = next_sequence(db, "users")
        now = datetime.now(timezone.utc)
        doc = {
            "_id": uid,
            "id": uid,
            "full_name": full_name,
            "email": email,
            "hashed_password": get_password_hash(password),
            "role": role,
            "is_active": True,
            "created_at": now,
            "profile_image_path": None,
            "bio": None,
            "birth_date": None,
            "phone": None,
            "college_name": None,
            "student_admin": False,
            "academic_posting_allowed": role in ("admin", "faculty"),
        }
        db.users.insert_one(doc)
        return doc

    admin = ensure_user(
        full_name="Campus Admin",
        email="admin@campus.edu",
        role="admin",
        password="Admin@123",
    )
    student = ensure_user(
        full_name="Student User",
        email="student@campus.edu",
        role="student",
        password="Student@123",
    )
    faculty = ensure_user(
        full_name="Faculty User",
        email="faculty@campus.edu",
        role="faculty",
        password="Faculty@123",
    )
    # Demo: faculty may use the academic board; students are not leads unless set in admin UI.
    db.users.update_one(
        {"id": faculty["id"]},
        {"$set": {"academic_posting_allowed": True, "student_admin": False}},
    )
    db.users.update_one(
        {"id": admin["id"]},
        {"$set": {"academic_posting_allowed": True, "student_admin": False}},
    )
    db.users.update_one(
        {"id": student["id"]},
        {"$set": {"academic_posting_allowed": False, "student_admin": False}},
    )

    now = datetime.now(timezone.utc)
    demo_events = [
        {
            "title": "Midterm Exam Schedule Released",
            "description": "Check timetable and seating plan.",
            "category": "academic",
            "priority": "urgent",
            "location": "Admin Block",
            "start_time": now - timedelta(hours=1),
            "end_time": now + timedelta(days=1),
            "created_by": admin["id"],
            "dashboard_segment": "academic",
        },
        {
            "title": "Hackathon Registration",
            "description": "24-hour coding event hosted by CSE Club.",
            "category": "club",
            "priority": "normal",
            "location": "Innovation Lab",
            "start_time": now + timedelta(days=2),
            "end_time": now + timedelta(days=3),
            "created_by": admin["id"],
            "dashboard_segment": "non_academic",
        },
    ]
    for ev in demo_events:
        if db.events.find_one({"title": ev["title"]}):
            continue
        eid = next_sequence(db, "events")
        db.events.insert_one(
            {
                "_id": eid,
                "id": eid,
                **ev,
                "poster_path": None,
                "exam_timetable_path": None,
                "auto_remove_after_hours": 0,
                "allow_registration": True,
            }
        )

    community = db.communities.find_one({"name": "Coding Club"})
    if not community:
        cid = next_sequence(db, "communities")
        community = {
            "_id": cid,
            "id": cid,
            "name": "Coding Club",
            "description": "All coding activities and peer sessions",
            "poster_path": None,
            "created_at": now,
        }
        db.communities.insert_one(community)

    # Faculty as appointed club manager for the demo club (per-club manager flag).
    if not db.community_members.find_one({"community_id": community["id"], "user_id": faculty["id"]}):
        mid = next_sequence(db, "community_members")
        db.community_members.insert_one(
            {
                "_id": mid,
                "id": mid,
                "community_id": community["id"],
                "user_id": faculty["id"],
                "joined_at": now,
                "is_moderator": True,
            }
        )
    else:
        db.community_members.update_one(
            {"community_id": community["id"], "user_id": faculty["id"]},
            {"$set": {"is_moderator": True}},
        )

    if not db.club_announcements.find_one({"title": "Weekly coding meetup"}):
        aid = next_sequence(db, "club_announcements")
        db.club_announcements.insert_one(
            {
                "_id": aid,
                "id": aid,
                "club_id": community["id"],
                "title": "Weekly coding meetup",
                "description": "Join us on Friday evening for the weekly challenge and peer help.",
                "image_path": None,
                "priority": "normal",
                "created_by": admin["id"],
                "created_at": now,
            }
        )

    if not db.lost_found.find_one({"title": "Lost Wallet"}):
        lid = next_sequence(db, "lost_found")
        db.lost_found.insert_one(
            {
                "_id": lid,
                "id": lid,
                "title": "Lost Wallet",
                "description": "Black wallet lost near cafeteria.",
                "location": "Cafeteria",
                "image_path": None,
                "author_id": student["id"],
                "is_found": False,
                "created_at": now,
            }
        )

    if not db.notifications.find_one({"title": "Welcome to Campus Board", "user_id": student["id"]}):
        nid = next_sequence(db, "notifications")
        db.notifications.insert_one(
            {
                "_id": nid,
                "id": nid,
                "title": "Welcome to Campus Board",
                "body": "You will now receive centralized campus updates here.",
                "priority": "normal",
                "kind": "update",
                "notification_type": "dashboard",
                "source_role": "system",
                "is_read": False,
                "route": "/dashboard",
                "user_id": student["id"],
                "created_at": now,
            }
        )

    print("")
    print("Seed data OK.")
    print("  Roles: student (app users), faculty (teaching staff + club leads), admin (campus IT).")
    print("  Club heads: use faculty@ or admin@ to manage clubs/announcements; students follow clubs for alerts.")
    print("  Demo logins:")
    print("    admin@campus.edu     / Admin@123")
    print("    faculty@campus.edu / Faculty@123   (seeded member of Coding Club)")
    print("    student@campus.edu / Student@123")
    print("")


if __name__ == "__main__":
    run()
