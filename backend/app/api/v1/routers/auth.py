from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from app.api.deps import get_current_user, get_db
from app.core.security import create_access_token, get_password_hash, verify_password
from app.db.mongo import next_sequence
from app.db.mongo_docs import public_user_fields
from app.schemas.auth import TokenResponse, UserLogin, UserResponse, UserSignup

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=UserResponse)
def signup(payload: UserSignup, db: Database = Depends(get_db)) -> UserResponse:
    email = str(payload.email).strip().lower()
    if db.users.find_one({"email": email}):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    # Campus self-service: student or faculty. Admin accounts are created by the institution only.
    role = payload.role
    uid = next_sequence(db, "users")
    now = datetime.now(timezone.utc)
    doc = {
        "_id": uid,
        "id": uid,
        "full_name": payload.full_name,
        "email": email,
        "hashed_password": get_password_hash(payload.password),
        "role": role,
        "is_active": True,
        "created_at": now,
        "profile_image_path": None,
        "bio": None,
        "birth_date": None,
        "phone": None,
        "college_name": None,
        "student_admin": False,
        "academic_posting_allowed": False,
    }
    db.users.insert_one(doc)
    return UserResponse.model_validate(public_user_fields(doc) or {})


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, db: Database = Depends(get_db)) -> TokenResponse:
    email = str(payload.email).strip().lower()
    user_doc = db.users.find_one({"email": email})
    if not user_doc or not verify_password(payload.password, user_doc["hashed_password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    if not user_doc.get("is_active", True):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account has been deactivated. Contact campus IT.")
    token = create_access_token(user_doc["email"])
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
def me(current_user=Depends(get_current_user)) -> UserResponse:
    raw = dict(vars(current_user))
    return UserResponse.model_validate(public_user_fields(raw) or raw)
