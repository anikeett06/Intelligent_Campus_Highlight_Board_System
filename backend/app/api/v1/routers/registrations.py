from types import SimpleNamespace

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.services.campus_staff_permissions import can_view_event_registrations
from app.schemas.registration import EventRegistrationAdminRow, MyRegistrationResponse

router = APIRouter(prefix="/registrations", tags=["registrations"])


@router.get("/me", response_model=list[MyRegistrationResponse])
def list_my_registrations(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[MyRegistrationResponse]:
    regs = list(db.registrations.find({"user_id": current_user.id}).sort("registered_at", -1))
    if not regs:
        return []
    event_ids = list({r["event_id"] for r in regs})
    events_by_id = {e["id"]: e for e in db.events.find({"id": {"$in": event_ids}})}
    out: list[MyRegistrationResponse] = []
    for reg in regs:
        ev = events_by_id.get(reg["event_id"])
        if not ev:
            continue
        out.append(
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
    return out


@router.get("/event/{event_id}", response_model=list[EventRegistrationAdminRow])
def list_registrations_for_event(
    event_id: int,
    db: Database = Depends(get_db),
    viewer: SimpleNamespace = Depends(get_current_user),
) -> list[EventRegistrationAdminRow]:
    if not db.events.find_one({"id": event_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if not can_view_event_registrations(db, viewer, event_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not permitted to view registrations for this event")
    regs = list(db.registrations.find({"event_id": event_id}).sort("registered_at", -1))
    if not regs:
        return []
    user_ids = list({r["user_id"] for r in regs})
    users_by_id = {u["id"]: u for u in db.users.find({"id": {"$in": user_ids}})}
    out: list[EventRegistrationAdminRow] = []
    for reg in regs:
        u = users_by_id.get(reg["user_id"])
        if not u:
            continue
        out.append(
            EventRegistrationAdminRow(
                registration_id=reg["id"],
                user_id=u["id"],
                full_name=u["full_name"],
                account_email=u["email"],
                profile_image_path=u.get("profile_image_path"),
                participant_name=reg.get("participant_name"),
                roll_no=reg.get("roll_no"),
                branch=reg.get("branch"),
                college_name=reg.get("college_name"),
                phone=reg.get("phone"),
                registration_email=reg.get("email"),
                registered_at=reg["registered_at"],
            )
        )
    return out
