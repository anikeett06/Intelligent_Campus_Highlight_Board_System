import json
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.db.mongo import next_sequence
from app.db.mongo_docs import strip_mongo_id
from app.schemas.event import EventCreate, EventResponse
from app.schemas.registration import EventRegistrationPayload
from app.services.campus_staff_permissions import assert_staff_dashboard_tools
from app.services.categorization import categorize_events
from app.services.notification_audience import academic_faculty_ids, student_ids, USER_IS_ACTIVE_QUERY
from app.services.notify_insert import insert_notifications_for_users

router = APIRouter(prefix="/events", tags=["events"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
TIMETABLE_SUFFIXES = {".pdf", ".xls", ".xlsx", ".csv", ".ods"}


def _bool_from_form(raw: str | bool | None, default: bool = True) -> bool:
    if raw is None:
        return default
    if isinstance(raw, bool):
        return raw
    s = str(raw).strip().lower()
    if s in ("false", "0", "no", "off", ""):
        return False
    if s in ("true", "1", "yes", "on"):
        return True
    return default


def _normalize_custom_link(
    label: str | None,
    url: str | None,
) -> tuple[str | None, str | None]:
    cli = (label or "").strip() or None
    cu = (url or "").strip() or None
    if (cli is None) ^ (cu is None):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Custom button needs both a label and a URL, or leave both empty.",
        )
    if cu is not None and not (cu.lower().startswith("http://") or cu.lower().startswith("https://")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Custom link URL must start with http:// or https://",
        )
    return cli, cu


_EDITOR_SECTIONS: tuple[str, ...] = (
    "poster",
    "headline",
    "schedule",
    "story",
    "highlights",
    "links",
    "audience",
    "advanced",
)
_EDITOR_SECTIONS_SET = frozenset(_EDITOR_SECTIONS)
_DEFAULT_EDITOR_ORDER_JSON = json.dumps(list(_EDITOR_SECTIONS))


def _optional_clean_str(v: str | None) -> str | None:
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def _optional_json_blob(v: str | None) -> str | None:
    """Persist optional JSON text; empty strings become None."""
    s = _optional_clean_str(v)
    if s is None:
        return None
    if s in ("{}", "[]", "null"):
        return None
    return s


async def _store_image_upload(upload: UploadFile, *, allowed_suffixes: set[str]) -> str:
    if upload is None or not upload.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing file")
    suffix = Path(upload.filename).suffix.lower()
    if suffix not in allowed_suffixes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported image type for this upload",
        )
    filename = f"{uuid4().hex}{suffix}"
    file_path = UPLOADS_DIR / filename
    file_path.write_bytes(await upload.read())
    return f"/uploads/{filename}"


def _unlink_upload_path(path: str | None) -> None:
    if not path or not isinstance(path, str):
        return
    name = Path(path).name
    if not name or name in (".", ".."):
        return
    old = UPLOADS_DIR / name
    if old.exists():
        old.unlink()


_BACKGROUND_KINDS: tuple[str, ...] = ("none", "color", "image")


def _normalize_background_kind(raw: str | None) -> str:
    s = (raw or "none").strip().lower()
    return s if s in _BACKGROUND_KINDS else "none"


def _normalize_hex_color(raw: str | None) -> str | None:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    if not s.startswith("#"):
        s = f"#{s}"
    if len(s) == 4:
        s = "#" + "".join(ch * 2 for ch in s[1:])
    if len(s) != 7:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Background color must be a hex value like #RRGGBB.",
        )
    body = s[1:].lower()
    valid = "0123456789abcdef"
    for ch in body:
        if ch not in valid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Background color must be a hex value like #RRGGBB.",
            )
    return f"#{body}"


def _normalize_editor_section_order(raw: str | None) -> str | None:
    if raw is None or not str(raw).strip():
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return _DEFAULT_EDITOR_ORDER_JSON
    if not isinstance(data, list):
        return _DEFAULT_EDITOR_ORDER_JSON
    ordered: list[str] = []
    seen: set[str] = set()
    for item in data:
        key = str(item).strip()
        if key in _EDITOR_SECTIONS_SET and key not in seen:
            ordered.append(key)
            seen.add(key)
    for key in _EDITOR_SECTIONS:
        if key not in seen:
            ordered.append(key)
            seen.add(key)
    return json.dumps(ordered)


def _parse_iso_datetime(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid datetime format. Use ISO-8601.") from exc


def _manager_ids(db: Database) -> list[int]:
    out: list[int] = []
    for u in db.users.find(
        {**USER_IS_ACTIVE_QUERY},
        {"id": 1, "role": 1, "academic_posting_allowed": 1, "student_admin": 1},
    ):
        r = u.get("role")
        uid = int(u["id"])
        if r == "admin":
            out.append(uid)
        elif r == "faculty" and u.get("academic_posting_allowed", False):
            out.append(uid)
        elif r == "student" and u.get("student_admin", False):
            out.append(uid)
    return list(dict.fromkeys(out))


def _normalize_segment(seg: str | None) -> str:
    s = (seg or "non_academic").strip().lower()
    return s if s in ("academic", "non_academic") else "non_academic"


def _visible_on_dashboard(row: dict) -> bool:
    """Omit from dashboard feeds when organizers hide an activity from the board."""
    v = row.get("show_in_dashboard")
    if v is None:
        return True
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("false", "0", "no", "off", ""):
        return False
    return True


def _trending_highlight(row: dict) -> bool:
    v = row.get("trending_highlight")
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    return s in ("true", "1", "yes", "on")


def _dashboard_segment_for_create(manager: SimpleNamespace, requested: str) -> str:
    """Admin: both boards. Granted faculty: academic only. Student campus lead: non-academic only."""
    seg = _normalize_segment(requested)
    role = getattr(manager, "role", None) or ""
    if role == "admin":
        return seg
    if role == "faculty":
        if not getattr(manager, "academic_posting_allowed", False):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your faculty account is not enabled for academic posting. Ask a campus administrator.",
            )
        if seg != "academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Faculty may only create academic dashboard activities.",
            )
        return "academic"
    if role == "student" and getattr(manager, "student_admin", False):
        if seg != "non_academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Student campus leads may only create non-academic activities.",
            )
        return "non_academic"
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not permitted to create this activity.")


def _assert_creator_or_campus_admin(manager: SimpleNamespace, event: dict, *, verb: str) -> None:
    """Faculty/student leads may only change dashboard rows they created; campus admin may change any."""
    if getattr(manager, "role", None) == "admin":
        return
    cb = event.get("created_by")
    try:
        if cb is None or int(cb) != int(manager.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Only the activity creator or a campus administrator can {verb} this.",
            )
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Only the activity creator or a campus administrator can {verb} this.",
        ) from None


def _dashboard_segment_for_update(manager: SimpleNamespace, existing: dict, requested: str) -> str:
    seg = _normalize_segment(requested)
    existing_seg = _normalize_segment(existing.get("dashboard_segment"))
    role = getattr(manager, "role", None) or ""
    if role == "admin":
        return seg
    if role == "faculty":
        if not getattr(manager, "academic_posting_allowed", False):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your faculty account is not enabled for academic posting. Ask a campus administrator.",
            )
        if existing_seg != "academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Faculty may only edit academic dashboard activities.",
            )
        if seg != "academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Faculty activities must remain on the academic dashboard.",
            )
        return "academic"
    if role == "student" and getattr(manager, "student_admin", False):
        if existing_seg != "non_academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Student campus leads may only edit non-academic activities.",
            )
        if seg != "non_academic":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Student lead content must stay on the non-academic board.",
            )
        return "non_academic"
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not permitted to update this activity.")


def _notify_students_new_dashboard_event(
    db: Database,
    *,
    event_id: int,
    title: str,
    description: str | None,
    priority: str,
    source_role: str,
    dashboard_segment: str,
) -> None:
    seg = _normalize_segment(dashboard_segment)
    nt = "academic" if seg == "academic" else "event"
    if seg == "academic":
        ttl = f"New academic activity: {title}"
        body = description or "A new academic item was posted. Open it from the Events tab or dashboard."
    else:
        ttl = f"New campus event: {title}"
        body = description or "A new event was posted. Open it from the Events tab or dashboard."
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=ttl,
        body=body,
        priority=priority,
        kind="update",
        source_role=source_role,
        route=f"/events/{event_id}",
        notification_type=nt,
    )


def _notify_students_updated_dashboard_event(
    db: Database,
    *,
    event_id: int,
    title: str,
    description: str | None,
    priority: str,
    source_role: str,
    dashboard_segment: str,
) -> None:
    seg = _normalize_segment(dashboard_segment)
    nt = "academic" if seg == "academic" else "event"
    if seg == "academic":
        ttl = f"Academic activity updated: {title}"
        body = description or "An academic dashboard item was updated. Check the Events tab for details."
    else:
        ttl = f"Event updated: {title}"
        body = description or "A campus event was updated. Check the Events tab for details."
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=ttl,
        body=body,
        priority=priority,
        kind="update",
        source_role=source_role,
        route=f"/events/{event_id}",
        notification_type=nt,
    )


def _registration_count_by_event(db: Database) -> dict[int, int]:
    out: dict[int, int] = {}
    for row in db.registrations.aggregate([{"$group": {"_id": "$event_id", "n": {"$sum": 1}}}]):
        eid = row.get("_id")
        if eid is not None:
            out[int(eid)] = int(row["n"])
    return out


def _event_response(db: Database, doc: dict, counts: dict[int, int] | None = None) -> EventResponse:
    base = strip_mongo_id(doc) or {}
    if "dashboard_segment" not in base or base.get("dashboard_segment") not in ("academic", "non_academic"):
        base["dashboard_segment"] = "non_academic"
    eid = int(base["id"])
    if counts is not None:
        n = counts.get(eid, 0)
    else:
        n = db.registrations.count_documents({"event_id": eid})
    return EventResponse.model_validate({**base, "registration_count": n})


@router.get("/", response_model=list[EventResponse])
def list_events(db: Database = Depends(get_db)) -> list[EventResponse]:
    counts = _registration_count_by_event(db)
    cursor = db.events.find({}).sort("start_time", -1)
    return [_event_response(db, doc, counts) for doc in cursor]


@router.post("/", response_model=EventResponse)
def create_event(
    payload: EventCreate,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> EventResponse:
    assert_staff_dashboard_tools(manager)
    eid = next_sequence(db, "events")
    seg = _dashboard_segment_for_create(manager, payload.dashboard_segment)
    dumped = payload.model_dump()
    dumped["dashboard_segment"] = seg
    doc = {
        "_id": eid,
        "id": eid,
        **dumped,
        "poster_path": None,
        "exam_timetable_path": None,
        "created_by": manager.id,
    }
    db.events.insert_one(doc)
    _notify_students_new_dashboard_event(
        db,
        event_id=eid,
        title=payload.title,
        description=payload.description,
        priority=payload.priority,
        source_role=manager.role,
        dashboard_segment=seg,
    )
    return _event_response(db, doc)


@router.post("/admin", response_model=EventResponse)
async def create_event_admin(
    title: str = Form(...),
    description: str | None = Form(None),
    category: str = Form("general"),
    priority: str = Form("normal"),
    location: str | None = Form(None),
    start_time: str = Form(...),
    end_time: str = Form(...),
    auto_remove_after_hours: int = Form(0),
    allow_registration: bool = Form(True),
    dashboard_segment: str = Form("non_academic"),
    show_description: str = Form("true"),
    show_location: str = Form("true"),
    show_registration_section: str = Form("true"),
    show_polls_section: str = Form("true"),
    show_announcements_section: str = Form("true"),
    custom_link_label: str | None = Form(None),
    custom_link_url: str | None = Form(None),
    fest_name: str | None = Form(None),
    team_format: str | None = Form(None),
    entry_fee: str | None = Form(None),
    prize_summary: str | None = Form(None),
    show_category_badge: str = Form("true"),
    editor_section_order: str | None = Form(None),
    show_in_dashboard: str = Form("true"),
    trending_highlight: str = Form("false"),
    dashboard_title: str | None = Form(None),
    dashboard_description: str | None = Form(None),
    event_page_json: str | None = Form(None),
    use_separate_carousel_image: str = Form("false"),
    event_page_background_kind: str = Form("none"),
    event_page_background_color: str | None = Form(None),
    poster: UploadFile | None = File(None),
    carousel_poster: UploadFile | None = File(None),
    event_page_background: UploadFile | None = File(None),
    exam_timetable: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> EventResponse:
    assert_staff_dashboard_tools(manager)
    poster_path: str | None = None
    if poster is not None and poster.filename:
        suffix = Path(poster.filename).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported poster type")
        filename = f"{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await poster.read())
        poster_path = f"/uploads/{filename}"
    exam_timetable_path: str | None = None
    if exam_timetable is not None and exam_timetable.filename:
        suffix = Path(exam_timetable.filename).suffix.lower()
        if suffix not in TIMETABLE_SUFFIXES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported timetable type. Use PDF or spreadsheet files.",
            )
        filename = f"{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await exam_timetable.read())
        exam_timetable_path = f"/uploads/{filename}"

    if poster_path is None or (isinstance(poster_path, str) and not str(poster_path).strip()):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A banner (poster) image is required when publishing a new activity.",
        )

    cli, cu = _normalize_custom_link(custom_link_label, custom_link_url)
    eso = _normalize_editor_section_order(editor_section_order)

    seg = _dashboard_segment_for_create(manager, dashboard_segment)

    dashboard_carousel_poster_path: str | None = None
    if _bool_from_form(use_separate_carousel_image, False) and carousel_poster is not None and carousel_poster.filename:
        dashboard_carousel_poster_path = await _store_image_upload(
            carousel_poster,
            allowed_suffixes={".jpg", ".jpeg", ".png", ".webp", ".gif"},
        )

    bg_kind = _normalize_background_kind(event_page_background_kind)
    bg_color: str | None = None
    bg_path: str | None = None
    if bg_kind == "color":
        bg_color = _normalize_hex_color(event_page_background_color)
    elif bg_kind == "image" and event_page_background is not None and event_page_background.filename:
        bg_path = await _store_image_upload(
            event_page_background,
            allowed_suffixes={".jpg", ".jpeg", ".png", ".webp", ".gif"},
        )

    eid = next_sequence(db, "events")
    doc = {
        "_id": eid,
        "id": eid,
        "title": title,
        "description": description,
        "category": category,
        "priority": priority,
        "location": location,
        "start_time": _parse_iso_datetime(start_time),
        "end_time": _parse_iso_datetime(end_time),
        "auto_remove_after_hours": max(0, auto_remove_after_hours),
        "allow_registration": allow_registration,
        "dashboard_segment": seg,
        "poster_path": poster_path,
        "exam_timetable_path": exam_timetable_path,
        "created_by": manager.id,
        "show_description": _bool_from_form(show_description, True),
        "show_location": _bool_from_form(show_location, True),
        "show_registration_section": _bool_from_form(show_registration_section, True),
        "show_polls_section": _bool_from_form(show_polls_section, True),
        "show_announcements_section": _bool_from_form(show_announcements_section, True),
        "custom_link_label": cli,
        "custom_link_url": cu,
        "fest_name": _optional_clean_str(fest_name),
        "team_format": _optional_clean_str(team_format),
        "entry_fee": _optional_clean_str(entry_fee),
        "prize_summary": _optional_clean_str(prize_summary),
        "show_category_badge": _bool_from_form(show_category_badge, True),
        "editor_section_order": eso,
        "show_in_dashboard": _bool_from_form(show_in_dashboard, True),
        "trending_highlight": _bool_from_form(trending_highlight, False) and _bool_from_form(show_in_dashboard, True),
        "dashboard_title": _optional_clean_str(dashboard_title),
        "dashboard_description": _optional_clean_str(dashboard_description),
        "event_page_json": _optional_json_blob(event_page_json),
        "dashboard_carousel_poster_path": dashboard_carousel_poster_path,
        "event_page_background_kind": bg_kind,
        "event_page_background_color": bg_color,
        "event_page_background_path": bg_path,
    }
    db.events.insert_one(doc)
    nt = "academic" if seg == "academic" else "event"
    _notify_students_new_dashboard_event(
        db,
        event_id=eid,
        title=_optional_clean_str(dashboard_title) or title,
        description=_optional_clean_str(dashboard_description) or description,
        priority=priority,
        source_role=manager.role,
        dashboard_segment=seg,
    )
    if manager.role == "admin":
        insert_notifications_for_users(
            db,
            academic_faculty_ids(db),
            title=f"Admin update: {title}",
            body=description or "A campus activity was published.",
            priority=priority,
            kind="update",
            source_role="admin",
            route=f"/events/{eid}",
            notification_type=nt,
        )
    return _event_response(db, doc)


@router.get("/dashboard/grouped")
def grouped_events(db: Database = Depends(get_db)) -> dict[str, list[EventResponse]]:
    counts = _registration_count_by_event(db)
    raw: list[dict] = []
    for doc in db.events.find({}):
        row = strip_mongo_id(doc) or {}
        if not _visible_on_dashboard(row):
            continue
        row["registration_count"] = counts.get(int(row["id"]), 0)
        raw.append(row)
    grouped = categorize_events(raw)
    return {key: [EventResponse.model_validate(e) for e in value] for key, value in grouped.items()}


@router.get("/{event_id}", response_model=EventResponse)
def get_event(event_id: int, db: Database = Depends(get_db)) -> EventResponse:
    doc = db.events.find_one({"id": event_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    return _event_response(db, doc)


@router.put("/{event_id}/admin", response_model=EventResponse)
async def update_event_admin(
    event_id: int,
    title: str = Form(...),
    description: str | None = Form(None),
    category: str = Form("general"),
    priority: str = Form("normal"),
    location: str | None = Form(None),
    start_time: str = Form(...),
    end_time: str = Form(...),
    auto_remove_after_hours: int = Form(0),
    allow_registration: bool = Form(True),
    dashboard_segment: str = Form("non_academic"),
    show_description: str = Form("true"),
    show_location: str = Form("true"),
    show_registration_section: str = Form("true"),
    show_polls_section: str = Form("true"),
    show_announcements_section: str = Form("true"),
    custom_link_label: str | None = Form(None),
    custom_link_url: str | None = Form(None),
    fest_name: str | None = Form(None),
    team_format: str | None = Form(None),
    entry_fee: str | None = Form(None),
    prize_summary: str | None = Form(None),
    show_category_badge: str = Form("true"),
    editor_section_order: str | None = Form(None),
    show_in_dashboard: str = Form("true"),
    trending_highlight: str = Form("false"),
    dashboard_title: str | None = Form(None),
    dashboard_description: str | None = Form(None),
    event_page_json: str | None = Form(None),
    use_separate_carousel_image: str = Form("false"),
    event_page_background_kind: str = Form("none"),
    event_page_background_color: str | None = Form(None),
    poster: UploadFile | None = File(None),
    carousel_poster: UploadFile | None = File(None),
    event_page_background: UploadFile | None = File(None),
    exam_timetable: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> EventResponse:
    assert_staff_dashboard_tools(manager)
    event = db.events.find_one({"id": event_id})
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    _assert_creator_or_campus_admin(manager, event, verb="edit")

    poster_path = event.get("poster_path")
    exam_timetable_path = event.get("exam_timetable_path")

    if poster is not None and poster.filename:
        suffix = Path(poster.filename).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported poster type")
        if poster_path:
            old = UPLOADS_DIR / Path(poster_path).name
            if old.exists():
                old.unlink()
        filename = f"{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await poster.read())
        poster_path = f"/uploads/{filename}"
    if exam_timetable is not None and exam_timetable.filename:
        suffix = Path(exam_timetable.filename).suffix.lower()
        if suffix not in TIMETABLE_SUFFIXES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported timetable type. Use PDF or spreadsheet files.",
            )
        if exam_timetable_path:
            old = UPLOADS_DIR / Path(exam_timetable_path).name
            if old.exists():
                old.unlink()
        filename = f"{uuid4().hex}{suffix}"
        file_path = UPLOADS_DIR / filename
        file_path.write_bytes(await exam_timetable.read())
        exam_timetable_path = f"/uploads/{filename}"

    if poster_path is None or (isinstance(poster_path, str) and not str(poster_path).strip()):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Add a banner image before saving (upload a poster).",
        )

    cli, cu = _normalize_custom_link(custom_link_label, custom_link_url)
    eso = _normalize_editor_section_order(editor_section_order)

    seg = _dashboard_segment_for_update(manager, event, dashboard_segment)

    prev_car = event.get("dashboard_carousel_poster_path")
    prev_poster = event.get("poster_path")
    use_car = _bool_from_form(use_separate_carousel_image, False)
    carousel_path_out: str | None = str(prev_car).strip() if prev_car else None
    if not use_car:
        carousel_path_out = None
        if prev_car and str(prev_car).strip() and str(prev_car) != str(prev_poster):
            _unlink_upload_path(str(prev_car))
    elif carousel_poster is not None and carousel_poster.filename:
        if prev_car and str(prev_car).strip() and str(prev_car) != str(prev_poster):
            _unlink_upload_path(str(prev_car))
        carousel_path_out = await _store_image_upload(
            carousel_poster,
            allowed_suffixes={".jpg", ".jpeg", ".png", ".webp", ".gif"},
        )

    updated = {
        **event,
        "title": title,
        "description": description,
        "category": category,
        "priority": priority,
        "location": location,
        "start_time": _parse_iso_datetime(start_time),
        "end_time": _parse_iso_datetime(end_time),
        "auto_remove_after_hours": max(0, auto_remove_after_hours),
        "allow_registration": allow_registration,
        "dashboard_segment": seg,
        "poster_path": poster_path,
        "exam_timetable_path": exam_timetable_path,
        "show_description": _bool_from_form(show_description, True),
        "show_location": _bool_from_form(show_location, True),
        "show_registration_section": _bool_from_form(show_registration_section, True),
        "show_polls_section": _bool_from_form(show_polls_section, True),
        "show_announcements_section": _bool_from_form(show_announcements_section, True),
        "custom_link_label": cli,
        "custom_link_url": cu,
        "fest_name": _optional_clean_str(fest_name),
        "team_format": _optional_clean_str(team_format),
        "entry_fee": _optional_clean_str(entry_fee),
        "prize_summary": _optional_clean_str(prize_summary),
        "show_category_badge": _bool_from_form(show_category_badge, True),
        "editor_section_order": eso,
        "show_in_dashboard": _bool_from_form(show_in_dashboard, True),
        "trending_highlight": _bool_from_form(trending_highlight, False) and _bool_from_form(show_in_dashboard, True),
        "dashboard_title": _optional_clean_str(dashboard_title),
        "dashboard_description": _optional_clean_str(dashboard_description),
        "event_page_json": _optional_json_blob(event_page_json),
        "dashboard_carousel_poster_path": carousel_path_out,
    }

    new_bg_kind = _normalize_background_kind(event_page_background_kind)
    prev_bg_path = event.get("event_page_background_path")
    bg_color_out: str | None = None
    bg_path_out: str | None = None
    if new_bg_kind == "color":
        bg_color_out = _normalize_hex_color(event_page_background_color)
        if prev_bg_path:
            _unlink_upload_path(str(prev_bg_path))
    elif new_bg_kind == "image":
        if event_page_background is not None and event_page_background.filename:
            if prev_bg_path:
                _unlink_upload_path(str(prev_bg_path))
            bg_path_out = await _store_image_upload(
                event_page_background,
                allowed_suffixes={".jpg", ".jpeg", ".png", ".webp", ".gif"},
            )
        else:
            bg_path_out = str(prev_bg_path).strip() if prev_bg_path else None
            if not bg_path_out:
                new_bg_kind = "none"
    else:
        if prev_bg_path:
            _unlink_upload_path(str(prev_bg_path))
    updated["event_page_background_kind"] = new_bg_kind
    updated["event_page_background_color"] = bg_color_out
    updated["event_page_background_path"] = bg_path_out

    db.events.replace_one({"id": event_id}, updated)

    nt = "academic" if seg == "academic" else "event"
    _notify_students_updated_dashboard_event(
        db,
        event_id=event_id,
        title=_optional_clean_str(dashboard_title) or title,
        description=_optional_clean_str(dashboard_description) or description,
        priority=priority,
        source_role=manager.role,
        dashboard_segment=seg,
    )
    if manager.role == "admin":
        insert_notifications_for_users(
            db,
            academic_faculty_ids(db),
            title=f"Admin updated activity: {title}",
            body=description or "A campus activity was updated.",
            priority=priority,
            kind="update",
            source_role="admin",
            route=f"/events/{event_id}",
            notification_type=nt,
        )
    return _event_response(db, updated)


@router.patch("/{event_id}/admin/trending", response_model=EventResponse)
def set_trending_highlight_admin(
    event_id: int,
    trending_highlight: bool = True,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> EventResponse:
    """Promote/demote an activity in the dashboard 'Trending highlights' carousel."""
    assert_staff_dashboard_tools(manager)
    event = db.events.find_one({"id": event_id})
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    _assert_creator_or_campus_admin(manager, event, verb="edit")

    value = bool(trending_highlight) and _visible_on_dashboard(event)
    db.events.update_one({"id": event_id}, {"$set": {"trending_highlight": value}})
    event["trending_highlight"] = value
    return _event_response(db, event)


@router.delete("/{event_id}/admin", status_code=status.HTTP_204_NO_CONTENT)
def delete_event_admin(
    event_id: int,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> None:
    """Remove a dashboard activity. Campus admin: any. Others: only activities they created (same board rules as edit)."""
    assert_staff_dashboard_tools(manager)
    event = db.events.find_one({"id": event_id})
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    _assert_creator_or_campus_admin(manager, event, verb="delete")
    if getattr(manager, "role", None) != "admin":
        _dashboard_segment_for_update(
            manager,
            event,
            _normalize_segment(event.get("dashboard_segment")),
        )

    poster_path = event.get("poster_path")
    if isinstance(poster_path, str) and poster_path:
        old = UPLOADS_DIR / Path(poster_path).name
        if old.exists():
            old.unlink()
    exam_path = event.get("exam_timetable_path")
    if isinstance(exam_path, str) and exam_path:
        old_ex = UPLOADS_DIR / Path(exam_path).name
        if old_ex.exists():
            old_ex.unlink()

    db.registrations.delete_many({"event_id": event_id})
    db.events.delete_one({"id": event_id})


@router.post("/{event_id}/register")
def register_event(
    event_id: int,
    payload: EventRegistrationPayload,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    event = db.events.find_one({"id": event_id})
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if not event.get("allow_registration", True):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Registration is closed for this event")

    existing = db.registrations.find_one({"user_id": current_user.id, "event_id": event_id})
    current_count = db.registrations.count_documents({"event_id": event_id})
    managers = _manager_ids(db)

    pdata = payload.model_dump()
    if existing:
        db.registrations.update_one({"_id": existing["_id"]}, {"$set": pdata})
        insert_notifications_for_users(
            db,
            managers,
            title=f"Event registration updated: {event['title']}",
            body=f"{current_user.full_name} updated registration. Total students registered: {current_count}.",
            priority="normal",
            kind="event_registration",
            source_role="student",
            route=f"/admin/events/{event_id}/registrations",
            notification_type="event",
        )
        insert_notifications_for_users(
            db,
            [current_user.id],
            title=f"Registration saved: {event['title']}",
            body="Your event registration details were updated.",
            priority="normal",
            kind="update",
            source_role="system",
            route=f"/events/{event_id}",
            notification_type="event",
        )
        return {"message": "Registration updated successfully"}

    rid = next_sequence(db, "registrations")
    now = datetime.now(timezone.utc)
    reg_doc = {
        "_id": rid,
        "id": rid,
        "user_id": current_user.id,
        "event_id": event_id,
        "registered_at": now,
        **pdata,
    }
    db.registrations.insert_one(reg_doc)
    insert_notifications_for_users(
        db,
        managers,
        title=f"New student registration: {event['title']}",
        body=f"{current_user.full_name} registered. Total students registered: {current_count + 1}.",
        priority="normal",
        kind="event_registration",
        source_role="student",
        route=f"/admin/events/{event_id}/registrations",
        notification_type="event",
    )
    insert_notifications_for_users(
        db,
        [current_user.id],
        title=f"You're registered: {event['title']}",
        body="Open the event to see details or update your registration.",
        priority="normal",
        kind="update",
        source_role="system",
        route=f"/events/{event_id}",
        notification_type="event",
    )
    return {"message": "Registered successfully"}


@router.delete("/{event_id}/register")
def unregister_event(
    event_id: int,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    registration = db.registrations.find_one({"user_id": current_user.id, "event_id": event_id})
    if not registration:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Registration not found")
    event = db.events.find_one({"id": event_id})
    managers = _manager_ids(db)
    db.registrations.delete_one({"_id": registration["_id"]})
    remaining = db.registrations.count_documents({"event_id": event_id})
    if event:
        insert_notifications_for_users(
            db,
            managers,
            title=f"Registration cancelled: {event['title']}",
            body=f"{current_user.full_name} cancelled registration. Total students registered: {max(0, remaining)}.",
            priority="normal",
            kind="event_registration",
            source_role="student",
            route=f"/admin/events/{event_id}/registrations",
            notification_type="event",
        )
        insert_notifications_for_users(
            db,
            [current_user.id],
            title=f"Registration cancelled: {event['title']}",
            body="You are no longer registered for this event.",
            priority="normal",
            kind="update",
            source_role="system",
            route=f"/events/{event_id}",
            notification_type="event",
        )
    return {"message": "Unregistered successfully"}
