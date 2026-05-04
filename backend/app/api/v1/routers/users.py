from datetime import date, datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db, require_admin
from app.services.campus_staff_permissions import can_staff_campus_dashboard_tools
from app.db.mongo import next_sequence
from app.db.mongo_docs import public_user_fields, strip_mongo_id
from app.schemas.auth import UserAdminUpdate, UserResponse
from app.schemas.community import ClubMembershipAdminRow, ClubModeratorAssignment
from app.schemas.registration import MyRegistrationResponse, UserAdminDetailResponse

router = APIRouter(prefix="/users", tags=["users"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
ALLOWED_IMAGE = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


def _parse_date(value: str | None) -> date | None:
    if value is None or not str(value).strip():
        return None
    s = str(value).strip()
    # Accept full ISO datetimes from clients (use date portion only).
    if len(s) >= 10 and s[4] == "-" and s[7] == "-":
        s = s[:10]
    try:
        return date.fromisoformat(s)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid birth_date. Use YYYY-MM-DD.") from exc


@router.get("/", response_model=list[UserResponse])
def list_users(
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(require_admin),
) -> list[UserResponse]:
    cursor = db.users.find({}).sort("created_at", -1)
    return [UserResponse.model_validate(public_user_fields(u) or {}) for u in cursor]


@router.get("/{user_id}/admin-profile", response_model=UserAdminDetailResponse)
def get_user_admin_profile(
    user_id: int,
    db: Database = Depends(get_db),
    viewer: SimpleNamespace = Depends(get_current_user),
) -> UserAdminDetailResponse:
    if not can_staff_campus_dashboard_tools(viewer):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Campus administrator, granted faculty, or student campus lead access required",
        )
    user = db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    regs = list(db.registrations.find({"user_id": user_id}).sort("registered_at", -1))
    event_ids = list({r["event_id"] for r in regs})
    events_by_id = {e["id"]: e for e in db.events.find({"id": {"$in": event_ids}})}
    out_regs: list[MyRegistrationResponse] = []
    for reg in regs:
        ev = events_by_id.get(reg["event_id"])
        if not ev:
            continue
        out_regs.append(
            MyRegistrationResponse(
                id=reg["id"],
                event_id=ev["id"],
                event_title=ev["title"],
                participant_name=reg.get("participant_name"),
                roll_no=reg.get("roll_no"),
                branch=reg.get("branch"),
                college_name=reg.get("college_name"),
                phone=reg.get("phone"),
                email=reg.get("email"),
                registered_at=reg["registered_at"],
            )
        )
    club_rows: list[ClubMembershipAdminRow] = []
    for m in db.community_members.find({"user_id": user_id}).sort("community_id", 1):
        comm = db.communities.find_one({"id": m["community_id"]})
        if not comm:
            continue
        club_rows.append(
            ClubMembershipAdminRow(
                community_id=int(m["community_id"]),
                community_name=str(comm.get("name") or ""),
                is_moderator=bool(m.get("is_moderator")),
            )
        )
    base = UserResponse.model_validate(public_user_fields(user) or {})
    return UserAdminDetailResponse(**base.model_dump(), registrations=out_regs, club_memberships=club_rows)


@router.patch("/me", response_model=UserResponse)
def update_me(
    full_name: str,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> UserResponse:
    db.users.update_one({"id": current_user.id}, {"$set": {"full_name": full_name}})
    updated = db.users.find_one({"id": current_user.id})
    return UserResponse.model_validate(public_user_fields(updated) or {})


@router.patch("/me/profile", response_model=UserResponse)
async def update_my_profile(
    full_name: str | None = Form(None),
    bio: str | None = Form(None),
    birth_date: str | None = Form(None),
    phone: str | None = Form(None),
    college_name: str | None = Form(None),
    profile_image: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> UserResponse:
    has_image = profile_image is not None and bool(profile_image.filename)
    if (
        full_name is None
        and bio is None
        and birth_date is None
        and phone is None
        and college_name is None
        and not has_image
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Provide at least one field to update")

    user_doc = db.users.find_one({"id": current_user.id})
    if not user_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    updates: dict = {}
    if full_name is not None and full_name.strip():
        updates["full_name"] = full_name.strip()
    if bio is not None:
        updates["bio"] = bio.strip() if bio.strip() else None
    if birth_date is not None:
        updates["birth_date"] = _parse_date(birth_date)
    if phone is not None:
        updates["phone"] = phone.strip() if phone.strip() else None
    if college_name is not None:
        updates["college_name"] = college_name.strip() if college_name.strip() else None

    new_path = user_doc.get("profile_image_path")
    if has_image and profile_image is not None:
        suffix = Path(profile_image.filename).suffix.lower()
        if suffix not in ALLOWED_IMAGE:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported image type")
        if user_doc.get("profile_image_path"):
            old = UPLOADS_DIR / Path(user_doc["profile_image_path"]).name
            if old.exists():
                old.unlink()
        filename = f"profile_{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await profile_image.read())
        new_path = f"/uploads/{filename}"
        updates["profile_image_path"] = new_path

    if updates:
        db.users.update_one({"id": current_user.id}, {"$set": updates})

    updated = db.users.find_one({"id": current_user.id})
    return UserResponse.model_validate(public_user_fields(updated) or {})


@router.patch("/{user_id}/community-moderator", response_model=dict)
def admin_set_club_moderator(
    user_id: int,
    payload: ClubModeratorAssignment,
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(require_admin),
) -> dict[str, str]:
    """Campus admin only: grant or revoke club-manager (per-community) for a student or faculty member."""
    target = db.users.find_one({"id": user_id})
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if target.get("role") == "admin":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not applicable to administrator accounts")
    if target.get("role") not in ("student", "faculty"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only student or faculty accounts can be club managers")

    community = db.communities.find_one({"id": payload.community_id})
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")

    existing = db.community_members.find_one({"user_id": user_id, "community_id": payload.community_id})
    now = datetime.now(timezone.utc)

    if payload.is_moderator:
        if existing:
            db.community_members.update_one(
                {"user_id": user_id, "community_id": payload.community_id},
                {"$set": {"is_moderator": True}},
            )
        else:
            mid = next_sequence(db, "community_members")
            db.community_members.insert_one(
                {
                    "_id": mid,
                    "id": mid,
                    "community_id": payload.community_id,
                    "user_id": user_id,
                    "joined_at": now,
                    "is_moderator": True,
                }
            )
    else:
        if existing:
            db.community_members.update_one(
                {"user_id": user_id, "community_id": payload.community_id},
                {"$set": {"is_moderator": False}},
            )

    return {"status": "ok"}


@router.patch("/{user_id}", response_model=UserResponse)
def admin_update_user(
    user_id: int,
    payload: UserAdminUpdate,
    db: Database = Depends(get_db),
    admin: SimpleNamespace = Depends(require_admin),
) -> UserResponse:
    """Change campus member role, activation, or display name. Admin accounts are not editable here."""
    body = payload.model_dump(exclude_unset=True)
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Provide at least one field to update")
    target = db.users.find_one({"id": user_id})
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if target.get("role") == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin accounts cannot be changed through this endpoint",
        )

    updates: dict = {}
    if "full_name" in body and body["full_name"] is not None:
        fn = str(body["full_name"]).strip()
        if fn:
            updates["full_name"] = fn
    if "role" in body and body["role"] is not None:
        updates["role"] = body["role"]
        if body["role"] == "faculty":
            updates["student_admin"] = False
        elif body["role"] == "student":
            updates["academic_posting_allowed"] = False

    if "academic_posting_allowed" in body and body["academic_posting_allowed"] is not None:
        eff = updates.get("role", target.get("role"))
        if eff != "faculty":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="academic_posting_allowed applies only to faculty accounts",
            )
        updates["academic_posting_allowed"] = bool(body["academic_posting_allowed"])

    if "student_admin" in body and body["student_admin"] is not None:
        eff = updates.get("role", target.get("role"))
        if eff != "student":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="student_admin applies only to student accounts",
            )
        updates["student_admin"] = bool(body["student_admin"])

    if "is_active" in body and body["is_active"] is not None:
        if user_id == admin.id and body["is_active"] is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot deactivate your own account",
            )
        updates["is_active"] = bool(body["is_active"])

    if not updates:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid updates provided")

    db.users.update_one({"id": user_id}, {"$set": updates})
    updated = db.users.find_one({"id": user_id})
    return UserResponse.model_validate(public_user_fields(updated) or {})
