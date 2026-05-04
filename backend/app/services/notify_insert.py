"""Insert in-app notifications into MongoDB (per-user + FCM via create_user_notification)."""

from pymongo.database import Database

from app.services.user_notifications import create_user_notification


def insert_notifications_for_users(
    db: Database,
    user_ids: list[int],
    *,
    title: str,
    body: str,
    priority: str = "normal",
    kind: str = "update",
    source_role: str = "system",
    route: str = "/notifications",
    notification_type: str = "dashboard",
    send_push: bool = True,
) -> None:
    for uid in set(user_ids):
        create_user_notification(
            db,
            uid,
            title,
            body,
            notification_type,
            priority,
            route=route,
            source_role=source_role,
            kind=kind,
            send_push=send_push,
        )
