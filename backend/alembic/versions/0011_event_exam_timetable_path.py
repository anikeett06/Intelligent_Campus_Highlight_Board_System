"""add exam timetable file path to events

Revision ID: 0011_event_exam_timetable_path
Revises: 0010_polls_module
Create Date: 2026-05-01 20:21:00.000000
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0011_event_exam_timetable_path"
down_revision: str | Sequence[str] | None = "0010_polls_module"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("events") as batch_op:
        batch_op.add_column(sa.Column("exam_timetable_path", sa.String(length=255), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("events") as batch_op:
        batch_op.drop_column("exam_timetable_path")
