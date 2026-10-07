"""
constants/translation_languages.py — languages a reader may translate into.

For each ISO 639-1 code: the name the OpenAI prompt uses, and the code Azure
Translator expects (Simplified Chinese is `zh-Hans` there, not `zh`). A
language missing here cannot be put in TRANSLATION_SUPPORTED_LANGS — config
validation refuses it.

Kept in step with the app's locales (`kAppLocaleCodes`): a reader translates
into the language their app is in.
"""

TARGET_LANGUAGES: dict[str, tuple[str, str]] = {
    "en": ("English", "en"),
    "fr": ("French", "fr"),
    "es": ("Spanish", "es"),
    "de": ("German", "de"),
    "ar": ("Arabic", "ar"),
    "zh": ("Simplified Chinese", "zh-Hans"),
}
