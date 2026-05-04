from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMModel


class LostFoundCreate(BaseModel):
    title: str
    description: str
    location: str | None = None


class LostFoundResponse(ORMModel):
    id: int
    title: str
    description: str
    location: str | None
    image_path: str | None
    is_found: bool
    author_id: int
    created_at: datetime


class LostFoundCommentCreate(BaseModel):
    finder_name: str
    contact: str | None = None
    message: str


class LostFoundCommentResponse(ORMModel):
    id: int
    item_id: int
    user_id: int
    finder_name: str
    contact: str | None
    message: str
    created_at: datetime
