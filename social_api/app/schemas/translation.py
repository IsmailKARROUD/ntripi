"""
schemas/translation.py — POST /translations and GET /translations/config.

The client names content, never sends text: the server loads the text itself,
so a reader can only ever have translated what they are allowed to read.
"""

import uuid
from typing import Optional

from pydantic import BaseModel, Field, model_validator

from app.models.content_translation import TRANSLATION_CONTENT_TYPES
from app.services.translation_service import REGISTRY

# pattern=, not Literal: the 422 body stays the shape every other endpoint gives.
_CONTENT_TYPE_PATTERN = f"^({'|'.join(TRANSLATION_CONTENT_TYPES)})$"
_FIELDS_BY_TYPE = {spec.content_type: spec.fields for spec in REGISTRY}

# One request covers a trip header with its notes, or a stop with its
# annotations — never a whole catalogue.
MAX_ITEMS_PER_REQUEST = 50


class TranslationItemIn(BaseModel):
    content_type: str = Field(..., pattern=_CONTENT_TYPE_PATTERN)
    content_id: uuid.UUID
    fields: list[str] = Field(..., min_length=1, max_length=3)

    @model_validator(mode="after")
    def _fields_belong_to_the_type(self) -> "TranslationItemIn":
        allowed = _FIELDS_BY_TYPE[self.content_type]
        unknown = [name for name in self.fields if name not in allowed]
        if unknown:
            raise ValueError(
                f"{self.content_type} has no translatable field {', '.join(unknown)}; "
                f"expected {', '.join(allowed)}"
            )
        return self


class TranslationRequest(BaseModel):
    # Shape only; whether the language is offered is a policy answer (400).
    target_lang: str = Field(..., pattern=r"^[a-z]{2}$")
    items: list[TranslationItemIn] = Field(..., min_length=1, max_length=MAX_ITEMS_PER_REQUEST)


class FieldTranslationOut(BaseModel):
    # translated | same_language | empty | unavailable | rate_limited
    status: str
    text: Optional[str] = None
    provider: Optional[str] = None
    source_lang: Optional[str] = None


class TranslationItemOut(BaseModel):
    content_type: str
    content_id: uuid.UUID
    status: str  # ok | not_found
    fields: dict[str, FieldTranslationOut] = {}


class TranslationResponse(BaseModel):
    target_lang: str
    items: list[TranslationItemOut]


class TranslationConfigResponse(BaseModel):
    enabled: bool
    target_langs: list[str]
