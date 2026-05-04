"""add notification kind field

Revision ID: 0008_notification_kind
Revises: 0007_community_profiles
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0008_notification_kind"
down_revision = "0007_community_profiles"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns("notifications")}
    if "kind" not in cols:
        op.add_column(
            "notifications",
            sa.Column("kind", sa.String(length=30), nullable=False, server_default="update"),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns("notifications")}
    if "kind" in cols:
        op.drop_column("notifications", "kind")
