# Intelligent Campus Highlight Board Backend

## Stack

- FastAPI
- MongoDB (Atlas or local) via PyMongo
- JWT auth
- Firebase Admin SDK (FCM)

SQLite / SQLAlchemy / Alembic are **not** used at runtime anymore. The `alembic/` folder is legacy history only; set `DATABASE_URL` if you ever need to run old SQLite migrations.

## Setup

1. Create virtual environment:
   - `python -m venv .venv`
   - Windows: `.venv\Scripts\activate`
2. Install dependencies:
   - `pip install -r requirements.txt`
3. Copy environment:
   - `copy .env.example .env`
4. Configure MongoDB in `.env`:
   - `MONGODB_URI` — Atlas SRV string or `mongodb://127.0.0.1:27017`
   - `MONGODB_DB_NAME` — database name (e.g. `campus_board`)
   - **Nothing on 27017?** Startup will fail with `WinError 10061` / `ServerSelectionTimeoutError`. Either:
     - From the **repository root** (parent of `backend/`): `docker compose up -d` — starts Mongo 7 on `localhost:27017`, or
     - Install [MongoDB Community](https://www.mongodb.com/try/download/community) and run `mongod`, or
     - Use **MongoDB Atlas** and set `MONGODB_URI` to your cluster connection string.
   - In Atlas, allow your IP (or `0.0.0.0/0` for testing) under Network Access.
   - **Atlas TLS errors on Windows** (`TLSV1_ALERT_INTERNAL_ERROR`, `SSL handshake failed`): reinstall deps (`pip install -r requirements.txt`). The app uses **certifi** as the CA bundle for `mongodb+srv` / TLS URIs. If it still fails (e.g. corporate SSL inspection), set **`MONGODB_TLS_INSECURE=true`** in `.env` for local dev only, or use **Python 3.11/3.12** for the venv.
   - **DNS / SRV timeout** (`LifetimeTimeout`, `ConfigurationError` from PyMongo on startup): `mongodb+srv://` needs DNS that can resolve `_mongodb._tcp.<your-cluster-host>`. Fix by using Atlas’s **standard** `mongodb://host:27017,...` connection string (same UI, non-SRV option), fixing VPN/DNS, or pointing **`MONGODB_URI`** at **`mongodb://127.0.0.1:27017`** with a local `mongod`.
5. Seed sample data (optional, idempotent):
   - From this folder: `python scripts/seed_data.py`
6. For local Flutter **web**, set in `.env`: `CORS_ALLOW_ALL=true` (see `.env.example`).
7. Start server (use `--host 0.0.0.0` so a phone on Wi‑Fi can reach your PC; port `8010` avoids common Windows blocks):

   `uvicorn app.main:app --host 0.0.0.0 --port 8010 --reload`

API docs:

- Swagger: `http://127.0.0.1:8010/docs` (match your port)

## Dashboard activities

- Each event can set **`dashboard_segment`**: `academic` or `non_academic` (admin/faculty when creating or editing). This controls which home board lists the activity.
- **Campus shortcut files** (timetable, exam schedule, notices, programs): `GET /api/v1/campus-shortcuts/` (authenticated); `PUT /api/v1/campus-shortcuts/{slot}` with multipart field `file`; `DELETE /api/v1/campus-shortcuts/{slot}` removes the file for that slot (admin/faculty only). `slot` is one of `timetable`, `exam_schedule`, `notices`, `programs`.

## Demo credentials

(After `python scripts/seed_data.py`.)

- **Admin** — `admin@campus.edu` / `Admin@123` — full campus configuration, broadcasts, user admin.
- **Faculty** — `faculty@campus.edu` / `Faculty@123` — teaching staff and **club leads**: dashboard/event CRUD, campus shortcuts, club posts/announcements, polls. Seeded as a member of **Coding Club** so club screens work out of the box.
- **Student** — `student@campus.edu` / `Student@123` — follows clubs, registers for events, notifications.

**Auth:** `POST /auth/signup` always registers **`student`** accounts. Only seed/ops should create `faculty` / `admin`.

## FCM notes

- Set `FIREBASE_CREDENTIALS_PATH` in `.env` to your Firebase service account JSON file.
- Backend initializes Firebase at startup when that path exists.
