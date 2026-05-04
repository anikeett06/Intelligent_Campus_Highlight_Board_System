from datetime import datetime

from app.schemas.common import ORMModel


class ClubAnnouncementResponse(ORMModel):
    id: int
    club_id: int
    title: str
    description: str
    image_url: str | None = None
    priority: str
    created_at: datetime
    created_by: int
    creator_name: str | None = None
