from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel


class PollOptionCreate(BaseModel):
    label: str = Field(..., min_length=1, max_length=160)


class PollCreate(BaseModel):
    question: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    is_active: bool = True
    options: list[PollOptionCreate] = Field(..., min_length=2)


class PollUpdate(BaseModel):
    question: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    is_active: bool = True
    options: list[PollOptionCreate] = Field(..., min_length=2)


class PollVotePayload(BaseModel):
    option_id: int


class PollOptionResponse(ORMModel):
    id: int
    label: str
    votes_count: int


class PollResponse(ORMModel):
    id: int
    question: str
    description: str | None
    is_active: bool
    created_by: int
    created_at: datetime
    my_vote_option_id: int | None = None
    options: list[PollOptionResponse]
