"""registration participant fields

Revision ID: 0002_reg_participant
Revises: 0001_initial
Create Date: 2026-05-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0002_reg_participant"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("registrations", sa.Column("participant_name", sa.String(length=120), nullable=True))
    op.add_column("registrations", sa.Column("roll_no", sa.String(length=40), nullable=True))
    op.add_column("registrations", sa.Column("branch", sa.String(length=80), nullable=True))
    op.add_column("registrations", sa.Column("college_name", sa.String(length=160), nullable=True))
    op.add_column("registrations", sa.Column("phone", sa.String(length=20), nullable=True))
    op.add_column("registrations", sa.Column("email", sa.String(length=120), nullable=True))


def downgrade() -> None:
    op.drop_column("registrations", "email")
    op.drop_column("registrations", "phone")
    op.drop_column("registrations", "college_name")
    op.drop_column("registrations", "branch")
    op.drop_column("registrations", "roll_no")
    op.drop_column("registrations", "participant_name")
