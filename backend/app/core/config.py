from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve .env next to the backend package (backend/.env) so Atlas/local URI works
# even when the process cwd is the repo root (e.g. `uvicorn app.main:app` from parent).
_BACKEND_ROOT = Path(__file__).resolve().parents[2]


def _env_file_paths() -> tuple[str, ...] | None:
    seen: set[str] = set()
    ordered: list[str] = []
    # Later files override earlier keys (pydantic-settings); backend/.env wins over cwd .env.
    for p in (Path(".env"), _BACKEND_ROOT / ".env"):
        if p.is_file():
            key = str(p.resolve())
            if key not in seen:
                seen.add(key)
                ordered.append(key)
    return tuple(ordered) if ordered else None


class Settings(BaseSettings):
    app_name: str = "Intelligent Campus Highlight Board API"
    api_v1_prefix: str = "/api/v1"
    secret_key: str = "change-this-in-production"
    access_token_expire_minutes: int = 1440
    # MongoDB Atlas or local: mongodb+srv://user:pass@cluster.mongodb.net/
    mongodb_uri: str = "mongodb://127.0.0.1:27017"
    mongodb_db_name: str = "campus_board"
    # Optional PEM path for TLS CA bundle. Leave unset to use certifi (recommended on Windows + Python 3.13 + Atlas).
    mongodb_tls_ca_file: str | None = None
    # Dev-only: if true, PyMongo uses tlsInsecure (relaxes TLS verification). Do not enable in production.
    mongodb_tls_insecure: bool = False
    cors_origins: str = "http://localhost:3000,http://localhost:5173"
    cors_origin_regex: str = r"https?://(localhost|127\.0\.0\.1)(:\d+)?"
    # Local dev only: set CORS_ALLOW_ALL=true in .env to allow any browser origin (JWT in header, not cookies).
    cors_allow_all: bool = False
    firebase_credentials_path: str | None = None

    model_config = SettingsConfigDict(
        env_file=_env_file_paths(),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def cors_origins_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
