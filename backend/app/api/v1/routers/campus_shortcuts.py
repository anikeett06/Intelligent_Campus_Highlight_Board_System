"""Singleton documents for academic shortcut file attachments (timetable, etc.)."""

from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.services.campus_staff_permissions import assert_academic_shortcuts
from app.services.notification_audience import student_ids
from app.services.notify_insert import insert_notifications_for_users

router = APIRouter(prefix="/campus-shortcuts", tags=["campus-shortcuts"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

SLOTS = frozenset({"timetable", "exam_schedule", "notices", "programs"})

_SLOT_STUDENT_NOTIFY: dict[str, tuple[str, str]] = {
    "timetable": ("Timetable updated", "A new class timetable file is available on the academic dashboard."),
    "exam_schedule": ("Exam schedule file updated", "A new exam schedule document was uploaded for students."),
    "notices": ("Academic notices updated", "Campus academic notices or documents were refreshed."),
    "programs": ("Programs / handbook updated", "Programs or handbook materials on the dashboard were updated."),
}

_SLOT_STUDENT_DELETE_NOTIFY: dict[str, tuple[str, str]] = {
    "timetable": ("Timetable file removed", "The timetable shortcut was cleared on the dashboard."),
    "exam_schedule": ("Exam schedule file removed", "The exam schedule shortcut was cleared on the dashboard."),
    "notices": ("Academic notices file removed", "The notices shortcut was cleared on the dashboard."),
    "programs": ("Programs file removed", "The programs/handbook shortcut was cleared on the dashboard."),
}


ALLOWED_SUFFIXES = frozenset(
    {".pdf", ".xls", ".xlsx", ".csv", ".ods", ".doc", ".docx", ".jpg", ".jpeg", ".png", ".webp"}
)
DOC_ID = "singleton"


def _paths_from_doc(doc: dict | None) -> dict[str, str | None]:
    if not doc:
        return {
            "timetable_path": None,
            "exam_schedule_path": None,
            "notices_path": None,
            "programs_path": None,
        }
    return {
        "timetable_path": doc.get("timetable_path"),
        "exam_schedule_path": doc.get("exam_schedule_path"),
        "notices_path": doc.get("notices_path"),
        "programs_path": doc.get("programs_path"),
    }


@router.get("/")
def get_shortcuts(
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str | None]:
    doc = db.campus_shortcuts.find_one({"_id": DOC_ID})
    return _paths_from_doc(doc)


@router.delete("/{slot}")
def delete_shortcut_file(
    slot: str,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str | None]:
    assert_academic_shortcuts(manager)
    if slot not in SLOTS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid shortcut slot")

    field = f"{slot}_path"
    prev = db.campus_shortcuts.find_one({"_id": DOC_ID}) or {}
    old_path = prev.get(field)
    if not old_path or not isinstance(old_path, str):
        return _paths_from_doc(prev)

    old_file = UPLOADS_DIR / Path(old_path).name
    if old_file.exists() and old_file.is_file():
        old_file.unlink()

    db.campus_shortcuts.update_one({"_id": DOC_ID}, {"$unset": {field: ""}})
    doc = db.campus_shortcuts.find_one({"_id": DOC_ID})
    if old_path and isinstance(old_path, str):
        d_title, d_body = _SLOT_STUDENT_DELETE_NOTIFY[slot]
        insert_notifications_for_users(
            db,
            student_ids(db),
            title=d_title,
            body=d_body,
            priority="normal",
            kind="update",
            source_role=str(manager.role),
            route="/dashboard",
            notification_type="academic",
        )
    return _paths_from_doc(doc)


@router.put("/{slot}")
async def upload_shortcut_file(
    slot: str,
    file: UploadFile = File(...),
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str | None]:
    assert_academic_shortcuts(manager)
    if slot not in SLOTS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid shortcut slot")
    if not file.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing file")

    suffix = Path(file.filename).suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported file type. Allowed: {', '.join(sorted(ALLOWED_SUFFIXES))}",
        )

    filename = f"{uuid4().hex}{suffix}"
    dest = UPLOADS_DIR / filename
    dest.write_bytes(await file.read())
    path = f"/uploads/{filename}"

    field = f"{slot}_path"
    prev = db.campus_shortcuts.find_one({"_id": DOC_ID}) or {}
    old_path = prev.get(field)
    if old_path and isinstance(old_path, str):
        old_name = Path(old_path).name
        old_file = UPLOADS_DIR / old_name
        if old_file.exists() and old_file.is_file():
            old_file.unlink()

    db.campus_shortcuts.update_one(
        {"_id": DOC_ID},
        {"$set": {field: path, "_id": DOC_ID}},
        upsert=True,
    )
    doc = db.campus_shortcuts.find_one({"_id": DOC_ID})

    title, body = _SLOT_STUDENT_NOTIFY[slot]
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=title,
        body=body,
        priority="normal",
        kind="update",
        source_role=str(manager.role),
        route="/dashboard",
        notification_type="academic",
    )

    return _paths_from_doc(doc)
