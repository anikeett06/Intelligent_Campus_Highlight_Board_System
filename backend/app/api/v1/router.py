from fastapi import APIRouter

from app.api.v1.routers import academic_notices, auth, campus_shortcuts, clubs, communities, device_tokens, events, lost_found, notifications, polls, registrations, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(academic_notices.router)
api_router.include_router(campus_shortcuts.router)
api_router.include_router(events.router)
api_router.include_router(registrations.router)
api_router.include_router(notifications.router)
api_router.include_router(polls.router)
api_router.include_router(communities.router)
api_router.include_router(clubs.router)
api_router.include_router(clubs.announcements_router)
api_router.include_router(lost_found.router)
api_router.include_router(device_tokens.router)
api_router.include_router(users.router)
