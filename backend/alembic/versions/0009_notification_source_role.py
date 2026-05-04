"""add notification source_role field

Revision ID: 0009_notification_source_role
Revises: 0008_notification_kind
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0009_notification_source_role"
down_revision = "0008_notification_kind"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns("notifications")}
    if "source_role" not in cols:
        op.add_column(
            "notifications",
            sa.Column("source_role", sa.String(length=20), nullable=False, server_default="system"),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns("notifications")}
    if "source_role" in cols:
        op.drop_column("notifications", "source_role")
