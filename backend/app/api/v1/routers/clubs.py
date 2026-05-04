from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.api.v1.routers.communities import _require_community_reader
from app.services.community_permissions import can_manage_community
from app.db.mongo import next_sequence
from app.db.mongo_docs import strip_mongo_id
from app.schemas.club_announcement import ClubAnnouncementResponse
from app.services.community_audience import notification_recipient_user_ids
from app.services.notify_insert import insert_notifications_for_users

router = APIRouter(prefix="/clubs", tags=["clubs"])
announcements_router = APIRouter(prefix="/announcements", tags=["announcements"])

UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
ALLOWED_IMAGE = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


async def _save_upload(upload: UploadFile, prefix: str) -> str:
    if not upload.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty filename")
    suffix = Path(upload.filename).suffix.lower()
    if suffix not in ALLOWED_IMAGE:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported image type")
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"{prefix}_{uuid4().hex}{suffix}"
    file_path = UPLOADS_DIR / filename
    file_path.write_bytes(await upload.read())
    return f"/uploads/{filename}"


def _coerce_announcement_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        dt = value
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    if isinstance(value, str):
        try:
            normalized = value.strip().replace("Z", "+00:00")
            parsed = datetime.fromisoformat(normalized)
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _announcement_doc_to_response(db: Database, doc: dict) -> ClubAnnouncementResponse:
    clean = strip_mongo_id(doc) or doc
    try:
        aid = int(clean.get("id", 0))
        club_id = int(clean.get("club_id", 0))
    except (TypeError, ValueError):
        aid, club_id = 0, 0
    title = str(clean.get("title") or "").strip() or "(untitled)"
    description = str(clean.get("description") or "").strip()
    try:
        created_by = int(clean.get("created_by", 0))
    except (TypeError, ValueError):
        created_by = 0
    creator = db.users.find_one({"id": created_by}) if created_by else None
    image_path = clean.get("image_path")
    created_at = _coerce_announcement_datetime(clean.get("created_at"))
    return ClubAnnouncementResponse(
        id=aid,
        club_id=club_id,
        title=title,
        description=description,
        image_url=str(image_path) if image_path else None,
        priority=str(clean.get("priority") or "normal"),
        created_at=created_at,
        created_by=created_by,
        creator_name=creator.get("full_name") if creator else None,
    )


def _push_club_announcement(
    db: Database,
    *,
    member_user_ids: list[int],
    title: str,
    body: str,
    priority: str,
    route: str,
) -> None:
    insert_notifications_for_users(
        db,
        member_user_ids,
        title=title,
        body=body,
        priority="urgent" if priority == "urgent" else "normal",
        kind="update",
        source_role="system",
        route=route,
        notification_type="club",
    )


def _load_announcement(db: Database, announcement_id: int) -> dict:
    doc = db.club_announcements.find_one({"id": announcement_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Announcement not found")
    return doc


@router.get("/{club_id}/announcements", response_model=list[ClubAnnouncementResponse])
def list_club_announcements(
    club_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[ClubAnnouncementResponse]:
    _require_community_reader(db, current_user, club_id)
    cursor = db.club_announcements.find({"club_id": club_id}).sort("created_at", -1)
    out: list[ClubAnnouncementResponse] = []
    for raw in cursor:
        try:
            out.append(_announcement_doc_to_response(db, raw))
        except Exception:
            # Skip rows that cannot be mapped (legacy / hand-edited Mongo docs)
            continue
    return out


@router.post("/{club_id}/announcements", response_model=ClubAnnouncementResponse)
async def create_club_announcement(
    club_id: int,
    title: str = Form(...),
    description: str = Form(...),
    priority: str = Form("normal"),
    image: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> ClubAnnouncementResponse:
    community = db.communities.find_one({"id": club_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Club not found")
    if not can_manage_community(db, current_user, club_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )
    _require_community_reader(db, current_user, club_id)
    pr = (priority or "normal").lower()
    if pr not in ("urgent", "normal"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="priority must be urgent or normal")

    image_path: str | None = None
    if image is not None and image.filename:
        image_path = await _save_upload(image, "club_announcement")

    aid = next_sequence(db, "club_announcements")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": aid,
        "id": aid,
        "club_id": club_id,
        "title": title.strip(),
        "description": description.strip(),
        "image_path": image_path,
        "priority": pr,
        "created_by": current_user.id,
        "created_at": now,
    }
    db.club_announcements.insert_one(doc)

    member_ids = notification_recipient_user_ids(db, club_id)
    route = f"/communities/{club_id}"
    _push_club_announcement(
        db,
        member_user_ids=member_ids,
        title=f"{community['name']}: {title.strip()}",
        body=description.strip()[:200],
        priority=pr,
        route=route,
    )
    return _announcement_doc_to_response(db, doc)


@announcements_router.put("/{announcement_id}", response_model=ClubAnnouncementResponse)
async def update_club_announcement(
    announcement_id: int,
    title: str | None = Form(None),
    description: str | None = Form(None),
    priority: str | None = Form(None),
    image: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> ClubAnnouncementResponse:
    existing = _load_announcement(db, announcement_id)
    club_id = int(existing["club_id"])
    if not can_manage_community(db, current_user, club_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )
    _require_community_reader(db, current_user, club_id)
    if (
        title is None
        and description is None
        and priority is None
        and (image is None or not image.filename)
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Nothing to update")

    updates: dict = dict(existing)
    if title is not None and title.strip():
        updates["title"] = title.strip()
    if description is not None and description.strip():
        updates["description"] = description.strip()
    if priority is not None:
        pr = priority.lower()
        if pr not in ("urgent", "normal"):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="priority must be urgent or normal")
        updates["priority"] = pr
    if image is not None and image.filename:
        if existing.get("image_path"):
            old = UPLOADS_DIR / Path(existing["image_path"]).name
            if old.exists():
                old.unlink()
        updates["image_path"] = await _save_upload(image, "club_announcement")

    db.club_announcements.replace_one({"id": announcement_id}, updates)
    refreshed = db.club_announcements.find_one({"id": announcement_id})
    community = db.communities.find_one({"id": club_id})
    if community:
        member_ids = notification_recipient_user_ids(db, club_id)
        route = f"/communities/{club_id}"
        pr = str(updates.get("priority") or "normal")
        t = str(updates.get("title") or existing.get("title") or "").strip()
        d = str(updates.get("description") or existing.get("description") or "").strip()
        _push_club_announcement(
            db,
            member_user_ids=member_ids,
            title=f"{community['name']}: announcement updated — {t}",
            body=d[:200] if d else "A club announcement was revised.",
            priority=pr,
            route=route,
        )
    return _announcement_doc_to_response(db, refreshed or updates)


@announcements_router.delete("/{announcement_id}")
def delete_club_announcement(
    announcement_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    existing = _load_announcement(db, announcement_id)
    club_id = int(existing["club_id"])
    if not can_manage_community(db, current_user, club_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )
    _require_community_reader(db, current_user, club_id)
    if existing.get("image_path"):
        old = UPLOADS_DIR / Path(existing["image_path"]).name
        if old.exists():
            old.unlink()
    community = db.communities.find_one({"id": club_id})
    if community:
        member_ids = notification_recipient_user_ids(db, club_id)
        t = str(existing.get("title") or "").strip() or "Announcement"
        _push_club_announcement(
            db,
            member_user_ids=member_ids,
            title=f"{community['name']}: announcement removed",
            body=f"This notice was withdrawn: {t}",
            priority="normal",
            route=f"/communities/{club_id}",
        )
    db.club_announcements.delete_one({"id": announcement_id})
    return {"message": "Announcement deleted"}
