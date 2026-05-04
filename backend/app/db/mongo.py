"""MongoDB Atlas / MongoDB connection and sequence helpers."""

from collections.abc import Generator

import certifi
from pymongo import ASCENDING, MongoClient, ReturnDocument
from pymongo.database import Database

from app.core.config import Settings, get_settings

_client: MongoClient | None = None


def _mongo_client_kwargs(settings: Settings) -> dict:
    """TLS options; see README for Python 3.13 + Atlas issues on Windows."""
    kwargs: dict = {"serverSelectionTimeoutMS": 30_000}
    uri = settings.mongodb_uri.strip()
    uses_tls = uri.startswith("mongodb+srv://") or "tls=true" in uri.lower()
    if settings.mongodb_tls_insecure and uses_tls:
        # Dev only: cannot combine tlsDisableOCSPEndpointCheck with tlsAllowInvalid* in PyMongo URI handling.
        kwargs["tlsAllowInvalidCertificates"] = True
        kwargs["tlsAllowInvalidHostnames"] = True
    elif uses_tls:
        ca = settings.mongodb_tls_ca_file
        kwargs["tlsCAFile"] = ca if ca else certifi.where()
    return kwargs


def get_mongo_client() -> MongoClient:
    global _client
    if _client is None:
        settings = get_settings()
        _client = MongoClient(settings.mongodb_uri, **_mongo_client_kwargs(settings))
    return _client


def get_database() -> Database:
    return get_mongo_client()[get_settings().mongodb_db_name]


def get_db() -> Generator[Database, None, None]:
    yield get_database()


def close_mongo_client() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None


def next_sequence(db: Database, counter_key: str) -> int:
    doc = db.counters.find_one_and_update(
        {"_id": counter_key},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int(doc["seq"])


def ensure_indexes(db: Database) -> None:
    db.users.create_index([("email", ASCENDING)], unique=True)
    db.users.create_index([("id", ASCENDING)], unique=True)

    db.events.create_index([("id", ASCENDING)], unique=True)

    db.registrations.create_index([("id", ASCENDING)], unique=True)
    db.registrations.create_index([("user_id", ASCENDING), ("event_id", ASCENDING)], unique=True)

    db.notifications.create_index([("id", ASCENDING)], unique=True)
    db.notifications.create_index([("user_id", ASCENDING), ("created_at", ASCENDING)])
    db.notifications.create_index([("user_id", ASCENDING), ("notification_type", ASCENDING)])

    db.communities.create_index([("id", ASCENDING)], unique=True)
    db.communities.create_index([("name", ASCENDING)], unique=True)

    db.community_members.create_index([("id", ASCENDING)], unique=True)
    db.community_members.create_index([("community_id", ASCENDING), ("user_id", ASCENDING)], unique=True)

    db.community_follows.create_index([("id", ASCENDING)], unique=True)
    db.community_follows.create_index([("community_id", ASCENDING), ("user_id", ASCENDING)], unique=True)

    db.community_posts.create_index([("id", ASCENDING)], unique=True)
    db.community_posts.create_index([("community_id", ASCENDING)])

    db.community_post_replies.create_index([("id", ASCENDING)], unique=True)
    db.community_post_replies.create_index([("post_id", ASCENDING)])

    db.club_announcements.create_index([("id", ASCENDING)], unique=True)
    db.club_announcements.create_index([("club_id", ASCENDING), ("created_at", ASCENDING)])

    db.lost_found.create_index([("id", ASCENDING)], unique=True)
    db.lost_found_comments.create_index([("id", ASCENDING)], unique=True)
    db.lost_found_comments.create_index([("item_id", ASCENDING)])

    db.device_tokens.create_index([("id", ASCENDING)], unique=True)
    db.device_tokens.create_index([("token", ASCENDING)], unique=True)

    db.polls.create_index([("id", ASCENDING)], unique=True)
    db.poll_options.create_index([("id", ASCENDING)], unique=True)
    db.poll_options.create_index([("poll_id", ASCENDING)])
    db.poll_votes.create_index([("id", ASCENDING)], unique=True)
    db.poll_votes.create_index([("poll_id", ASCENDING), ("user_id", ASCENDING)], unique=True)

    db.academic_notices.create_index([("id", ASCENDING)], unique=True)
    db.academic_notices.create_index([("created_at", ASCENDING)])

    # campus_shortcuts: singleton doc keyed by _id; no explicit _id index (MongoDB forbids unique on _id spec).
