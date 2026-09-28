"""Reject an explicit JSON null on a PATCH field whose column is NOT NULL.

The update schemas type these fields `Optional[...] = None` so that omitting one
means "leave it alone". `model_dump(exclude_unset=True)` keeps an explicit null,
though, and the router's setattr loop then hands None to a NOT NULL column — a
500 at commit instead of a 422 at the door.
"""

from pydantic import BaseModel


def reject_explicit_nulls(model: BaseModel, fields: tuple[str, ...]) -> BaseModel:
    """Raise if any of `fields` was sent, and sent as null. Returns `model`."""
    for name in fields:
        if name in model.model_fields_set and getattr(model, name) is None:
            raise ValueError(f"{name} cannot be null; omit it to leave it unchanged.")
    return model
