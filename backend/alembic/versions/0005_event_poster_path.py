"""event poster path

Revision ID: 0005_event_poster
Revises: 0004_lost_found_comments
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0005_event_poster"
down_revision = "0004_lost_found_comments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {col["name"] for col in inspector.get_columns("events")}
    if "poster_path" not in columns:
        op.add_column("events", sa.Column("poster_path", sa.String(length=255), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {col["name"] for col in inspector.get_columns("events")}
    if "poster_path" in columns:
        op.drop_column("events", "poster_path")
