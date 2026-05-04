from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.db.base import Base


class Community(Base):
    __tablename__ = "communities"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), unique=True, nullable=False)
    description = Column(Text, nullable=True)
    poster_path = Column(String(255), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    posts = relationship("CommunityPost", back_populates="community", cascade="all,delete")
    members = relationship("CommunityMember", back_populates="community", cascade="all,delete")


class CommunityPost(Base):
    __tablename__ = "community_posts"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(140), nullable=False)
    content = Column(Text, nullable=False)
    image_path = Column(String(255), nullable=True)
    community_id = Column(Integer, ForeignKey("communities.id"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    community = relationship("Community", back_populates="posts")
    author = relationship("User", back_populates="community_posts")
    replies = relationship("CommunityPostReply", back_populates="post", cascade="all,delete-orphan")
