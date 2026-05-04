from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.db.mongo import next_sequence
from app.db.mongo_docs import strip_mongo_id
from app.services.campus_staff_permissions import assert_can_create_community
from app.services.community_permissions import can_manage_community, can_read_community_content
from app.schemas.community import (
    AddCommunityMemberBody,
    CommunityCreate,
    CommunityPostResponse,
    CommunityResponse,
)
from app.services.community_audience import notification_recipient_user_ids
from app.services.notification_audience import club_managers_for_follow_alerts, student_ids
from app.services.notify_insert import insert_notifications_for_users

router = APIRouter(prefix="/communities", tags=["communities"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
ALLOWED_IMAGE = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


def _poster_url_for_request(request: Request, poster_path: object) -> str | None:
    if poster_path is None:
        return None
    p = str(poster_path).strip()
    if not p:
        return None
    if p.startswith("http://") or p.startswith("https://"):
        return p
    base = str(request.base_url).rstrip("/")
    return f"{base}{p}" if p.startswith("/") else f"{base}/{p}"


def _community_response(request: Request, raw: dict) -> CommunityResponse:
    clean = strip_mongo_id(raw) or raw
    d = dict(clean)
    d["poster_url"] = _poster_url_for_request(request, d.get("poster_path"))
    return CommunityResponse.model_validate(d)


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


def _is_member(db: Database, user_id: int, community_id: int) -> bool:
    return db.community_members.find_one({"user_id": user_id, "community_id": community_id}) is not None


def _is_follower(db: Database, user_id: int, community_id: int) -> bool:
    return db.community_follows.find_one({"user_id": user_id, "community_id": community_id}) is not None


def _require_community_reader(db: Database, user: SimpleNamespace, community_id: int) -> dict:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if not can_read_community_content(db, user, community_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Follow or join this club to view updates")
    return community


def _require_community_member(db: Database, user: SimpleNamespace, community_id: int) -> dict:
    return _require_community_reader(db, user, community_id)


def _post_to_response(db: Database, post: dict) -> CommunityPostResponse:
    author = db.users.find_one({"id": post["author_id"]})
    author_name = author["full_name"] if author else None
    clean = strip_mongo_id(post) or post
    return CommunityPostResponse(
        id=clean["id"],
        title=clean["title"],
        content=clean["content"],
        community_id=clean["community_id"],
        author_id=clean["author_id"],
        author_name=author_name,
        image_path=clean.get("image_path"),
        created_at=clean["created_at"],
    )


@router.get("/", response_model=list[CommunityResponse])
def list_communities(request: Request, db: Database = Depends(get_db)) -> list[CommunityResponse]:
    cursor = db.communities.find({}).sort("created_at", -1)
    return [_community_response(request, c) for c in cursor]


@router.get("/mine", response_model=list[CommunityResponse])
def my_communities(
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[CommunityResponse]:
    mids = [m["community_id"] for m in db.community_members.find({"user_id": current_user.id})]
    if not mids:
        return []
    cursor = db.communities.find({"id": {"$in": mids}}).sort("created_at", -1)
    return [_community_response(request, c) for c in cursor]


@router.get("/moderating/mine", response_model=list[CommunityResponse])
def my_moderating_communities(
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[CommunityResponse]:
    """Clubs where this user is an appointed club manager (can post and edit that club)."""
    uid = int(current_user.id)
    cids = [
        int(m["community_id"])
        for m in db.community_members.find({"user_id": uid, "is_moderator": True}, {"community_id": 1})
    ]
    if not cids:
        return []
    cursor = db.communities.find({"id": {"$in": cids}}).sort("created_at", -1)
    return [_community_response(request, c) for c in cursor]


@router.get("/following/mine", response_model=list[CommunityResponse])
def my_followed_communities(
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[CommunityResponse]:
    """Clubs the current user follows (students)."""
    fids = [f["community_id"] for f in db.community_follows.find({"user_id": current_user.id})]
    if not fids:
        return []
    cursor = db.communities.find({"id": {"$in": fids}}).sort("created_at", -1)
    return [_community_response(request, c) for c in cursor]


def _require_student(current_user: SimpleNamespace) -> None:
    if getattr(current_user, "role", None) != "student":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only students can follow or unfollow clubs",
        )


@router.post("/{community_id}/follow", response_model=CommunityResponse)
def follow_community(
    community_id: int,
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityResponse:
    _require_student(current_user)
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if _is_follower(db, current_user.id, community_id):
        return _community_response(request, community)
    fid = next_sequence(db, "community_follows")
    now = datetime.now(timezone.utc)
    db.community_follows.insert_one(
        {
            "_id": fid,
            "id": fid,
            "community_id": community_id,
            "user_id": current_user.id,
            "followed_at": now,
        }
    )
    refreshed = db.communities.find_one({"id": community_id})
    mgrs = club_managers_for_follow_alerts(db, community_id)
    follower_name = getattr(current_user, "full_name", None) or "A student"
    n_follow = db.community_follows.count_documents({"community_id": community_id})
    insert_notifications_for_users(
        db,
        [m for m in mgrs if m != current_user.id],
        title=f"New follower — {community['name']}",
        body=f"{follower_name} started following this club. Total followers: {n_follow}.",
        priority="normal",
        kind="update",
        source_role="student",
        route=f"/communities/{community_id}",
        notification_type="club",
    )
    return _community_response(request, refreshed or community)


@router.delete("/{community_id}/follow", response_model=dict[str, str])
def unfollow_community(
    community_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    _require_student(current_user)
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    del_res = db.community_follows.delete_one({"community_id": community_id, "user_id": current_user.id})
    if del_res.deleted_count:
        mgrs = club_managers_for_follow_alerts(db, community_id)
        follower_name = getattr(current_user, "full_name", None) or "A student"
        n_follow = db.community_follows.count_documents({"community_id": community_id})
        insert_notifications_for_users(
            db,
            [m for m in mgrs if m != current_user.id],
            title=f"Follower left — {community['name']}",
            body=f"{follower_name} unfollowed this club. Total followers: {n_follow}.",
            priority="normal",
            kind="update",
            source_role="student",
            route=f"/communities/{community_id}",
            notification_type="club",
        )
    return {"message": "Unfollowed"}


@router.post("/", response_model=CommunityResponse)
def create_community(
    payload: CommunityCreate,
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityResponse:
    assert_can_create_community(current_user)
    if db.communities.find_one({"name": payload.name}):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Community already exists")
    cid = next_sequence(db, "communities")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": cid,
        "id": cid,
        "name": payload.name,
        "description": payload.description,
        "poster_path": None,
        "created_at": now,
    }
    db.communities.insert_one(doc)
    # Student campus lead who creates a club becomes its first club manager.
    if getattr(current_user, "role", None) == "student" and getattr(current_user, "student_admin", False):
        mid = next_sequence(db, "community_members")
        db.community_members.insert_one(
            {
                "_id": mid,
                "id": mid,
                "community_id": cid,
                "user_id": current_user.id,
                "joined_at": now,
                "is_moderator": True,
            }
        )
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=f"New club/community: {payload.name}",
        body=payload.description or "A new community is now available.",
        priority="normal",
        kind="update",
        source_role=current_user.role,
        route="/dashboard",
        notification_type="club",
    )
    return _community_response(request, doc)


@router.post("/{community_id}/join", response_model=CommunityResponse)
def join_community(
    community_id: int,
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityResponse:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if _is_member(db, current_user.id, community_id):
        return _community_response(request, community)
    mid = next_sequence(db, "community_members")
    now = datetime.now(timezone.utc)
    db.community_members.insert_one(
        {
            "_id": mid,
            "id": mid,
            "community_id": community_id,
            "user_id": current_user.id,
            "joined_at": now,
            "is_moderator": False,
        }
    )
    refreshed = db.communities.find_one({"id": community_id})
    return _community_response(request, refreshed)


@router.put("/{community_id}/admin", response_model=CommunityResponse)
async def update_community_admin(
    community_id: int,
    request: Request,
    name: str | None = Form(None),
    description: str | None = Form(None),
    poster: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityResponse:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if not can_manage_community(db, current_user, community_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )

    updates = dict(community)
    if name is not None and name.strip():
        taken = db.communities.find_one({"name": name.strip(), "id": {"$ne": community_id}})
        if taken:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Name already in use")
        updates["name"] = name.strip()
    if description is not None:
        updates["description"] = description or None
    if poster is not None and poster.filename:
        if community.get("poster_path"):
            old = UPLOADS_DIR / Path(community["poster_path"]).name
            if old.exists():
                old.unlink()
        updates["poster_path"] = await _save_upload(poster, "community_poster")

    db.communities.replace_one({"id": community_id}, updates)
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=f"Community updated: {updates['name']}",
        body=updates.get("description") or f"Community details were updated ({current_user.role}).",
        priority="normal",
        kind="update",
        source_role=current_user.role,
        route=f"/communities/{community_id}",
        notification_type="club",
    )
    final = db.communities.find_one({"id": community_id})
    return _community_response(request, final)


@router.delete("/{community_id}/admin")
def delete_community_admin(
    community_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if not can_manage_community(db, current_user, community_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )

    for ann in db.club_announcements.find({"club_id": community_id}):
        if ann.get("image_path"):
            old = UPLOADS_DIR / Path(ann["image_path"]).name
            if old.exists():
                old.unlink()
    db.club_announcements.delete_many({"club_id": community_id})

    for post in db.community_posts.find({"community_id": community_id}):
        if post.get("image_path"):
            old = UPLOADS_DIR / Path(post["image_path"]).name
            if old.exists():
                old.unlink()
    db.community_posts.delete_many({"community_id": community_id})

    db.community_members.delete_many({"community_id": community_id})
    db.community_follows.delete_many({"community_id": community_id})

    if community.get("poster_path"):
        old = UPLOADS_DIR / Path(community["poster_path"]).name
        if old.exists():
            old.unlink()

    db.communities.delete_one({"id": community_id})
    return {"message": "Community deleted"}


@router.post("/{community_id}/members", response_model=CommunityResponse)
def add_community_member(
    community_id: int,
    payload: AddCommunityMemberBody,
    request: Request,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityResponse:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if not can_manage_community(db, current_user, community_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )
    if not db.users.find_one({"id": payload.user_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if not _is_member(db, payload.user_id, community_id):
        mid = next_sequence(db, "community_members")
        now = datetime.now(timezone.utc)
        db.community_members.insert_one(
            {
                "_id": mid,
                "id": mid,
                "community_id": community_id,
                "user_id": payload.user_id,
                "joined_at": now,
                "is_moderator": False,
            }
        )
    refreshed = db.communities.find_one({"id": community_id})
    return _community_response(request, refreshed)


@router.get("/{community_id}/posts", response_model=list[CommunityPostResponse])
def list_community_posts(
    community_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[CommunityPostResponse]:
    _require_community_reader(db, current_user, community_id)
    posts = list(db.community_posts.find({"community_id": community_id}).sort("created_at", -1))
    return [_post_to_response(db, p) for p in posts]


@router.post("/{community_id}/posts", response_model=CommunityPostResponse)
async def create_community_post(
    community_id: int,
    title: str = Form(...),
    content: str = Form(...),
    image: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> CommunityPostResponse:
    community = db.communities.find_one({"id": community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")
    if not can_manage_community(db, current_user, community_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Club manager or campus admin access required",
        )
    _require_community_reader(db, current_user, community_id)
    image_path: str | None = None
    if image is not None and image.filename:
        image_path = await _save_upload(image, "community_post")
    pid = next_sequence(db, "community_posts")
    now = datetime.now(timezone.utc)
    post_doc = {
        "_id": pid,
        "id": pid,
        "title": title,
        "content": content,
        "community_id": community_id,
        "author_id": current_user.id,
        "image_path": image_path,
        "created_at": now,
    }
    db.community_posts.insert_one(post_doc)
    member_ids = notification_recipient_user_ids(db, community_id)
    insert_notifications_for_users(
        db,
        member_ids,
        title=f"{community['name']}: {title}",
        body=content,
        priority="normal",
        kind="update",
        source_role=str(current_user.role),
        route=f"/communities/{community_id}",
        notification_type="club",
    )
    return _post_to_response(db, post_doc)
