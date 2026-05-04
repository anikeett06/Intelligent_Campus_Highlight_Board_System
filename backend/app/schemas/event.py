from datetime import datetime

from typing import Literal

from pydantic import BaseModel

from app.schemas.common import ORMModel


class EventCreate(BaseModel):
    title: str
    description: str | None = None
    category: str = "general"
    priority: str = "normal"
    location: str | None = None
    start_time: datetime
    end_time: datetime
    auto_remove_after_hours: int = 0
    allow_registration: bool = True
    dashboard_segment: Literal["academic", "non_academic"] = "non_academic"
    show_description: bool = True
    show_location: bool = True
    show_registration_section: bool = True
    show_polls_section: bool = True
    show_announcements_section: bool = True
    custom_link_label: str | None = None
    custom_link_url: str | None = None
    fest_name: str | None = None
    team_format: str | None = None
    entry_fee: str | None = None
    prize_summary: str | None = None
    show_category_badge: bool = True
    editor_section_order: str | None = None
    show_in_dashboard: bool = True
    trending_highlight: bool = False
    dashboard_title: str | None = None
    dashboard_description: str | None = None
    event_page_json: str | None = None
    event_page_background_kind: str = "none"
    event_page_background_color: str | None = None


class EventResponse(ORMModel):
    id: int
    title: str
    description: str | None
    category: str
    priority: str
    location: str | None
    poster_path: str | None
    exam_timetable_path: str | None
    start_time: datetime
    end_time: datetime
    auto_remove_after_hours: int
    allow_registration: bool
    created_by: int
    registration_count: int = 0
    dashboard_segment: str = "non_academic"
    show_description: bool = True
    show_location: bool = True
    show_registration_section: bool = True
    show_polls_section: bool = True
    show_announcements_section: bool = True
    custom_link_label: str | None = None
    custom_link_url: str | None = None
    fest_name: str | None = None
    team_format: str | None = None
    entry_fee: str | None = None
    prize_summary: str | None = None
    show_category_badge: bool = True
    editor_section_order: str | None = None
    show_in_dashboard: bool = True
    trending_highlight: bool = False
    dashboard_title: str | None = None
    dashboard_description: str | None = None
    event_page_json: str | None = None
    dashboard_carousel_poster_path: str | None = None
    event_page_background_kind: str = "none"
    event_page_background_color: str | None = None
    event_page_background_path: str | None = None
