"""community members, post images, user profiles

Revision ID: 0007_community_profiles
Revises: 0006_event_auto_remove
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0007_community_profiles"
down_revision = "0006_event_auto_remove"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    user_cols = {c["name"] for c in inspector.get_columns("users")}
    if "profile_image_path" not in user_cols:
        op.add_column("users", sa.Column("profile_image_path", sa.String(255), nullable=True))
    if "bio" not in user_cols:
        op.add_column("users", sa.Column("bio", sa.Text(), nullable=True))
    if "birth_date" not in user_cols:
        op.add_column("users", sa.Column("birth_date", sa.Date(), nullable=True))
    if "phone" not in user_cols:
        op.add_column("users", sa.Column("phone", sa.String(40), nullable=True))
    if "college_name" not in user_cols:
        op.add_column("users", sa.Column("college_name", sa.String(200), nullable=True))

    comm_cols = {c["name"] for c in inspector.get_columns("communities")}
    if "poster_path" not in comm_cols:
        op.add_column("communities", sa.Column("poster_path", sa.String(255), nullable=True))

    post_cols = {c["name"] for c in inspector.get_columns("community_posts")}
    if "image_path" not in post_cols:
        op.add_column("community_posts", sa.Column("image_path", sa.String(255), nullable=True))

    tables = inspector.get_table_names()
    if "community_members" not in tables:
        op.create_table(
            "community_members",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("community_id", sa.Integer(), sa.ForeignKey("communities.id"), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("joined_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.UniqueConstraint("community_id", "user_id", name="uq_community_user"),
        )
        op.create_index("ix_community_members_community_id", "community_members", ["community_id"])
        op.create_index("ix_community_members_user_id", "community_members", ["user_id"])

    if "community_post_replies" not in tables:
        op.create_table(
            "community_post_replies",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("post_id", sa.Integer(), sa.ForeignKey("community_posts.id"), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("message", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_community_post_replies_post_id", "community_post_replies", ["post_id"])


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = inspector.get_table_names()
    if "community_post_replies" in tables:
        op.drop_table("community_post_replies")
    if "community_members" in tables:
        op.drop_table("community_members")

    post_cols = {c["name"] for c in inspector.get_columns("community_posts")}
    if "image_path" in post_cols:
        op.drop_column("community_posts", "image_path")

    comm_cols = {c["name"] for c in inspector.get_columns("communities")}
    if "poster_path" in comm_cols:
        op.drop_column("communities", "poster_path")

    user_cols = {c["name"] for c in inspector.get_columns("users")}
    for col in ("college_name", "phone", "birth_date", "bio", "profile_image_path"):
        if col in user_cols:
            op.drop_column("users", col)
