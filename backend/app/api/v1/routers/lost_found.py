from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.db.mongo import next_sequence
from app.db.mongo_docs import strip_mongo_id
from app.schemas.lost_found import LostFoundCommentCreate, LostFoundCommentResponse, LostFoundResponse
from app.services.notification_audience import admin_faculty_ids, student_ids
from app.services.notify_insert import insert_notifications_for_users

LOST_FOUND_ROUTE = "/lost-found"

router = APIRouter(prefix="/lost-found", tags=["lost-found"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)


def _lost_found_broadcast_user_ids(db: Database) -> list[int]:
    return list(dict.fromkeys(student_ids(db) + admin_faculty_ids(db)))


def _can_moderate_or_own_lost_item(current_user: SimpleNamespace, item: dict) -> bool:
    """Admin and faculty may moderate any entry; others only their own posts."""
    if current_user.role in {"admin", "faculty"}:
        return True
    return item.get("author_id") == current_user.id


@router.get("/", response_model=list[LostFoundResponse])
def list_items(db: Database = Depends(get_db)) -> list[LostFoundResponse]:
    cursor = db.lost_found.find({}).sort("created_at", -1)
    return [LostFoundResponse.model_validate(strip_mongo_id(doc)) for doc in cursor]


@router.post("/", response_model=LostFoundResponse)
async def create_item(
    title: str = Form(...),
    description: str = Form(...),
    location: str | None = Form(None),
    image: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> LostFoundResponse:
    image_path: str | None = None
    if image is not None and image.filename:
        suffix = Path(image.filename).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported image type")
        filename = f"{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await image.read())
        image_path = f"/uploads/{filename}"

    iid = next_sequence(db, "lost_found")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": iid,
        "id": iid,
        "title": title,
        "description": description,
        "location": location,
        "image_path": image_path,
        "author_id": current_user.id,
        "is_found": False,
        "created_at": now,
    }
    db.lost_found.insert_one(doc)
    ttl = title if len(title) <= 80 else title[:77] + "..."
    insert_notifications_for_users(
        db,
        _lost_found_broadcast_user_ids(db),
        title=f"Lost & found: {ttl}",
        body=description if len(description) <= 200 else description[:197] + "...",
        priority="normal",
        kind="update",
        source_role=str(current_user.role),
        route=LOST_FOUND_ROUTE,
        notification_type="dashboard",
    )
    return LostFoundResponse.model_validate(strip_mongo_id(doc))


@router.patch("/{item_id}/status", response_model=LostFoundResponse)
def mark_found(
    item_id: int,
    is_found: bool,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> LostFoundResponse:
    item = db.lost_found.find_one({"id": item_id})
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    if not _can_moderate_or_own_lost_item(current_user, item):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")
    db.lost_found.update_one({"id": item_id}, {"$set": {"is_found": is_found}})
    updated = db.lost_found.find_one({"id": item_id})
    author_id = int(item.get("author_id", 0))
    if author_id and author_id != current_user.id:
        status_txt = "marked as found" if is_found else "marked as still open / not found"
        insert_notifications_for_users(
            db,
            [author_id],
            title=f"Lost & found update: {item.get('title', 'Your item')}",
            body=f"A moderator updated your entry — it was {status_txt}.",
            priority="normal",
            kind="update",
            source_role=str(current_user.role),
            route=LOST_FOUND_ROUTE,
            notification_type="dashboard",
        )
    return LostFoundResponse.model_validate(strip_mongo_id(updated))


@router.delete("/{item_id}")
def cancel_item_request(
    item_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    item = db.lost_found.find_one({"id": item_id})
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    if current_user.role != "admin" and item.get("author_id") != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if item.get("image_path"):
        img = UPLOADS_DIR / Path(item["image_path"]).name
        if img.exists():
            img.unlink()
    db.lost_found_comments.delete_many({"item_id": item_id})
    db.lost_found.delete_one({"id": item_id})
    author_id = int(item.get("author_id", 0))
    if current_user.role == "admin" and author_id and author_id != current_user.id:
        insert_notifications_for_users(
            db,
            [author_id],
            title="Lost & found post removed",
            body=f"An administrator removed your listing: {item.get('title', '')}.",
            priority="normal",
            kind="update",
            source_role="admin",
            route=LOST_FOUND_ROUTE,
            notification_type="dashboard",
        )
    return {"message": "Item request cancelled"}


@router.get("/{item_id}/comments", response_model=list[LostFoundCommentResponse])
def list_item_comments(
    item_id: int,
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(get_current_user),
) -> list[LostFoundCommentResponse]:
    if not db.lost_found.find_one({"id": item_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    cursor = db.lost_found_comments.find({"item_id": item_id}).sort("created_at", -1)
    return [LostFoundCommentResponse.model_validate(strip_mongo_id(c)) for c in cursor]


@router.post("/{item_id}/comments", response_model=LostFoundCommentResponse)
def add_item_comment(
    item_id: int,
    payload: LostFoundCommentCreate,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> LostFoundCommentResponse:
    if not db.lost_found.find_one({"id": item_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    cid = next_sequence(db, "lost_found_comments")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": cid,
        "id": cid,
        "item_id": item_id,
        "user_id": current_user.id,
        "finder_name": payload.finder_name,
        "contact": payload.contact,
        "message": payload.message,
        "created_at": now,
    }
    db.lost_found_comments.insert_one(doc)
    item_row = db.lost_found.find_one({"id": item_id}) or {}
    author_id = int(item_row.get("author_id", 0))
    targets: list[int] = []
    if author_id and author_id != current_user.id:
        targets.append(author_id)
    msg_preview = (payload.message or "").strip()
    if len(msg_preview) > 160:
        msg_preview = msg_preview[:157] + "..."
    if targets:
        who = getattr(current_user, "full_name", None) or "Someone"
        insert_notifications_for_users(
            db,
            targets,
            title=f"New comment on: {item_row.get('title', 'your item')}",
            body=f"{who}: {msg_preview or 'New message on your lost & found post.'}",
            priority="normal",
            kind="update",
            source_role=str(current_user.role),
            route=LOST_FOUND_ROUTE,
            notification_type="dashboard",
        )
    return LostFoundCommentResponse.model_validate(strip_mongo_id(doc))
