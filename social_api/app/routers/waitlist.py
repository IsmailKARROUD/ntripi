"""
routers/waitlist.py — Pre-launch waitlist for iOS/Android app.

POST /waitlist/join accepts an email and/or WhatsApp number.
At least one contact field is required.
Duplicate emails are treated as success (idempotent).
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.waitlist import WaitlistEntry

router = APIRouter(tags=["Waitlist"])


class WaitlistJoinBody(BaseModel):
    email: EmailStr | None = None
    whatsapp: str | None = None
    platform: Literal["ios", "android", "both"] = "both"

    @field_validator("whatsapp")
    @classmethod
    def strip_whatsapp(cls, v: str | None) -> str | None:
        return v.strip() if v else None

    @field_validator("email")
    @classmethod
    def lowercase_email(cls, v: EmailStr | None) -> str | None:
        return v.lower() if v else None


@router.post("/waitlist/join", status_code=201)
def join_waitlist(
    body: WaitlistJoinBody,
    db: Session = Depends(get_db),
) -> dict:
    if not body.email and not body.whatsapp:
        raise HTTPException(
            status_code=422,
            detail="Provide at least an email or a WhatsApp number.",
        )

    entry = WaitlistEntry(
        email=body.email,
        whatsapp=body.whatsapp,
        platform=body.platform,
    )
    db.add(entry)
    try:
        db.commit()
    except IntegrityError:
        # Duplicate email — treat as success so the caller shows the same confirmation.
        db.rollback()

    return {"ok": True}
