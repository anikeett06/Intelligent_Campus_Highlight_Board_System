from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi import APIRouter, Depends
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.db.mongo import next_sequence
from app.db.mongo_docs import strip_mongo_id
from app.schemas.device_token import DeviceTokenCreate, DeviceTokenResponse

router = APIRouter(prefix="/device-tokens", tags=["device-tokens"])


@router.post("/", response_model=DeviceTokenResponse)
def register_token(
    payload: DeviceTokenCreate,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> DeviceTokenResponse:
    existing = db.device_tokens.find_one({"token": payload.token})
    now = datetime.now(timezone.utc)
    if existing:
        db.device_tokens.update_one(
            {"_id": existing["_id"]},
            {"$set": {"user_id": current_user.id, "platform": payload.platform}},
        )
        updated = db.device_tokens.find_one({"token": payload.token})
        return DeviceTokenResponse.model_validate(strip_mongo_id(updated))

    tid = next_sequence(db, "device_tokens")
    doc = {
        "_id": tid,
        "id": tid,
        "token": payload.token,
        "platform": payload.platform,
        "user_id": current_user.id,
        "created_at": now,
    }
    db.device_tokens.insert_one(doc)
    return DeviceTokenResponse.model_validate(strip_mongo_id(doc))


@router.delete("/")
def remove_token(
    token: str,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    db.device_tokens.delete_many({"token": token, "user_id": current_user.id})
    return {"message": "Token removed"}
