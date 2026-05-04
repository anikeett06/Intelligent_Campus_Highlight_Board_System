from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship

from app.db.base import Base


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(140), nullable=False)
    description = Column(Text, nullable=True)
    category = Column(String(50), nullable=False, default="general")
    priority = Column(String(20), nullable=False, default="normal")
    location = Column(String(140), nullable=True)
    poster_path = Column(String(255), nullable=True)
    exam_timetable_path = Column(String(255), nullable=True)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=False)
    auto_remove_after_hours = Column(Integer, nullable=False, default=0)
    allow_registration = Column(Boolean, default=True)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)

    creator = relationship("User", back_populates="events")
    registrations = relationship("Registration", back_populates="event", cascade="all,delete")
