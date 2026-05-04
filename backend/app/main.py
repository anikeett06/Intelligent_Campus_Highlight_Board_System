from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pymongo.errors import AutoReconnect, ConfigurationError, OperationFailure, ServerSelectionTimeoutError

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.mongo import close_mongo_client, ensure_indexes, get_database
from app.services.notification_service import init_firebase

settings = get_settings()
app = FastAPI(title=settings.app_name)
uploads_dir = Path(__file__).resolve().parents[1] / "uploads"
uploads_dir.mkdir(parents=True, exist_ok=True)

if settings.cors_allow_all:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_origin_regex=settings.cors_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


def _mongodb_startup_hint(exc: BaseException) -> str:
    """Context-specific hints; the URI scheme alone does not imply DNS vs TLS failure."""
    msg = str(exc).lower()
    uri = get_settings().mongodb_uri.strip().lower()
    parts: list[str] = []

    if any(s in msg for s in ("ssl handshake", "tlsv1 alert", "tls alert", "certificate", "handshake failed")):
        parts.append(
            " TLS handshake to Atlas failed (often Windows + Python 3.13 + OpenSSL). "
            "For local dev only, set MONGODB_TLS_INSECURE=true in backend/.env, or use Python 3.11/3.12 in this venv, "
            "or MONGODB_URI=mongodb://127.0.0.1:27017. See backend/README.md (Atlas TLS on Windows)."
        )
    if "mongodb+srv://" in uri and any(
        s in msg for s in ("lifetime", "resolution", "dns", "srv", "could not contact dns")
    ):
        parts.append(
            " mongodb+srv:// needs DNS SRV lookups. If that was the issue, use Atlas standard mongodb://host:27017,... "
            "or local MongoDB."
        )
    if "mongodb+srv://" in uri and not parts:
        parts.append(
            " Check MONGODB_URI, network/VPN, and Atlas IP allowlist. For DNS-only failures, prefer Atlas standard URI."
        )
    if any(
        s in msg
        for s in (
            "actively refused",
            "10061",
            "10054",
            "connection refused",
            "forcibly closed",
            "autoreconnect",
        )
    ):
        parts.append(
            " Local MongoDB is not accepting connections (mongod not running, wrong port, or it restarted). "
            "Start MongoDB on this machine (default port 27017), or set MONGODB_URI in backend/.env to MongoDB Atlas / another host. "
            "See README.md and backend/README.md."
        )
    return "".join(parts)


def _is_mongo_bad_auth(exc: OperationFailure) -> bool:
    msg = str(exc).lower()
    return "authentication failed" in msg or "bad auth" in msg


@app.on_event("startup")
def on_startup() -> None:
    try:
        db = get_database()
        ensure_indexes(db)
    except OperationFailure as exc:
        if _is_mongo_bad_auth(exc):
            raise RuntimeError(
                "MongoDB authentication failed (Atlas rejected the database user or password in MONGODB_URI). "
                "Fix: Atlas → Database Access → confirm the user name and reset the password if needed. "
                "In the URI, URL-encode any special characters in the password (e.g. @ → %40, : → %3A, / → %2F, # → %23, ? → %3F). "
                "Use the user shown in the connection string, not necessarily your Atlas account email. "
                f"Original error: {exc}"
            ) from exc
        raise
    except (ConfigurationError, ServerSelectionTimeoutError, AutoReconnect) as exc:
        raise RuntimeError(
            f"MongoDB could not be reached.{_mongodb_startup_hint(exc)} "
            f"Original error: {exc}"
        ) from exc
    init_firebase()


@app.on_event("shutdown")
def on_shutdown() -> None:
    close_mongo_client()


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    return {"status": "ok", "database": get_settings().mongodb_db_name}


app.include_router(api_router, prefix=settings.api_v1_prefix)
app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")
