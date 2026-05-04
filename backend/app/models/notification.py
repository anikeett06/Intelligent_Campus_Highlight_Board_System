from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(140), nullable=False)
    body = Column(Text, nullable=False)
    priority = Column(String(20), default="normal")
    kind = Column(String(30), default="update")
    source_role = Column(String(20), default="system")
    is_read = Column(Boolean, default=False)
    route = Column(String(120), nullable=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="notifications")
