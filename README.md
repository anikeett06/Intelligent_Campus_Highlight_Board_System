# Intelligent Campus Highlight Board System

Production-oriented mobile + backend system for centralized campus communication.

## Tech Stack
- Frontend: Flutter (`provider`, `go_router`, `dio`, `flutter_secure_storage`, `firebase_messaging`)
- Backend: FastAPI + JWT (MongoDB via PyMongo)
- Database: MongoDB Atlas or local MongoDB (`MONGODB_URI` in `backend/.env`)
- Push Notifications: Firebase Cloud Messaging (FCM)

## Tools Required
- Flutter SDK and Android Studio
- Python 3.11+ and pip
- Postman (or Insomnia) for API testing
- Firebase project + service account JSON (for push)

## Project Structure
- `lib/` Flutter app UI + API integration (screens under `lib/screens/`, router in `lib/app_router.dart`)
- `backend/` FastAPI service
  - `app/schemas` request/response contracts
  - `app/api/v1/routers` REST modules
  - `app/services` categorization and notifications
  - `scripts/seed_data.py` sample data (MongoDB)

## Run Backend
1. `cd backend`
2. `python -m venv .venv`
3. Windows: `.venv\\Scripts\\activate`
4. `pip install -r requirements.txt`
5. `copy .env.example .env` (only if you do not already have `.env`)
6. Edit `backend/.env`: set **`MONGODB_URI`** and **`MONGODB_DB_NAME`** (see `backend/.env.example`). For local dev, `MONGODB_URI=mongodb://127.0.0.1:27017` matches the Docker option below.
7. **MongoDB must be running** before `uvicorn`. If you see `WinError 10061` / “actively refused” on port 27017:
   - **Option A — Docker:** from the repo root, run `docker compose up -d`, wait a few seconds, then start the API.
   - **Option B — Install:** run MongoDB Community as a Windows service (or `mongod.exe`), or use **MongoDB Atlas** and put your Atlas URI in `MONGODB_URI`.
8. `python scripts\seed_data.py` (optional; demo users and sample content)
9. In `backend/.env`, set `CORS_ALLOW_ALL=true` for local testing (especially Flutter **web** in Chrome/Edge).
10. Start API (port `8010` matches the Flutter app defaults; use `--host 0.0.0.0` so phones on Wi‑Fi can reach your PC):
   - `uvicorn app.main:app --host 0.0.0.0 --port 8010 --reload`

Backend URLs:
- API docs: `http://127.0.0.1:8010/docs` (same port you chose)
- Health: `http://127.0.0.1:8010/health`

## Run Flutter App
1. `cd ..` (root folder)
2. `flutter pub get`
3. **Android emulator** (default in code: `http://10.0.2.2:8010/api/v1`): use backend on port `8010`, or set the API URL on the login screen / `--dart-define=API_BASE_URL=...`.
4. **Physical phone** (same Wi‑Fi as PC): bind backend with `--host 0.0.0.0`, find PC IPv4 (`ipconfig`), then either:
   - Open login → **Change server URL** → `http://<YOUR_PC_IP>:8010/api/v1` → **Save URL**, or  
   - `flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8010/api/v1`
5. **Flutter web**: run on `Chrome`/`Edge` with `API_BASE_URL=http://127.0.0.1:8010/api/v1` and keep `CORS_ALLOW_ALL=true` in backend `.env`.

## Troubleshooting login / network
| Symptom | Fix |
|--------|-----|
| `WinError 10013` on port 8000 | Use `--port 8010` (or another free port). |
| Phone cannot reach PC | Backend must use `--host 0.0.0.0`; use PC LAN IP in app, not `127.0.0.1`. |
| Web shows `OPTIONS ... 400` or XMLHttpRequest error | Add `CORS_ALLOW_ALL=true` to `backend/.env` and restart uvicorn. |
| Emulator vs phone wrong host | Emulator: `10.0.2.2`. Phone: your PC Wi‑Fi IP. Use **Change server URL** on the login screen (saved on device). |
| Login **401** after switching to MongoDB Atlas | Run `python scripts/seed_data.py` from `backend/` (creates demo users). Student password is **`Student@123`** (capital **S**). |

## Demo accounts (run `python scripts/seed_data.py` in `backend/` first)

| Role | Email | Password | In-app use |
|------|-------|----------|------------|
| **Student** | `student@campus.edu` | `Student@123` (capital **S**) | Dashboard, events, follow clubs, notifications, lost & found |
| **Faculty** | `faculty@campus.edu` | `Faculty@123` | Same as student visibility, plus create/edit **dashboard activities**, **campus shortcut** uploads, **club announcements**, **community posts**, **polls** (staff / **club lead** flows use this role) |
| **Admin** | `admin@campus.edu` | `Admin@123` | Everything faculty can do, plus **broadcast notices**, **user directory**, stricter admin routes |

**Club heads** are modeled as **faculty** or **admin** in this codebase (no separate role): they manage clubs with `require_admin_or_faculty`. Students **follow** clubs for updates instead of self-joining.

**Sign up** in the app always creates a **student** account. Admin and faculty accounts must be added via seed or your institution’s provisioning.

## API Modules Implemented
- Auth: signup, login, me
- Users: list (admin), update profile
- Events: CRUD-lite create/list/detail, register/unregister, grouped dashboard
- Notifications: create/list/mark-read
- Communities: create/list + posts
- Lost & Found: create/list/update status
- Device Tokens: register/remove for FCM

## Optional Advanced Structure Included
- Email parsing and AI categorization hooks planned via services layer extension points
- Admin analytics can be added as new router + dashboard widgets without changing core architecture
