from pydantic import BaseModel

from app.schemas.common import ORMModel


class DeviceTokenCreate(BaseModel):
    token: str
    platform: str = "android"


class DeviceTokenResponse(ORMModel):
    id: int
    token: str
    platform: str
    user_id: int
