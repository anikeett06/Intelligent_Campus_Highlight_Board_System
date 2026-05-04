from pathlib import Path

from firebase_admin import credentials, initialize_app, messaging

from app.core.config import get_settings

_firebase_ready = False


def init_firebase() -> None:
    global _firebase_ready
    if _firebase_ready:
        return

    settings = get_settings()
    if not settings.firebase_credentials_path:
        return

    cred_path = Path(settings.firebase_credentials_path)
    if not cred_path.exists():
        return

    cred = credentials.Certificate(str(cred_path))
    initialize_app(cred)
    _firebase_ready = True


def send_push(
    tokens: list[str],
    title: str,
    body: str,
    priority: str,
    route: str,
    *,
    notification_type: str | None = None,
) -> None:
    if not _firebase_ready or not tokens:
        return

    data: dict[str, str] = {"priority": priority, "route": route}
    if notification_type:
        data["type"] = notification_type

    for token in tokens:
        msg = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data=data,
        )
        messaging.send(msg)
