"""
schemas/device.py — register / unregister an FCM device token.

Only a request schema: both endpoints answer 204. There is nothing to tell the
client about its own token that it did not just send us, and returning the row
would put a delivery address in a response body for no reason.
"""

from pydantic import BaseModel, Field

# Same values as models.device_token.DEVICE_PLATFORMS. A `pattern` rather than
# a Literal, per the project rule: switching to Literal changes the 422 body,
# and the validation-error shape is part of the API contract.
_PLATFORM = r"^(ios|android)$"


class DeviceRegisterRequest(BaseModel):
    # No max_length: FCM documents no maximum token length and has grown them
    # before. min_length rejects the empty string a failed getToken() yields.
    token: str = Field(min_length=1)
    platform: str = Field(pattern=_PLATFORM)
    # The language to render this device's push text in. Accepts "fr" or
    # "fr-CA"; push_i18n.normalize falls back to English for anything else, so
    # an unexpected value degrades rather than 422s.
    locale: str = Field(default="en", max_length=10)
