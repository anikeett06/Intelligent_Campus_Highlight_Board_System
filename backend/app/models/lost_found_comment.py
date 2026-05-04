from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class LostFoundComment(Base):
    __tablename__ = "lost_found_comments"

    id = Column(Integer, primary_key=True, index=True)
    item_id = Column(Integer, ForeignKey("lost_found.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    finder_name = Column(String(120), nullable=False)
    contact = Column(String(120), nullable=True)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    item = relationship("LostFound", back_populates="comments")
    user = relationship("User", back_populates="lost_found_comments")
