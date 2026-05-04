from datetime import date
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import ORMModel


class UserSignup(BaseModel):
    full_name: str
    email: EmailStr
    password: str
    """Self-service campus signup: students and teaching staff. Admins are provisioned separately."""
    role: Literal["student", "faculty"] = "student"


class UserAdminUpdate(BaseModel):
    """Admin-only account governance."""

    full_name: str | None = None
    role: Literal["student", "faculty"] | None = None
    is_active: bool | None = None
    academic_posting_allowed: bool | None = Field(
        default=None,
        description="Faculty: when true, may post/edit academic dashboard activities (set by campus admin).",
    )
    student_admin: bool | None = Field(
        default=None,
        description="Student: when true, may post/edit non-academic campus content only (set by campus admin).",
    )


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(ORMModel):
    id: int
    full_name: str
    email: EmailStr
    role: str
    is_active: bool
    student_admin: bool = False
    academic_posting_allowed: bool = False
    profile_image_path: str | None = None
    bio: str | None = None
    birth_date: date | None = None
    phone: str | None = None
    college_name: str | None = None
