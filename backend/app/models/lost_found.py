from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class LostFound(Base):
    __tablename__ = "lost_found"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(140), nullable=False)
    description = Column(Text, nullable=False)
    location = Column(String(140), nullable=True)
    image_path = Column(String(255), nullable=True)
    is_found = Column(Boolean, default=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    author = relationship("User", back_populates="lost_found_posts")
    comments = relationship("LostFoundComment", back_populates="item", cascade="all, delete")
