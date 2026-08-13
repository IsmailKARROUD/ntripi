"""
constants/push_i18n.py — Rendered push text, per language.

WHY THIS EXISTS AT ALL, given that notification rows deliberately store no
rendered sentence: the OS draws a tray notification before any of our code
runs, so there is nobody left to render it client-side. The text here is
built at send time and thrown away — the `notifications` table still stores
only the structured reference, so nothing about that invariant changes.

Every string is copied VERBATIM from the Flutter app's .arb files (keys
`notificationFollowRequest`, `notificationRated`, …) so a tray notification
and the feed row it corresponds to read identically. If you reword one, reword
the other in the same commit or the two drift apart silently.

Fallback is the same double fallback as legal.document(): unknown language →
English, missing key in a known language → English.
"""

from app.i18n import SUPPORTED

# The wording the feed uses. `{name}` is the actor's display name (or the
# localised "Someone" when moderation hid it / the account is gone); `{title}`
# is the itinerary title.
#
# Arabic and Chinese put the actor where interpolation cannot be reordered,
# which is exactly why these are whole sentences per language rather than a
# shared template with a substituted verb.
_STRINGS: dict[str, dict[str, str]] = {
    "en": {
        "someone": "Someone",
        "follow_request": "{name} asked to follow you",
        "new_follower": "{name} started following you",
        "follow_accepted": "{name} accepted your follow request",
        "itinerary_rated": "{name} rated one of your itineraries",
        "itinerary_saved": "{name} saved one of your itineraries",
        "hidden": "“{title}” was hidden",
        "hidden_untitled": "One of your itineraries was hidden",
        "removed": "“{title}” was removed",
        "removed_untitled": "One of your itineraries was removed",
        "warned": "You've received a moderation warning",
        "warned_detail": "Tap to see why and to appeal",
        "tap_for_details": "Tap for details and to appeal",
        "generic": "You have a new notification.",
    },
    "fr": {
        "someone": "Quelqu'un",
        "follow_request": "{name} demande à vous suivre",
        "new_follower": "{name} s'est abonné(e) à vous",
        "follow_accepted": "{name} a accepté votre demande d'abonnement",
        "itinerary_rated": "{name} a noté l'un de vos itinéraires",
        "itinerary_saved": "{name} a enregistré l'un de vos itinéraires",
        "hidden": "« {title} » a été masqué",
        "hidden_untitled": "L'un de vos itinéraires a été masqué",
        "removed": "« {title} » a été supprimé",
        "removed_untitled": "L'un de vos itinéraires a été supprimé",
        "warned": "Vous avez reçu un avertissement de modération",
        "warned_detail": "Appuyez pour voir pourquoi et faire appel",
        "tap_for_details": "Appuyez pour en savoir plus et faire appel",
        "generic": "Vous avez une nouvelle notification.",
    },
    "ar": {
        "someone": "شخص ما",
        "follow_request": "طلب {name} متابعتك",
        "new_follower": "بدأ {name} بمتابعتك",
        "follow_accepted": "قبل {name} طلب متابعتك",
        "itinerary_rated": "قيّم {name} أحد مسارات رحلاتك",
        "itinerary_saved": "حفظ {name} أحد مسارات رحلاتك",
        "hidden": "تم إخفاء «{title}»",
        "hidden_untitled": "تم إخفاء أحد مسارات رحلاتك",
        "removed": "تمت إزالة «{title}»",
        "removed_untitled": "تمت إزالة أحد مسارات رحلاتك",
        "warned": "لقد تلقيت تحذيرًا من الإشراف",
        "warned_detail": "اضغط لمعرفة السبب ولتقديم تظلّم",
        "tap_for_details": "اضغط للتفاصيل ولتقديم تظلّم",
        "generic": "لديك إشعار جديد.",
    },
    "de": {
        "someone": "Jemand",
        "follow_request": "{name} möchte dir folgen",
        "new_follower": "{name} folgt dir jetzt",
        "follow_accepted": "{name} hat deine Follow-Anfrage angenommen",
        "itinerary_rated": "{name} hat eine deiner Reiserouten bewertet",
        "itinerary_saved": "{name} hat eine deiner Reiserouten gespeichert",
        "hidden": "„{title}“ wurde ausgeblendet",
        "hidden_untitled": "Eine deiner Reiserouten wurde ausgeblendet",
        "removed": "„{title}“ wurde entfernt",
        "removed_untitled": "Eine deiner Reiserouten wurde entfernt",
        "warned": "Du hast eine Verwarnung der Moderation erhalten",
        "warned_detail": "Tippen, um den Grund zu sehen und Einspruch einzulegen",
        "tap_for_details": "Tippen für Details und Einspruch",
        "generic": "Du hast eine neue Benachrichtigung.",
    },
    "es": {
        "someone": "Alguien",
        "follow_request": "{name} quiere seguirte",
        "new_follower": "{name} empezó a seguirte",
        "follow_accepted": "{name} aceptó tu solicitud de seguimiento",
        "itinerary_rated": "{name} valoró uno de tus itinerarios",
        "itinerary_saved": "{name} guardó uno de tus itinerarios",
        "hidden": "«{title}» se ocultó",
        "hidden_untitled": "Uno de tus itinerarios se ocultó",
        "removed": "«{title}» se eliminó",
        "removed_untitled": "Uno de tus itinerarios se eliminó",
        "warned": "Has recibido una advertencia de moderación",
        "warned_detail": "Toca para ver por qué y apelar",
        "tap_for_details": "Toca para ver los detalles y apelar",
        "generic": "Tienes una notificación nueva.",
    },
    "zh": {
        "someone": "某人",
        "follow_request": "{name} 请求关注你",
        "new_follower": "{name} 关注了你",
        "follow_accepted": "{name} 接受了你的关注请求",
        "itinerary_rated": "{name} 评价了你的一条行程",
        "itinerary_saved": "{name} 收藏了你的一条行程",
        "hidden": "“{title}”已被隐藏",
        "hidden_untitled": "你的一条行程已被隐藏",
        "removed": "“{title}”已被移除",
        "removed_untitled": "你的一条行程已被移除",
        "warned": "你收到了一条审核警告",
        "warned_detail": "点击查看原因并申诉",
        "tap_for_details": "点击查看详情并申诉",
        "generic": "你有一条新通知。",
    },
}


def normalize(locale: str | None) -> str:
    """Best-effort language code. Accepts "fr", "fr-FR", "fr_CA" and junk."""
    if not locale:
        return "en"
    primary = locale.replace("_", "-").split("-")[0].strip().lower()
    return primary if primary in SUPPORTED else "en"


def text(lang: str, key: str) -> str:
    """One string, English-fallback twice over — unknown language, and a key
    missing from an otherwise known language."""
    table = _STRINGS.get(lang) or _STRINGS["en"]
    return table.get(key) or _STRINGS["en"].get(key, "")


def render(
    *,
    type: str,
    subtype: str | None,
    actor_name: str | None,
    entity_title: str | None,
    locale: str | None,
) -> tuple[str, str | None]:
    """`(title, body)` for the tray. Body may be None — a title-only
    notification renders correctly on both platforms.

    Mirrors AppNotification.title()/subtitle() in the Flutter client; the
    branch order in the moderation case is load-bearing there and here.
    """
    lang = normalize(locale)
    name = actor_name or text(lang, "someone")

    if type == "moderation_action":
        return _moderation(lang, subtype, entity_title)

    if type in ("follow_request", "new_follower", "follow_accepted"):
        return text(lang, type).format(name=name), None

    if type in ("itinerary_rated", "itinerary_saved"):
        # The itinerary is the recipient's own, so naming it leaks nothing.
        return text(lang, type).format(name=name), entity_title

    # Unknown type: a newer backend must never produce an empty tray entry.
    return text(lang, "generic"), None


def _moderation(
    lang: str, subtype: str | None, entity_title: str | None
) -> tuple[str, str | None]:
    """Moderation text carries NO reason and NO reporter — the same rule that
    keeps actor_id null on these rows. Everything actionable is behind the tap,
    on /settings/account-status, where the appeal button lives."""
    # Checked before the hide fallthrough or a warning reads as a takedown.
    if subtype == "warn":
        return text(lang, "warned"), text(lang, "warned_detail")

    # 'delete' is the operator's hard removal; the rest of the family is a
    # hide, which is provisional and appealable.
    stem = "removed" if subtype == "delete" else "hidden"
    if entity_title:
        title = text(lang, stem).format(title=entity_title)
    else:
        title = text(lang, f"{stem}_untitled")
    return title, text(lang, "tap_for_details")
