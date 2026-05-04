from datetime import datetime
from typing import Any

from pydantic import BaseModel, computed_field, model_validator

from app.schemas.common import ORMModel


class NotificationCreate(BaseModel):
    title: str
    body: str
    priority: str = "normal"
    kind: str = "update"
    source_role: str = "system"
    route: str | None = None
    user_id: int
    notification_type: str = "dashboard"


class NotificationCreatePayload(BaseModel):
    """Alias for POST /notifications/create (same fields as NotificationCreate)."""

    title: str
    body: str
    priority: str = "normal"
    notification_type: str = "dashboard"
    kind: str = "update"
    source_role: str = "system"
    route: str | None = None
    user_id: int


class NotificationBroadcastToStudents(BaseModel):
    title: str
    body: str
    priority: str = "normal"
    audience: str = "students"
    route: str | None = "/dashboard"


class NotificationResponse(ORMModel):
    id: int
    title: str
    body: str
    priority: str
    kind: str
    source_role: str
    is_read: bool
    route: str | None
    user_id: int
    created_at: datetime
    notification_type: str = "dashboard"

    @model_validator(mode="before")
    @classmethod
    def legacy_defaults(cls, data: Any) -> Any:
        if isinstance(data, dict):
            from app.services.user_notifications import default_notification_type_from_kind, normalize_priority

            if not data.get("notification_type"):
                data["notification_type"] = default_notification_type_from_kind(data.get("kind"))
            data["priority"] = normalize_priority(str(data.get("priority", "normal")))
        return data

    @computed_field
    @property
    def message(self) -> str:
        return self.body
