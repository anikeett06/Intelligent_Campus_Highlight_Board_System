from collections import Counter
from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.services.campus_staff_permissions import assert_staff_dashboard_tools
from app.db.mongo import next_sequence
from app.schemas.poll import PollCreate, PollOptionResponse, PollResponse, PollUpdate, PollVotePayload
from app.services.notification_audience import student_ids
from app.services.notify_insert import insert_notifications_for_users

router = APIRouter(prefix="/polls", tags=["polls"])

POLL_ROUTE = "/events"


def _notify_students_poll(db: Database, *, title: str, body: str, source_role: str) -> None:
    insert_notifications_for_users(
        db,
        student_ids(db),
        title=title,
        body=body,
        priority="normal",
        kind="update",
        source_role=source_role,
        route=POLL_ROUTE,
        notification_type="dashboard",
    )


def _to_response(db: Database, poll: dict, current_user: SimpleNamespace) -> PollResponse:
    pid = poll["id"]
    options = list(db.poll_options.find({"poll_id": pid}).sort("id", 1))
    votes = list(db.poll_votes.find({"poll_id": pid}))
    counts = Counter(v["option_id"] for v in votes)
    my_vote = db.poll_votes.find_one({"poll_id": pid, "user_id": current_user.id})
    return PollResponse(
        id=poll["id"],
        question=poll["question"],
        description=poll.get("description"),
        is_active=poll.get("is_active", True),
        created_by=poll["created_by"],
        created_at=poll["created_at"],
        my_vote_option_id=my_vote["option_id"] if my_vote else None,
        options=[
            PollOptionResponse(
                id=o["id"],
                label=o["label"],
                votes_count=counts.get(o["id"], 0),
            )
            for o in options
        ],
    )


@router.get("/", response_model=list[PollResponse])
def list_polls(
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> list[PollResponse]:
    polls = list(db.polls.find({}).sort("created_at", -1))
    return [_to_response(db, p, current_user) for p in polls]


@router.post("/", response_model=PollResponse)
def create_poll(
    payload: PollCreate,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> PollResponse:
    assert_staff_dashboard_tools(current_user)
    pid = next_sequence(db, "polls")
    now = datetime.now(timezone.utc)
    poll_doc = {
        "_id": pid,
        "id": pid,
        "question": payload.question.strip(),
        "description": (payload.description or "").strip() or None,
        "is_active": payload.is_active,
        "created_by": current_user.id,
        "created_at": now,
    }
    db.polls.insert_one(poll_doc)
    opt_docs = []
    for opt in payload.options:
        label = opt.label.strip()
        if not label:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Poll option label cannot be empty")
        oid = next_sequence(db, "poll_options")
        opt_docs.append(
            {
                "_id": oid,
                "id": oid,
                "poll_id": pid,
                "label": label,
                "created_at": now,
            }
        )
    if opt_docs:
        db.poll_options.insert_many(opt_docs)
    q = poll_doc["question"]
    _notify_students_poll(
        db,
        title=f"New poll: {q}",
        body=poll_doc.get("description") or "Open Events to view and vote.",
        source_role=str(current_user.role),
    )
    return _to_response(db, poll_doc, current_user)


@router.put("/{poll_id}", response_model=PollResponse)
def update_poll(
    poll_id: int,
    payload: PollUpdate,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> PollResponse:
    assert_staff_dashboard_tools(current_user)
    poll = db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Poll not found")
    db.poll_votes.delete_many({"poll_id": poll_id})
    db.poll_options.delete_many({"poll_id": poll_id})

    now = datetime.now(timezone.utc)
    updated = {
        **poll,
        "question": payload.question.strip(),
        "description": (payload.description or "").strip() or None,
        "is_active": payload.is_active,
    }
    db.polls.replace_one({"id": poll_id}, updated)

    opt_docs = []
    for opt in payload.options:
        label = opt.label.strip()
        if not label:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Poll option label cannot be empty")
        oid = next_sequence(db, "poll_options")
        opt_docs.append(
            {
                "_id": oid,
                "id": oid,
                "poll_id": poll_id,
                "label": label,
                "created_at": now,
            }
        )
    if opt_docs:
        db.poll_options.insert_many(opt_docs)
    _notify_students_poll(
        db,
        title=f"Poll updated (votes reset): {updated['question']}",
        body="Options changed — please open Events and vote again if needed.",
        source_role=str(current_user.role),
    )
    return _to_response(db, updated, current_user)


@router.delete("/{poll_id}")
def delete_poll(
    poll_id: int,
    db: Database = Depends(get_db),
    manager: SimpleNamespace = Depends(get_current_user),
) -> dict[str, str]:
    assert_staff_dashboard_tools(manager)
    poll = db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Poll not found")
    db.poll_votes.delete_many({"poll_id": poll_id})
    db.poll_options.delete_many({"poll_id": poll_id})
    q = poll.get("question", "Poll")
    db.polls.delete_one({"id": poll_id})
    _notify_students_poll(
        db,
        title="Poll removed",
        body=f"This poll is no longer active: {q}",
        source_role=str(manager.role),
    )
    return {"message": "Poll deleted"}


@router.post("/{poll_id}/vote", response_model=PollResponse)
def vote_poll(
    poll_id: int,
    payload: PollVotePayload,
    db: Database = Depends(get_db),
    current_user: SimpleNamespace = Depends(get_current_user),
) -> PollResponse:
    poll = db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Poll not found")
    if not poll.get("is_active", True):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Poll is not active")
    option = db.poll_options.find_one({"id": payload.option_id, "poll_id": poll_id})
    if not option:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Option not found")
    existing = db.poll_votes.find_one({"poll_id": poll_id, "user_id": current_user.id})
    now = datetime.now(timezone.utc)
    if existing:
        db.poll_votes.update_one({"_id": existing["_id"]}, {"$set": {"option_id": payload.option_id, "created_at": now}})
    else:
        vid = next_sequence(db, "poll_votes")
        db.poll_votes.insert_one(
            {
                "_id": vid,
                "id": vid,
                "poll_id": poll_id,
                "option_id": payload.option_id,
                "user_id": current_user.id,
                "created_at": now,
            }
        )
    refreshed = db.polls.find_one({"id": poll_id})
    q = poll.get("question", "Poll")
    insert_notifications_for_users(
        db,
        [current_user.id],
        title="Vote recorded",
        body=f"{option['label']} — {q}",
        priority="normal",
        kind="update",
        source_role="student",
        route=POLL_ROUTE,
        notification_type="dashboard",
    )
    creator_id = int(poll.get("created_by", 0))
    voter_label = getattr(current_user, "full_name", None) or "A campus member"
    if creator_id and creator_id != current_user.id:
        insert_notifications_for_users(
            db,
            [creator_id],
            title="New vote on your poll",
            body=f"{voter_label} voted on: {q}",
            priority="low",
            kind="update",
            source_role=str(current_user.role),
            route=POLL_ROUTE,
            notification_type="dashboard",
        )
    return _to_response(db, refreshed or poll, current_user)
