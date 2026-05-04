from types import SimpleNamespace

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db, require_admin
from app.services.campus_staff_permissions import assert_staff_dashboard_tools
from app.db.mongo_docs import strip_mongo_id
from app.schemas.notification import (
    NotificationBroadcastToStudents,
    NotificationCreate,
    NotificationCreatePayload,
    NotificationResponse,
)
from app.services.notification_audience import USER_IS_ACTIVE_QUERY
from app.services.user_notifications import create_user_notification, prepare_notification_document

router = APIRouter(prefix="/notifications", tags=["notifications"])


def _broadcast_notification_type(priority: str) -> str:
    p = (priority or "normal").lower()
    if p == "academic":
        return "academic"
    return "dashboard"


@router.get("/", response_model=list[NotificationResponse])
def my_notifications(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
) -> list[NotificationResponse]:
    filt: dict = {"user_id": current_user.id}
    # Regular students: dashboard-style feed only. Campus leads keep role=student but need staff alerts.
    is_student_lead = current_user.role == "student" and bool(getattr(current_user, "student_admin", False))
    if current_user.role == "student" and not is_student_lead:
        filt["kind"] = "update"
    cursor = db.notifications.find(filt).sort("created_at", -1).limit(limit)
    return [NotificationResponse.model_validate(prepare_notification_document(strip_mongo_id(n) or n)) for n in cursor]


@router.get("/me", response_model=list[NotificationResponse])
def my_notifications_alias(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
) -> list[NotificationResponse]:
    """Alias for GET / (JWT-scoped feed)."""
    return my_notifications(db, current_user, limit)


@router.get("/admin/feed")
def admin_notification_feed(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(require_admin),
) -> dict[str, list[NotificationResponse]]:
    rows = list(db.notifications.find({"user_id": current_user.id}).sort("created_at", -1))
    updates = [
        NotificationResponse.model_validate(prepare_notification_document(strip_mongo_id(n) or n))
        for n in rows
        if n.get("kind") == "update"
    ]
    student_activity = [
        NotificationResponse.model_validate(prepare_notification_document(strip_mongo_id(n) or n))
        for n in rows
        if n.get("kind") != "update"
    ]
    return {"updates": updates, "student_activity": student_activity}


@router.post("/", response_model=NotificationResponse)
def admin_post_notification(
    payload: NotificationCreate,
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(require_admin),
) -> NotificationResponse:
    if not db.users.find_one({"id": payload.user_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Target user not found")
    nid = create_user_notification(
        db,
        payload.user_id,
        payload.title,
        payload.body,
        payload.notification_type,
        payload.priority,
        route=payload.route,
        source_role=payload.source_role,
        kind=payload.kind,
        send_push=True,
    )
    doc = db.notifications.find_one({"id": nid})
    if not doc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to load notification")
    return NotificationResponse.model_validate(prepare_notification_document(strip_mongo_id(doc) or doc))


@router.post("/create", response_model=NotificationResponse)
def admin_post_notification_create_alias(
    payload: NotificationCreatePayload,
    db: Database = Depends(get_db),
    sender: SimpleNamespace = Depends(get_current_user),
) -> NotificationResponse:
    """Create a single notification (campus staff with posting tools). Same behavior as POST / with broader auth."""
    assert_staff_dashboard_tools(sender)
    if not db.users.find_one({"id": payload.user_id}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Target user not found")
    nid = create_user_notification(
        db,
        payload.user_id,
        payload.title,
        payload.body,
        payload.notification_type,
        payload.priority,
        route=payload.route,
        source_role=payload.source_role,
        kind=payload.kind,
        send_push=True,
    )
    doc = db.notifications.find_one({"id": nid})
    if not doc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to load notification")
    return NotificationResponse.model_validate(prepare_notification_document(strip_mongo_id(doc) or doc))


@router.post("/broadcast/students")
def broadcast_notice_to_students(
    payload: NotificationBroadcastToStudents,
    db: Database = Depends(get_db),
    sender_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, int]:
    assert_staff_dashboard_tools(sender_user)
    students = list(db.users.find({"role": "student", **USER_IS_ACTIVE_QUERY}))
    admins = list(db.users.find({"role": "admin", **USER_IS_ACTIVE_QUERY}))
    faculties = list(db.users.find({"role": "faculty", **USER_IS_ACTIVE_QUERY}))
    audience = (payload.audience or "students").lower()
    if audience not in {"students", "admins", "both"}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="audience must be students, admins, or both")

    nt = _broadcast_notification_type(payload.priority)
    route = payload.route or "/dashboard"

    create_user_notification(
        db,
        sender_user.id,
        payload.title,
        payload.body,
        nt,
        payload.priority,
        route=route,
        source_role=str(sender_user.role),
        kind="update",
        send_push=True,
    )

    recipient_ids: set[int] = set()
    if audience in {"students", "both"}:
        recipient_ids.update(s["id"] for s in students)
        if sender_user.role == "admin":
            recipient_ids.update(f["id"] for f in faculties if f["id"] != sender_user.id)
    if audience in {"admins", "both"}:
        recipient_ids.update(a["id"] for a in admins if a["id"] != sender_user.id)

    sent = 0
    for uid in recipient_ids:
        if uid == sender_user.id:
            continue
        create_user_notification(
            db,
            uid,
            payload.title,
            payload.body,
            nt,
            payload.priority,
            route=route,
            source_role=str(sender_user.role),
            kind="update",
            send_push=True,
        )
        sent += 1

    return {"recipients_notified": sent}


@router.patch("/{notification_id}/read")
def mark_read(
    notification_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    result = db.notifications.update_one(
        {"id": notification_id, "user_id": current_user.id},
        {"$set": {"is_read": True}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")
    return {"message": "Notification marked as read"}


@router.put("/read/{notification_id}")
def mark_read_put_alias(
    notification_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    return mark_read(notification_id, db, current_user)


@router.put("/read-all")
def mark_all_read(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    db.notifications.update_many({"user_id": current_user.id, "is_read": False}, {"$set": {"is_read": True}})
    return {"message": "All notifications marked as read"}


@router.delete("/{notification_id}")
def delete_notification(
    notification_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    result = db.notifications.delete_one({"id": notification_id, "user_id": current_user.id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")
    return {"message": "Notification deleted"}
