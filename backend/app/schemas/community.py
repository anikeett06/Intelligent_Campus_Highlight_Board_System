from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel


class CommunityCreate(BaseModel):
    name: str
    description: str | None = None


class CommunityResponse(ORMModel):
    id: int
    name: str
    description: str | None
    poster_path: str | None = None
    # Absolute URL (same host the client used to reach the API). Prefer over joining poster_path on-device.
    poster_url: str | None = None
    created_at: datetime


class CommunityPostCreate(BaseModel):
    title: str
    content: str
    community_id: int


class CommunityPostResponse(ORMModel):
    id: int
    title: str
    content: str
    community_id: int
    author_id: int
    author_name: str | None = None
    image_path: str | None = None
    created_at: datetime


class CommunityPostReplyCreate(BaseModel):
    message: str = Field(..., min_length=1)


class CommunityPostReplyResponse(ORMModel):
    id: int
    post_id: int
    user_id: int
    author_name: str | None = None
    message: str
    created_at: datetime


class AddCommunityMemberBody(BaseModel):
    user_id: int


class ClubMembershipAdminRow(BaseModel):
    """Per-club row for admin profile: member of club and whether they may manage it."""

    community_id: int
    community_name: str
    is_moderator: bool


class ClubModeratorAssignment(BaseModel):
    community_id: int
    is_moderator: bool
