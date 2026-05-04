"""lost found comments table

Revision ID: 0004_lost_found_comments
Revises: 0003_lost_found_image
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_lost_found_comments"
down_revision = "0003_lost_found_image"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "lost_found_comments" not in inspector.get_table_names():
        op.create_table(
            "lost_found_comments",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("item_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("finder_name", sa.String(length=120), nullable=False),
            sa.Column("contact", sa.String(length=120), nullable=True),
            sa.Column("message", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
            sa.ForeignKeyConstraint(["item_id"], ["lost_found.id"]),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
    index_names = {idx["name"] for idx in inspector.get_indexes("lost_found_comments")}
    idx_name = op.f("ix_lost_found_comments_id")
    if idx_name not in index_names:
        op.create_index(idx_name, "lost_found_comments", ["id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_lost_found_comments_id"), table_name="lost_found_comments")
    op.drop_table("lost_found_comments")
