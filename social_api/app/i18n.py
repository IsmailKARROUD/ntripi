"""i18n.py — Lightweight EN/FR translations for server-rendered web pages.

Stdlib only — no gettext catalogs or extra dependencies. Templates call the
`_('key')` global (injected via a context processor in templating.py) and read
`lang` for the <html lang> attribute and the language switcher.

Language resolution order: ?lang= query override → ntripi_lang cookie →
Accept-Language header (any `fr*` → French) → English default.
"""

from __future__ import annotations

from starlette.requests import Request

SUPPORTED = ("en", "fr")

# key -> {"en": ..., "fr": ...}. Only UI chrome and page copy — the privacy /
# ToS legal bodies stay English (see legal_en_only_notice).
TRANSLATIONS: dict[str, dict[str, str]] = {
    # ── Nav / footer chrome (_base.html) ──────────────────────────────────
    "nav_sign_in": {"en": "Sign in", "fr": "Se connecter"},
    "nav_sign_up": {"en": "Sign up", "fr": "S'inscrire"},
    "footer_privacy": {"en": "Privacy", "fr": "Confidentialité"},
    "footer_terms": {"en": "Terms", "fr": "Conditions"},
    "lang_switch_to": {"en": "Français", "fr": "English"},
    "meta_default_desc": {
        "en": "Travel itineraries, shared.",
        "fr": "Des itinéraires de voyage, partagés.",
    },
    # ── Login ─────────────────────────────────────────────────────────────
    "login_title": {"en": "Sign in — Ntripi", "fr": "Connexion — Ntripi"},
    "login_heading": {"en": "Sign in to Ntripi", "fr": "Connectez-vous à Ntripi"},
    "login_email_or_username": {
        "en": "Email or username",
        "fr": "E-mail ou nom d'utilisateur",
    },
    "login_password": {"en": "Password", "fr": "Mot de passe"},
    "login_submit": {"en": "Sign in", "fr": "Se connecter"},
    "login_new_prompt": {"en": "New to Ntripi?", "fr": "Nouveau sur Ntripi ?"},
    "login_create_account": {"en": "Create an account", "fr": "Créer un compte"},
    # ── Register ──────────────────────────────────────────────────────────
    "register_title": {"en": "Create account — Ntripi", "fr": "Créer un compte — Ntripi"},
    "register_heading": {
        "en": "Create your Ntripi account",
        "fr": "Créez votre compte Ntripi",
    },
    "register_email": {"en": "Email", "fr": "E-mail"},
    "register_username": {"en": "Username", "fr": "Identifiant"},
    "register_username_help": {
        "en": "4–30 chars: letters, numbers, periods, or underscores. Must start with a letter. Hyphens not allowed.",
        "fr": "4 à 30 caractères : lettres, chiffres, points ou tirets bas. Doit commencer par une lettre. Les tirets ne sont pas autorisés.",
    },
    "register_display_name": {"en": "Display name", "fr": "Nom affiché"},
    "register_optional": {"en": "(optional)", "fr": "(optionnel)"},
    "register_display_name_help": {
        "en": "How others see you. Any language, emoji. Defaults to your @username.",
        "fr": "Comment les autres vous voient. Toute langue, emoji. Par défaut, votre @identifiant.",
    },
    "register_password": {"en": "Password", "fr": "Mot de passe"},
    "register_password_help": {
        "en": "At least 8 characters, must include a digit.",
        "fr": "Au moins 8 caractères, avec au moins un chiffre.",
    },
    "register_confirm_password": {
        "en": "Confirm password",
        "fr": "Confirmer le mot de passe",
    },
    "register_agree_pre": {"en": "I agree to the", "fr": "J'accepte les"},
    "register_tos": {"en": "Terms of Service", "fr": "Conditions d'utilisation"},
    "register_agree_and": {"en": "and", "fr": "et la"},
    "register_privacy": {"en": "Privacy Policy", "fr": "Politique de confidentialité"},
    "register_submit": {"en": "Create account", "fr": "Créer un compte"},
    "register_have_account": {
        "en": "Already have an account?",
        "fr": "Vous avez déjà un compte ?",
    },
    # ── Password reset ────────────────────────────────────────────────────
    "reset_title": {"en": "Reset password — Ntripi", "fr": "Réinitialiser — Ntripi"},
    "reset_heading": {"en": "Set a new password", "fr": "Définir un nouveau mot de passe"},
    "reset_new_password": {"en": "New password", "fr": "Nouveau mot de passe"},
    "reset_password_placeholder": {
        "en": "At least 8 characters, one number",
        "fr": "Au moins 8 caractères, un chiffre",
    },
    "reset_confirm": {"en": "Confirm new password", "fr": "Confirmer le nouveau mot de passe"},
    "reset_submit": {"en": "Update password", "fr": "Mettre à jour le mot de passe"},
    "reset_done_heading": {"en": "Password updated", "fr": "Mot de passe mis à jour"},
    "reset_done_body": {
        "en": "Your password has been changed. You can now sign in with your new password.",
        "fr": "Votre mot de passe a été changé. Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.",
    },
    # ── Email verified / token invalid ────────────────────────────────────
    "email_verified_heading": {"en": "Email verified", "fr": "E-mail vérifié"},
    "email_verified_body": {
        "en": "Your email is verified. You can head back to the app.",
        "fr": "Votre e-mail est vérifié. Vous pouvez retourner dans l'application.",
    },
    "open_ntripi": {"en": "Open Ntripi", "fr": "Ouvrir Ntripi"},
    "token_invalid_heading": {"en": "Link no longer valid", "fr": "Lien expiré"},
    "token_invalid_body": {
        "en": "This link has expired or already been used.",
        "fr": "Ce lien a expiré ou a déjà été utilisé.",
    },
    # ── Share pages ───────────────────────────────────────────────────────
    "share_not_found_title": {
        "en": "Itinerary Not Found — Ntripi",
        "fr": "Itinéraire introuvable — Ntripi",
    },
    "share_not_found_heading": {"en": "Itinerary not found", "fr": "Itinéraire introuvable"},
    "share_not_found_body": {
        "en": "This itinerary is not available or may have been removed.",
        "fr": "Cet itinéraire n'est pas disponible ou a peut-être été supprimé.",
    },
    "share_go_to_ntripi": {"en": "Go to Ntripi", "fr": "Aller sur Ntripi"},
    "share_private_heading": {"en": "This itinerary is private", "fr": "Cet itinéraire est privé"},
    "share_private_body": {
        "en": "The owner has restricted who can view this itinerary.",
        "fr": "Le propriétaire a restreint l'accès à cet itinéraire.",
    },
    "share_by": {"en": "by", "fr": "par"},
    "share_stops": {"en": "stops", "fr": "étapes"},
    "share_open_in_app": {"en": "Open in Ntripi", "fr": "Ouvrir dans Ntripi"},
    "share_download": {"en": "Download the app", "fr": "Télécharger l'application"},
    "share_private_message": {
        "en": "This is a private itinerary. Open the Ntripi app to view the full trip.",
        "fr": "Cet itinéraire est privé. Ouvrez l'application Ntripi pour voir le voyage complet.",
    },
    "share_install_prompt": {"en": "Don't have Ntripi?", "fr": "Vous n'avez pas Ntripi ?"},
    "share_shared_via": {"en": "Shared via Ntripi", "fr": "Partagé via Ntripi"},
    "share_note_from_author": {"en": "Note from author", "fr": "Note de l'auteur"},
    "share_get_the_app": {"en": "Get the app", "fr": "Obtenir l'application"},
    "share_public_badge": {"en": "Public itinerary", "fr": "Itinéraire public"},
    "share_the_route": {"en": "The Route", "fr": "L'itinéraire"},
    "share_free": {"en": "Free", "fr": "Gratuit"},
    "share_plan_own": {"en": "Plan your own journey", "fr": "Planifiez votre propre voyage"},
    "share_plan_own_sub": {
        "en": "Open this itinerary in the Ntripi app, or download to start creating your own.",
        "fr": "Ouvrez cet itinéraire dans l'application Ntripi, ou téléchargez-la pour créer le vôtre.",
    },
    "share_open_in_app_short": {"en": "Open in app", "fr": "Ouvrir dans l'app"},
    "share_or_download": {"en": "or download", "fr": "ou télécharger"},
    "share_download_on": {"en": "Download on the", "fr": "Télécharger sur l'"},
    "share_get_it_on": {"en": "Get it on", "fr": "Disponible sur"},
    # ── Homepage ──────────────────────────────────────────────────────────
    "home_title": {
        "en": "Ntripi — Share your travel itineraries",
        "fr": "Ntripi — Partagez vos itinéraires de voyage",
    },
    "home_description": {
        "en": "Plan, share, and discover travel itineraries",
        "fr": "Planifiez, partagez et découvrez des itinéraires de voyage",
    },
    "home_coming_soon": {
        "en": "Coming soon on iOS & Android",
        "fr": "Bientôt sur iOS et Android",
    },
    "home_hero_title_1": {"en": "Plan. Share.", "fr": "Planifiez. Partagez."},
    "home_hero_title_2": {"en": "Discover.", "fr": "Découvrez."},
    "home_hero_sub": {
        "en": "Build travel itineraries with real stops, costs, and routes. Share what works. Discover trips that locals love.",
        "fr": "Créez des itinéraires de voyage avec de vraies étapes, coûts et parcours. Partagez ce qui fonctionne. Découvrez des voyages que les locaux adorent.",
    },
    "home_hero_have_account": {
        "en": "Already have an account?",
        "fr": "Vous avez déjà un compte ?",
    },
    "home_get_it_on": {"en": "Get it on", "fr": "Disponible sur"},
    "home_download_on": {"en": "Download on the", "fr": "Télécharger sur l'"},
    "home_features_label": {"en": "Everything you need", "fr": "Tout ce qu'il vous faut"},
    "home_features_title_pre": {"en": "Built for", "fr": "Conçu pour"},
    "home_features_title_em": {"en": "real travelers", "fr": "les vrais voyageurs"},
    "home_feat1_h": {"en": "Plan together", "fr": "Planifiez ensemble"},
    "home_feat1_p": {
        "en": "Build itineraries with stops, transit modes, costs, and personal notes. Everything in one place, easy to share.",
        "fr": "Créez des itinéraires avec étapes, modes de transport, coûts et notes personnelles. Tout au même endroit, facile à partager.",
    },
    "home_feat2_h": {"en": "Share anywhere", "fr": "Partagez partout"},
    "home_feat2_p": {
        "en": "Send a link to anyone. No install required — they can browse your full itinerary in any browser.",
        "fr": "Envoyez un lien à qui vous voulez. Aucune installation requise — chacun peut parcourir votre itinéraire complet dans son navigateur.",
    },
    "home_feat3_h": {"en": "Trust the community", "fr": "Faites confiance à la communauté"},
    "home_feat3_p": {
        "en": "Multi-dimensional ratings: safety, experience, accessibility, and family-friendliness — from people who've been there.",
        "fr": "Des évaluations multidimensionnelles : sécurité, expérience, accessibilité et adaptation aux familles — par ceux qui y sont allés.",
    },
    "home_feat4_h": {"en": "Explore the feed", "fr": "Explorez le fil"},
    "home_feat4_p": {
        "en": "Discover public itineraries shared by travelers worldwide. Follow explorers and get inspired for your next trip.",
        "fr": "Découvrez des itinéraires publics partagés par des voyageurs du monde entier. Suivez des explorateurs et inspirez-vous pour votre prochain voyage.",
    },
    "home_feat5_h": {"en": "Detailed stop info", "fr": "Détails de chaque étape"},
    "home_feat5_p": {
        "en": "Each stop includes location, cost, transport connections and custom notes — so nothing gets missed on the road.",
        "fr": "Chaque étape inclut lieu, coût, correspondances de transport et notes personnalisées — pour ne rien oublier en route.",
    },
    "home_feat6_h": {"en": "Follow & connect", "fr": "Suivez et connectez-vous"},
    "home_feat6_p": {
        "en": "Build a profile, follow fellow explorers, and grow your travel network — public or private, your choice.",
        "fr": "Créez un profil, suivez d'autres explorateurs et développez votre réseau de voyage — public ou privé, à vous de choisir.",
    },
    "home_how_label": {"en": "How it works", "fr": "Comment ça marche"},
    "home_how_title_pre": {"en": "Three steps to your next", "fr": "Trois étapes vers votre prochaine"},
    "home_how_title_em": {"en": "adventure", "fr": "aventure"},
    "home_step1_h": {"en": "Create an itinerary", "fr": "Créez un itinéraire"},
    "home_step1_p": {
        "en": "Add your stops, choose transport, set costs and notes for each leg of the journey.",
        "fr": "Ajoutez vos étapes, choisissez le transport, définissez les coûts et notes pour chaque tronçon du voyage.",
    },
    "home_step2_h": {"en": "Share with the world", "fr": "Partagez avec le monde"},
    "home_step2_p": {
        "en": "Make it public and let the community discover your route via the feed or a direct link.",
        "fr": "Rendez-le public et laissez la communauté découvrir votre parcours via le fil ou un lien direct.",
    },
    "home_step3_h": {"en": "Rate & improve", "fr": "Évaluez et améliorez"},
    "home_step3_p": {
        "en": "Travelers who follow your route leave multi-dimensional ratings so everyone benefits.",
        "fr": "Les voyageurs qui suivent votre parcours laissent des évaluations multidimensionnelles pour que tout le monde en profite.",
    },
    "home_ratings_title_pre": {"en": "Ratings that actually", "fr": "Des évaluations qui"},
    "home_ratings_title_em": {"en": "mean something", "fr": "veulent dire quelque chose"},
    "home_ratings_p": {
        "en": "We go beyond a single star. Every itinerary is rated across multiple dimensions so you always know what to expect before you go.",
        "fr": "Nous allons au-delà d'une simple étoile. Chaque itinéraire est évalué sur plusieurs dimensions pour que vous sachiez toujours à quoi vous attendre.",
    },
    "home_rating_overall": {"en": "Overall experience", "fr": "Expérience globale"},
    "home_rating_safety": {"en": "Safety", "fr": "Sécurité"},
    "home_rating_accessibility": {"en": "Accessibility", "fr": "Accessibilité"},
    "home_rating_family": {"en": "Family-friendly", "fr": "Adapté aux familles"},
    "home_cta_title": {"en": "Ready to explore?", "fr": "Prêt à explorer ?"},
    "home_cta_sub": {
        "en": "Download the app or jump straight into the web experience.",
        "fr": "Téléchargez l'application ou lancez-vous directement dans l'expérience web.",
    },
    "home_cta_download": {"en": "Download the App", "fr": "Télécharger l'application"},
    "home_cta_continue_web": {"en": "Continue on web", "fr": "Continuer sur le web"},
    # ── Waitlist modal ────────────────────────────────────────────────────
    "wl_title": {"en": "Be first to know", "fr": "Soyez informé en premier"},
    "wl_sub": {
        "en": "Leave your email or WhatsApp and we'll notify you the moment the app lands on your platform.",
        "fr": "Laissez votre e-mail ou WhatsApp et nous vous préviendrons dès que l'application arrive sur votre plateforme.",
    },
    "wl_email_label": {"en": "Email address", "fr": "Adresse e-mail"},
    "wl_or": {"en": "or", "fr": "ou"},
    "wl_whatsapp_label": {"en": "WhatsApp number", "fr": "Numéro WhatsApp"},
    "wl_notify_me": {"en": "Notify me", "fr": "Prévenez-moi"},
    "wl_no_spam": {
        "en": "No spam. One email when the app is ready.",
        "fr": "Pas de spam. Un seul e-mail quand l'application est prête.",
    },
    "wl_success_title": {"en": "You're on the list!", "fr": "Vous êtes sur la liste !"},
    "wl_success_sub": {
        "en": "We'll reach out as soon as NTripi lands on your platform. Stay tuned!",
        "fr": "Nous vous contacterons dès que NTripi arrive sur votre plateforme. Restez à l'écoute !",
    },
    "wl_done": {"en": "Done", "fr": "Terminé"},
    "wl_err_contact_required": {
        "en": "Please enter your email or WhatsApp number.",
        "fr": "Veuillez saisir votre e-mail ou numéro WhatsApp.",
    },
    "wl_err_network": {
        "en": "Network error. Please check your connection and try again.",
        "fr": "Erreur réseau. Vérifiez votre connexion et réessayez.",
    },
    "wl_sending": {"en": "Sending…", "fr": "Envoi en cours…"},
    "wl_err_generic": {
        "en": "Something went wrong. Please try again.",
        "fr": "Une erreur est survenue. Veuillez réessayer.",
    },
    # ── Legal ─────────────────────────────────────────────────────────────
    "legal_en_only_notice": {
        "en": "",
        "fr": "Cette page n'est disponible qu'en anglais.",
    },
}


def resolve_lang(request: Request) -> str:
    """Pick the display language from ?lang=, cookie, then Accept-Language."""
    q = request.query_params.get("lang")
    if q in SUPPORTED:
        return q
    cookie = request.cookies.get("ntripi_lang")
    if cookie in SUPPORTED:
        return cookie
    accept = request.headers.get("accept-language", "")
    # first language subtag starting with "fr" wins (fr, fr-FR, fr-CA, …)
    for part in accept.split(","):
        tag = part.split(";")[0].strip().lower()
        if tag.startswith("fr"):
            return "fr"
    return "en"


def translator(lang: str):
    """Return a `_(key, **kw)` function for the given language, EN-fallback."""
    def _(key: str, **kwargs: str) -> str:
        entry = TRANSLATIONS.get(key)
        if entry is None:
            return key  # surfaces missing keys loudly in dev
        text = entry.get(lang) or entry["en"]
        return text.format(**kwargs) if kwargs else text

    return _
