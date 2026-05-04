"""event auto remove after hours

Revision ID: 0006_event_auto_remove
Revises: 0005_event_poster
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0006_event_auto_remove"
down_revision = "0005_event_poster"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {col["name"] for col in inspector.get_columns("events")}
    if "auto_remove_after_hours" not in columns:
        op.add_column("events", sa.Column("auto_remove_after_hours", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {col["name"] for col in inspector.get_columns("events")}
    if "auto_remove_after_hours" in columns:
        op.drop_column("events", "auto_remove_after_hours")
