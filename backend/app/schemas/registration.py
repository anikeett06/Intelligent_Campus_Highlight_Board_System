from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.schemas.auth import UserResponse
from app.schemas.community import ClubMembershipAdminRow


class EventRegistrationPayload(BaseModel):
    participant_name: str
    roll_no: str
    branch: str
    college_name: str
    phone: str
    email: EmailStr


class MyRegistrationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    id: int
    event_id: int
    event_title: str
    participant_name: str | None
    roll_no: str | None
    branch: str | None
    college_name: str | None
    phone: str | None
    email: str | None
    registered_at: datetime


class EventRegistrationAdminRow(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    registration_id: int
    user_id: int
    full_name: str
    account_email: str
    profile_image_path: str | None
    participant_name: str | None
    roll_no: str | None
    branch: str | None
    college_name: str | None
    phone: str | None
    registration_email: str | None
    registered_at: datetime


class UserAdminDetailResponse(UserResponse):
    registrations: list[MyRegistrationResponse]
    club_memberships: list[ClubMembershipAdminRow] = Field(default_factory=list)
