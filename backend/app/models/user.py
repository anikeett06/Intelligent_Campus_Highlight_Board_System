from sqlalchemy import Boolean, Column, Date, DateTime, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(120), nullable=False)
    email = Column(String(120), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False, default="student")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    profile_image_path = Column(String(255), nullable=True)
    bio = Column(Text, nullable=True)
    birth_date = Column(Date, nullable=True)
    phone = Column(String(40), nullable=True)
    college_name = Column(String(200), nullable=True)

    events = relationship("Event", back_populates="creator")
    registrations = relationship("Registration", back_populates="user")
    notifications = relationship("Notification", back_populates="user")
    community_posts = relationship("CommunityPost", back_populates="author")
    community_memberships = relationship("CommunityMember", back_populates="user", cascade="all,delete")
    community_replies = relationship("CommunityPostReply", back_populates="user")
    lost_found_posts = relationship("LostFound", back_populates="author")
    lost_found_comments = relationship("LostFoundComment", back_populates="user")
    device_tokens = relationship("DeviceToken", back_populates="user")
