from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class Registration(Base):
    __tablename__ = "registrations"
    __table_args__ = (UniqueConstraint("user_id", "event_id", name="uq_user_event"),)

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False)
    registered_at = Column(DateTime(timezone=True), server_default=func.now())
    participant_name = Column(String(120), nullable=True)
    roll_no = Column(String(40), nullable=True)
    branch = Column(String(80), nullable=True)
    college_name = Column(String(160), nullable=True)
    phone = Column(String(20), nullable=True)
    email = Column(String(120), nullable=True)

    user = relationship("User", back_populates="registrations")
    event = relationship("Event", back_populates="registrations")
