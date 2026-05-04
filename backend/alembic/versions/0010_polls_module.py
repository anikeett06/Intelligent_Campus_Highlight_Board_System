"""add polls and voting tables

Revision ID: 0010_polls_module
Revises: 0009_notification_source_role
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0010_polls_module"
down_revision = "0009_notification_source_role"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = inspector.get_table_names()

    if "polls" not in tables:
        op.create_table(
            "polls",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("question", sa.String(length=255), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_polls_id", "polls", ["id"])

    if "poll_options" not in tables:
        op.create_table(
            "poll_options",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("poll_id", sa.Integer(), sa.ForeignKey("polls.id"), nullable=False),
            sa.Column("label", sa.String(length=160), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_poll_options_id", "poll_options", ["id"])

    if "poll_votes" not in tables:
        op.create_table(
            "poll_votes",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("poll_id", sa.Integer(), sa.ForeignKey("polls.id"), nullable=False),
            sa.Column("option_id", sa.Integer(), sa.ForeignKey("poll_options.id"), nullable=False),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.UniqueConstraint("poll_id", "user_id", name="uq_poll_user_vote"),
        )
        op.create_index("ix_poll_votes_id", "poll_votes", ["id"])


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = inspector.get_table_names()
    if "poll_votes" in tables:
        op.drop_table("poll_votes")
    if "poll_options" in tables:
        op.drop_table("poll_options")
    if "polls" in tables:
        op.drop_table("polls")
