"""
routers/translations.py — reading user content in your own language.

GET  /translations/config — whether translation is on, and into which languages
POST /translations        — translate named content for the signed-in reader

Sign-in is required for both: the app reads nothing anonymously, and the share
page stays in the original language. With TRANSLATION_PROVIDERS unset the POST
404s — the feature is invisible, not merely locked — and the config says so, so
the client never offers the button.

Sync `def` on purpose: the engines are blocking HTTP calls, which FastAPI runs
in its threadpool (the same reasoning as text moderation).
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.dependencies import get_current_user
from app.errors import ApiError
from app.limiter import limiter
from app.models.user import User
from app.schemas.translation import (
    FieldTranslationOut,
    TranslationConfigResponse,
    TranslationItemOut,
    TranslationRequest,
    TranslationResponse,
)
from app.services import translation_service

router = APIRouter(prefix="/translations", tags=["Translations"])


@router.get("/config", response_model=TranslationConfigResponse,
            summary="Whether translation is available, and into which languages")
def translation_config(
    _user: User = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> TranslationConfigResponse:
    enabled = settings.translation_enabled
    return TranslationConfigResponse(
        enabled=enabled,
        target_langs=settings.translation_supported_langs if enabled else [],
    )


@router.post("", response_model=TranslationResponse,
             summary="Translate content the reader can see into their language")
@limiter.limit("60/minute")
def translate(
    request: Request,  # required first positional for slowapi rate limiting
    body: TranslationRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> TranslationResponse:
    if not settings.translation_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")
    if body.target_lang not in settings.translation_supported_langs:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="translation_language_unsupported",
            detail="Translation into this language is not supported.",
        )

    results = translation_service.translate_items(
        db, settings, current_user.id, body.target_lang,
        [
            translation_service.ItemRequest(
                content_type=item.content_type,
                content_id=item.content_id,
                fields=tuple(item.fields),
            )
            for item in body.items
        ],
    )
    return TranslationResponse(
        target_lang=body.target_lang,
        items=[
            TranslationItemOut(
                content_type=result.content_type,
                content_id=result.content_id,
                status=result.status,
                fields={
                    name: FieldTranslationOut(
                        status=field.status, text=field.text,
                        provider=field.provider, source_lang=field.source_lang,
                    )
                    for name, field in result.fields.items()
                },
            )
            for result in results
        ],
    )
