from types import SimpleNamespace

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from pymongo.database import Database

from app.core.config import get_settings
from app.db.mongo import get_db
from app.db.mongo_docs import public_user_fields

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Database = Depends(get_db),
) -> SimpleNamespace:
    settings = get_settings()
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
    )
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        email = payload.get("sub")
        if not email:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    user_doc = db.users.find_one({"email": email})
    if not user_doc:
        raise credentials_exception
    if not user_doc.get("is_active", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account has been deactivated. Contact campus IT.",
        )
    clean = public_user_fields(user_doc)
    if not clean:
        raise credentials_exception
    return SimpleNamespace(**clean)


def require_admin(current_user: SimpleNamespace = Depends(get_current_user)) -> SimpleNamespace:
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return current_user


def require_admin_or_faculty(current_user: SimpleNamespace = Depends(get_current_user)) -> SimpleNamespace:
    if current_user.role not in {"admin", "faculty"}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin or faculty access required")
    return current_user
