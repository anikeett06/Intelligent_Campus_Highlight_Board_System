"""Block-style academic notices: each notice may carry text, a PDF, an image, or a link."""

import logging
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.db.mongo import next_sequence
from app.services.campus_staff_permissions import assert_academic_shortcuts
from app.services.notification_audience import student_ids
from app.services.notify_insert import insert_notifications_for_users

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/academic-notices", tags=["academic-notices"])
UPLOADS_DIR = Path(__file__).resolve().parents[4] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

PDF_SUFFIXES = frozenset({".pdf"})
IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png", ".webp", ".gif"})
ALLOWED_SUFFIXES = PDF_SUFFIXES | IMAGE_SUFFIXES
PDF_THUMB_MAX_PX = 720  # longest edge in pixels


def _serialize(doc: dict) -> dict:
    return {
        "id": int(doc.get("id", 0)),
        "title": str(doc.get("title", "")),
        "body": doc.get("body") or "",
        "file_path": doc.get("file_path"),
        "file_kind": doc.get("file_kind"),
        "file_thumbnail_path": doc.get("file_thumbnail_path"),
        "link_url": doc.get("link_url"),
        "created_at": doc.get("created_at"),
        "created_by": doc.get("created_by"),
        "created_by_name": doc.get("created_by_name") or "",
        "expires_at": doc.get("expires_at"),
    }


def _parse_optional_iso_datetime(value: str | None) -> datetime | None:
    """Parse an optional ISO-8601 datetime string. Empty/whitespace returns None."""
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    normalized = s.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid expiry datetime. Use ISO-8601.",
        ) from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _purge_expired_notices(db) -> None:
    """Delete notices whose expiry has passed and remove their uploaded files."""
    now = datetime.now(timezone.utc)
    expired = list(db.academic_notices.find({"expires_at": {"$ne": None, "$lte": now}}))
    if not expired:
        return
    for doc in expired:
        _unlink_upload(doc.get("file_path"))
        _unlink_upload(doc.get("file_thumbnail_path"))
    ids = [int(doc["id"]) for doc in expired if doc.get("id") is not None]
    if ids:
        db.academic_notices.delete_many({"id": {"$in": ids}})


def _unlink_upload(path: str | None) -> None:
    if not path or not isinstance(path, str):
        return
    name = Path(path).name
    if not name or name in (".", ".."):
        return
    p = UPLOADS_DIR / name
    if p.exists() and p.is_file():
        p.unlink()


def _render_pdf_first_page_thumbnail(pdf_path: Path, *, max_edge_px: int = PDF_THUMB_MAX_PX) -> str | None:
    """Render the first page of [pdf_path] to a PNG and return its `/uploads/...` URL."""
    try:
        import pypdfium2 as pdfium  # imported lazily so the API still boots if the lib is missing
    except Exception:  # pragma: no cover
        logger.warning("pypdfium2 not available; skipping PDF thumbnail generation.")
        return None
    try:
        pdf = pdfium.PdfDocument(str(pdf_path))
        if len(pdf) == 0:
            return None
        page = pdf[0]
        width, height = page.get_size()  # in points (1/72 inch)
        if width <= 0 or height <= 0:
            return None
        scale = max_edge_px / max(width, height)
        if scale <= 0:
            scale = 1.0
        bitmap = page.render(scale=scale)
        pil_image = bitmap.to_pil()
        thumb_name = f"{pdf_path.stem}_thumb.png"
        thumb_path = UPLOADS_DIR / thumb_name
        pil_image.save(thumb_path, format="PNG", optimize=True)
        return f"/uploads/{thumb_name}"
    except Exception as exc:  # pragma: no cover
        logger.warning("Failed to render PDF thumbnail for %s: %s", pdf_path, exc)
        return None


def _validate_link(raw: str | None) -> str | None:
    if not raw:
        return None
    s = raw.strip()
    if not s:
        return None
    low = s.lower()
    if not (low.startswith("http://") or low.startswith("https://")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Link URL must start with http:// or https://",
        )
    return s


@router.get("/")
def list_notices(
    db: Database = Depends(get_db),
    _: SimpleNamespace = Depends(get_current_user),
) -> list[dict]:
    _purge_expired_notices(db)
    cur = db.academic_notices.find({}).sort("created_at", -1)
    return [_serialize(doc) for doc in cur]


@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_notice(
    title: str = Form(...),
    body: str | None = Form(None),
    link_url: str | None = Form(None),
    expires_at: str | None = Form(None),
    file: UploadFile | None = File(None),
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> dict:
    assert_academic_shortcuts(manager)

    title_clean = (title or "").strip()
    if not title_clean:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Notice heading is required.",
        )

    body_clean = (body or "").strip() or None
    link_clean = _validate_link(link_url)
    expires_dt = _parse_optional_iso_datetime(expires_at)
    if expires_dt is not None and expires_dt <= datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expiry must be in the future.",
        )

    file_path: str | None = None
    file_kind: str | None = None
    file_thumbnail_path: str | None = None
    if file is not None and file.filename:
        suffix = Path(file.filename).suffix.lower()
        if suffix not in ALLOWED_SUFFIXES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported file type. Allowed: {', '.join(sorted(ALLOWED_SUFFIXES))}",
            )
        filename = f"{uuid4().hex}{suffix}"
        dest = UPLOADS_DIR / filename
        dest.write_bytes(await file.read())
        file_path = f"/uploads/{filename}"
        file_kind = "pdf" if suffix in PDF_SUFFIXES else "image"
        if file_kind == "pdf":
            file_thumbnail_path = _render_pdf_first_page_thumbnail(dest)

    if not body_clean and not link_clean and not file_path:
        # Title alone is enough; no extra validation needed.
        pass

    doc = {
        "id": next_sequence(db, "academic_notices"),
        "title": title_clean,
        "body": body_clean,
        "file_path": file_path,
        "file_kind": file_kind,
        "file_thumbnail_path": file_thumbnail_path,
        "link_url": link_clean,
        "created_at": datetime.now(timezone.utc),
        "created_by": int(manager.id),
        "created_by_name": str(getattr(manager, "name", None) or getattr(manager, "email", "") or ""),
        "expires_at": expires_dt,
    }
    db.academic_notices.insert_one(doc)

    insert_notifications_for_users(
        db,
        student_ids(db),
        title="New academic notice",
        body=title_clean,
        priority="normal",
        kind="update",
        source_role=str(manager.role),
        route="/dashboard",
        notification_type="academic",
    )

    return _serialize(doc)


@router.delete("/{notice_id}")
def delete_notice(
    notice_id: int,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> dict:
    assert_academic_shortcuts(manager)
    doc = db.academic_notices.find_one({"id": int(notice_id)})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notice not found")
    role = getattr(manager, "role", None) or ""
    if role != "admin":
        creator = doc.get("created_by")
        try:
            if creator is None or int(creator) != int(manager.id):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Only the notice author or a campus administrator can delete this.",
                )
        except (TypeError, ValueError) as exc:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the notice author or a campus administrator can delete this.",
            ) from exc

    _unlink_upload(doc.get("file_path"))
    _unlink_upload(doc.get("file_thumbnail_path"))
    db.academic_notices.delete_one({"id": int(notice_id)})
    return {"deleted": int(notice_id)}
