"""lost found image path

Revision ID: 0003_lost_found_image
Revises: 0002_reg_participant
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0003_lost_found_image"
down_revision = "0002_reg_participant"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("lost_found", sa.Column("image_path", sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column("lost_found", "image_path")
