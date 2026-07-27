"""i18n.py — Lightweight EN/FR/AR translations for server-rendered web pages.

Stdlib only — no gettext catalogs or extra dependencies. Templates call the
`_('key')` global (injected via a context processor in templating.py) and read
`lang` for the <html lang>/<html dir> attributes and the language switcher.

Language resolution order: ?lang= query override → ntripi_lang cookie →
Accept-Language header (first tag whose primary subtag is supported) →
English default.
"""

from __future__ import annotations

from starlette.requests import Request

SUPPORTED = ("en", "fr", "ar")

# Native language names for the switcher — deliberately untranslated.
LANG_NAMES = {"en": "English", "fr": "Français", "ar": "العربية"}

# Languages rendered right-to-left (drives <html dir=...>).
RTL_LANGS = ("ar",)

# key -> {"en": ..., "fr": ..., "ar": ...}. Only UI chrome and page copy — the
# privacy / ToS legal bodies stay English (see legal_en_only_notice).
TRANSLATIONS: dict[str, dict[str, str]] = {
    # ── Nav / footer chrome (_base.html) ──────────────────────────────────
    "footer_privacy": {"en": "Privacy", "fr": "Confidentialité", "ar": "الخصوصية"},
    "footer_terms": {"en": "Terms", "fr": "Conditions", "ar": "الشروط"},
    "meta_default_desc": {
        "en": "Travel itineraries, shared.",
        "fr": "Des itinéraires de voyage, partagés.",
        "ar": "مسارات للرحلات، تتم مشاركتها.",
    },
    # login_submit is kept: reset_password_done.html labels its /app/ CTA with it.
    "login_submit": {"en": "Sign in", "fr": "Se connecter", "ar": "تسجيل الدخول"},
    # ── Password reset ────────────────────────────────────────────────────
    "reset_title": {"en": "Reset password — Ntripi", "fr": "Réinitialiser — Ntripi", "ar": "إعادة تعيين كلمة المرور — Ntripi"},
    "reset_heading": {"en": "Set a new password", "fr": "Définir un nouveau mot de passe", "ar": "عيّن كلمة مرور جديدة"},
    "reset_new_password": {"en": "New password", "fr": "Nouveau mot de passe", "ar": "كلمة المرور الجديدة"},
    "reset_password_placeholder": {
        "en": "At least 8 characters, one number",
        "fr": "Au moins 8 caractères, un chiffre",
        "ar": "8 أحرف على الأقل، ورقم واحد",
    },
    "reset_confirm": {"en": "Confirm new password", "fr": "Confirmer le nouveau mot de passe", "ar": "تأكيد كلمة المرور الجديدة"},
    "reset_submit": {"en": "Update password", "fr": "Mettre à jour le mot de passe", "ar": "تحديث كلمة المرور"},
    "reset_done_heading": {"en": "Password updated", "fr": "Mot de passe mis à jour", "ar": "تم تحديث كلمة المرور"},
    "reset_done_body": {
        "en": "Your password has been changed. You can now sign in with your new password.",
        "fr": "Votre mot de passe a été changé. Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.",
        "ar": "تم تغيير كلمة المرور. يمكنك الآن تسجيل الدخول بكلمة المرور الجديدة.",
    },
    # ── Email verified / token invalid ────────────────────────────────────
    "email_verified_heading": {"en": "Email verified", "fr": "E-mail vérifié", "ar": "تم تأكيد البريد الإلكتروني"},
    "email_verified_body": {
        "en": "Your email is verified. You can head back to the app.",
        "fr": "Votre e-mail est vérifié. Vous pouvez retourner dans l'application.",
        "ar": "تم تأكيد بريدك الإلكتروني. يمكنك العودة إلى التطبيق.",
    },
    "open_ntripi": {"en": "Open Ntripi", "fr": "Ouvrir Ntripi", "ar": "افتح Ntripi"},
    "token_invalid_heading": {"en": "Link no longer valid", "fr": "Lien expiré", "ar": "انتهت صلاحية الرابط"},
    "token_invalid_body": {
        "en": "This link has expired or already been used.",
        "fr": "Ce lien a expiré ou a déjà été utilisé.",
        "ar": "انتهت صلاحية هذا الرابط أو سبق استخدامه.",
    },
    # ── Share pages ───────────────────────────────────────────────────────
    "share_not_found_title": {
        "en": "Itinerary Not Found — Ntripi",
        "fr": "Itinéraire introuvable — Ntripi",
        "ar": "المسار غير موجود — Ntripi",
    },
    "share_not_found_heading": {"en": "Itinerary not found", "fr": "Itinéraire introuvable", "ar": "المسار غير موجود"},
    "share_not_found_body": {
        "en": "This itinerary is not available or may have been removed.",
        "fr": "Cet itinéraire n'est pas disponible ou a peut-être été supprimé.",
        "ar": "المسار هذا غير متاح أو ربما تمت إزالته.",
    },
    "share_go_to_ntripi": {"en": "Go to Ntripi", "fr": "Aller sur Ntripi", "ar": "الانتقال إلى Ntripi"},
    "share_private_heading": {"en": "This itinerary is private", "fr": "Cet itinéraire est privé", "ar": "المسار هذا خاص"},
    "share_private_body": {
        "en": "The owner has restricted who can view this itinerary.",
        "fr": "Le propriétaire a restreint l'accès à cet itinéraire.",
        "ar": "قيّد المالك من يمكنه عرض المسار هذا.",
    },
    "share_by": {"en": "by", "fr": "par", "ar": "بواسطة"},
    "share_stops": {"en": "stops", "fr": "étapes", "ar": "محطات"},
    "share_open_in_app": {"en": "Open in Ntripi", "fr": "Ouvrir dans Ntripi", "ar": "افتحه في Ntripi"},
    "share_download": {"en": "Download the app", "fr": "Télécharger l'application", "ar": "نزّل التطبيق"},
    "share_private_message": {
        "en": "This is a private itinerary. Open the Ntripi app to view the full trip.",
        "fr": "Cet itinéraire est privé. Ouvrez l'application Ntripi pour voir le voyage complet.",
        "ar": "المسار هذا خاص. افتح تطبيق Ntripi لعرض الرحلة كاملة.",
    },
    "share_install_prompt": {"en": "Don't have Ntripi?", "fr": "Vous n'avez pas Ntripi ?", "ar": "ليس لديك Ntripi؟"},
    "share_shared_via": {"en": "Shared via Ntripi", "fr": "Partagé via Ntripi", "ar": "تمت المشاركة عبر Ntripi"},
    "share_note_from_author": {"en": "Note from author", "fr": "Note de l'auteur", "ar": "ملاحظة من الكاتب"},
    "share_get_the_app": {"en": "Get the app", "fr": "Obtenir l'application", "ar": "احصل على التطبيق"},
    "share_public_badge": {"en": "Public itinerary", "fr": "Itinéraire public", "ar": "مسار عام"},
    "share_the_route": {"en": "The Route", "fr": "L'itinéraire", "ar": "الطريق"},
    "share_free": {"en": "Free", "fr": "Gratuit", "ar": "مجاني"},
    "share_plan_own": {"en": "Plan your own journey", "fr": "Planifiez votre propre voyage", "ar": "خطط لرحلتك الخاصة"},
    "share_plan_own_sub": {
        "en": "Open this itinerary in the Ntripi app, or download to start creating your own.",
        "fr": "Ouvrez cet itinéraire dans l'application Ntripi, ou téléchargez-la pour créer le vôtre.",
        "ar": "افتح المسار هذا في تطبيق Ntripi، أو نزّله لتبدأ في إنشاء المسار الخاص بك.",
    },
    "share_open_in_app_short": {"en": "Open in app", "fr": "Ouvrir dans l'app", "ar": "افتح في التطبيق"},
    "share_or_download": {"en": "or download", "fr": "ou télécharger", "ar": "أو نزّله"},
    "share_download_on": {"en": "Download on the", "fr": "Télécharger sur l'", "ar": "حمّله من"},
    "share_get_it_on": {"en": "Get it on", "fr": "Disponible sur", "ar": "متوفر على"},
    # ── Content reporting (share page) ────────────────────────────────────
    "report_link": {"en": "Report this itinerary", "fr": "Signaler cet itinéraire", "ar": "الإبلاغ عن هذا المسار"},
    "report_title": {"en": "Report this itinerary", "fr": "Signaler cet itinéraire", "ar": "الإبلاغ عن هذا المسار"},
    "report_reason_label": {"en": "Reason", "fr": "Motif", "ar": "السبب"},
    "report_reason_spam": {"en": "Spam", "fr": "Spam", "ar": "محتوى مزعج"},
    "report_reason_nsfw": {"en": "Nudity or sexual content", "fr": "Nudité ou contenu sexuel", "ar": "عُري أو محتوى جنسي"},
    "report_reason_violence": {"en": "Violence", "fr": "Violence", "ar": "عنف"},
    "report_reason_hate_speech": {"en": "Hate speech", "fr": "Discours haineux", "ar": "خطاب كراهية"},
    "report_reason_harassment": {"en": "Harassment", "fr": "Harcèlement", "ar": "تحرّش"},
    "report_reason_copyright": {"en": "Copyright infringement", "fr": "Atteinte au droit d'auteur", "ar": "انتهاك حقوق النشر"},
    "report_reason_other": {"en": "Other", "fr": "Autre", "ar": "أخرى"},
    "report_notes_label": {"en": "Details (optional)", "fr": "Détails (facultatif)", "ar": "تفاصيل (اختياري)"},
    "report_submit": {"en": "Submit report", "fr": "Envoyer le signalement", "ar": "إرسال البلاغ"},
    "report_cancel": {"en": "Cancel", "fr": "Annuler", "ar": "إلغاء"},
    "report_thanks": {"en": "Thanks. We'll review this report.", "fr": "Merci. Nous examinerons ce signalement.", "ar": "شكرًا. سنراجع هذا البلاغ."},
    "report_error": {"en": "Something went wrong. Please try again.", "fr": "Une erreur s'est produite. Veuillez réessayer.", "ar": "حدث خطأ ما. يُرجى المحاولة مرة أخرى."},
    "report_rate_limited": {
        "en": "Too many reports from your connection. Please try again later.",
        "fr": "Trop de signalements depuis votre connexion. Veuillez réessayer plus tard.",
        "ar": "عدد كبير جدًا من البلاغات من اتصالك. يُرجى المحاولة لاحقًا.",
    },
    # ── Homepage ──────────────────────────────────────────────────────────
    "home_title": {
        "en": "Ntripi — Share your travel itineraries",
        "fr": "Ntripi — Partagez vos itinéraires de voyage",
        "ar": "Ntripi — شارك مسارات رحلاتك",
    },
    "home_description": {
        "en": "Plan, share, and discover travel itineraries",
        "fr": "Planifiez, partagez et découvrez des itinéraires de voyage",
        "ar": "خطط وشارك واكتشف مسارات الرحلات",
    },
    "home_coming_soon": {
        "en": "Coming soon on iOS & Android",
        "fr": "Bientôt sur iOS et Android",
        "ar": "قريبًا على iOS وAndroid",
    },
    "home_hero_title_1": {"en": "Plan. Share.", "fr": "Planifiez. Partagez.", "ar": "خطط. شارك."},
    "home_hero_title_2": {"en": "Discover.", "fr": "Découvrez.", "ar": "اكتشف."},
    "home_hero_sub": {
        "en": "Build travel itineraries with real stops, costs, and routes. Share what works. Discover trips that locals love.",
        "fr": "Créez des itinéraires de voyage avec de vraies étapes, coûts et parcours. Partagez ce qui fonctionne. Découvrez des voyages que les locaux adorent.",
        "ar": "أنشئ مسارات للرحلات بمحطات وتكاليف وطرق حقيقية. شارك ما ينجح. واكتشف رحلات يحبها السكان المحليون.",
    },
    "home_hero_have_account": {
        "en": "Already have an account?",
        "fr": "Vous avez déjà un compte ?",
        "ar": "لديك حساب بالفعل؟",
    },
    "home_get_it_on": {"en": "Get it on", "fr": "Disponible sur", "ar": "متوفر على"},
    "home_download_on": {"en": "Download on the", "fr": "Télécharger sur l'", "ar": "حمّله من"},
    "home_features_label": {"en": "Everything you need", "fr": "Tout ce qu'il vous faut", "ar": "كل ما تحتاجه"},
    "home_features_title_pre": {"en": "Built for", "fr": "Conçu pour", "ar": "صُمم من أجل"},
    "home_features_title_em": {"en": "real travelers", "fr": "les vrais voyageurs", "ar": "المسافرين الحقيقيين"},
    "home_feat1_h": {"en": "Plan together", "fr": "Planifiez ensemble", "ar": "خططوا معًا"},
    "home_feat1_p": {
        "en": "Build itineraries with stops, transit modes, costs, and personal notes. Everything in one place, easy to share.",
        "fr": "Créez des itinéraires avec étapes, modes de transport, coûts et notes personnelles. Tout au même endroit, facile à partager.",
        "ar": "أنشئ مسارات بمحطات ووسائل نقل وتكاليف وملاحظات شخصية. كل شيء في مكان واحد وسهل المشاركة.",
    },
    "home_feat2_h": {"en": "Share anywhere", "fr": "Partagez partout", "ar": "شارك في أي مكان"},
    "home_feat2_p": {
        "en": "Send a link to anyone. No install required — they can browse your full itinerary in any browser.",
        "fr": "Envoyez un lien à qui vous voulez. Aucune installation requise — chacun peut parcourir votre itinéraire complet dans son navigateur.",
        "ar": "أرسل رابطًا لأي شخص. لا حاجة إلى تثبيت — يمكن للجميع تصفح مسارك كاملاً في أي متصفح.",
    },
    "home_feat3_h": {"en": "Trust the community", "fr": "Faites confiance à la communauté", "ar": "ثق بالمجتمع"},
    "home_feat3_p": {
        "en": "Multi-dimensional ratings: safety, experience, accessibility, and family-friendliness — from people who've been there.",
        "fr": "Des évaluations multidimensionnelles : sécurité, expérience, accessibilité et adaptation aux familles — par ceux qui y sont allés.",
        "ar": "تقييمات متعددة الأبعاد: السلامة والتجربة وسهولة الوصول والملاءمة للعائلات — من أشخاص زاروا المكان فعلاً.",
    },
    "home_feat4_h": {"en": "Explore the feed", "fr": "Explorez le fil", "ar": "استكشف الرحلات"},
    "home_feat4_p": {
        "en": "Discover public itineraries shared by travelers worldwide. Follow explorers and get inspired for your next trip.",
        "fr": "Découvrez des itinéraires publics partagés par des voyageurs du monde entier. Suivez des explorateurs et inspirez-vous pour votre prochain voyage.",
        "ar": "اكتشف مسارات عامة يشاركها مسافرون من حول العالم. تابِع المستكشفين واستلهم رحلتك القادمة.",
    },
    "home_feat5_h": {"en": "Detailed stop info", "fr": "Détails de chaque étape", "ar": "تفاصيل كل محطة"},
    "home_feat5_p": {
        "en": "Each stop includes location, cost, transport connections and custom notes — so nothing gets missed on the road.",
        "fr": "Chaque étape inclut lieu, coût, correspondances de transport et notes personnalisées — pour ne rien oublier en route.",
        "ar": "كل محطة تتضمن الموقع والتكلفة ووصلات النقل وملاحظات مخصصة — حتى لا يفوتك شيء على الطريق.",
    },
    "home_feat6_h": {"en": "Follow & connect", "fr": "Suivez et connectez-vous", "ar": "تابِع وتواصل"},
    "home_feat6_p": {
        "en": "Build a profile, follow fellow explorers, and grow your travel network — public or private, your choice.",
        "fr": "Créez un profil, suivez d'autres explorateurs et développez votre réseau de voyage — public ou privé, à vous de choisir.",
        "ar": "أنشئ ملفًا شخصيًا، وتابِع المستكشفين الآخرين، ووسّع شبكة أسفارك — عامة أو خاصة، الخيار لك.",
    },
    "home_how_label": {"en": "How it works", "fr": "Comment ça marche", "ar": "كيف يعمل"},
    "home_how_title_pre": {"en": "Three steps to your next", "fr": "Trois étapes vers votre prochaine", "ar": "ثلاث خطوات نحو"},
    "home_how_title_em": {"en": "adventure", "fr": "aventure", "ar": "مغامرتك القادمة"},
    "home_step1_h": {"en": "Create an itinerary", "fr": "Créez un itinéraire", "ar": "أنشئ مسار"},
    "home_step1_p": {
        "en": "Add your stops, choose transport, set costs and notes for each leg of the journey.",
        "fr": "Ajoutez vos étapes, choisissez le transport, définissez les coûts et notes pour chaque tronçon du voyage.",
        "ar": "أضف محطاتك، واختر وسيلة النقل، وحدد التكاليف والملاحظات لكل مرحلة من الرحلة.",
    },
    "home_step2_h": {"en": "Share with the world", "fr": "Partagez avec le monde", "ar": "شاركه مع العالم"},
    "home_step2_p": {
        "en": "Make it public and let the community discover your route via the feed or a direct link.",
        "fr": "Rendez-le public et laissez la communauté découvrir votre parcours via le fil ou un lien direct.",
        "ar": "اجعله عامًا ودع المجتمع يكتشف طريقك عبر صفحة الاستكشاف أو برابط مباشر.",
    },
    "home_step3_h": {"en": "Rate & improve", "fr": "Évaluez et améliorez", "ar": "قيّم وحسّن"},
    "home_step3_p": {
        "en": "Travelers who follow your route leave multi-dimensional ratings so everyone benefits.",
        "fr": "Les voyageurs qui suivent votre parcours laissent des évaluations multidimensionnelles pour que tout le monde en profite.",
        "ar": "المسافرون الذين يسلكون طريقك يتركون تقييمات متعددة الأبعاد ليستفيد الجميع.",
    },
    "home_ratings_title_pre": {"en": "Ratings that actually", "fr": "Des évaluations qui", "ar": "تقييمات"},
    "home_ratings_title_em": {"en": "mean something", "fr": "veulent dire quelque chose", "ar": "ذات معنى حقيقي"},
    "home_ratings_p": {
        "en": "We go beyond a single star. Every itinerary is rated across multiple dimensions so you always know what to expect before you go.",
        "fr": "Nous allons au-delà d'une simple étoile. Chaque itinéraire est évalué sur plusieurs dimensions pour que vous sachiez toujours à quoi vous attendre.",
        "ar": "نذهب أبعد من نجمة واحدة. يُقيَّم كل مسار عبر أبعاد متعددة لتعرف دائمًا ما ينتظرك قبل أن تنطلق.",
    },
    # Dimension pills mirror the app's DimensionKey labels (Flutter l10n) verbatim.
    "home_rating_overall": {"en": "Overall", "fr": "Globale", "ar": "عام"},
    "home_rating_safety": {"en": "Safety", "fr": "Sécurité", "ar": "السلامة"},
    "home_rating_experience": {"en": "Experience", "fr": "Expérience", "ar": "التجربة"},
    "home_rating_accessibility": {"en": "Accessibility", "fr": "Accessibilité", "ar": "سهولة الوصول"},
    "home_rating_family": {"en": "Family-friendly", "fr": "Adapté aux familles", "ar": "مناسب للعائلات"},
    "home_rating_uncrowded": {"en": "Uncrowded", "fr": "Tranquillité", "ar": "غير مزدحم"},
    "home_cta_title": {"en": "Ready to explore?", "fr": "Prêt à explorer ?", "ar": "مستعد للاستكشاف؟"},
    "home_cta_sub": {
        "en": "Download the app or jump straight into the web experience.",
        "fr": "Téléchargez l'application ou lancez-vous directement dans l'expérience web.",
        "ar": "نزّل التطبيق أو انطلق مباشرة إلى تجربة الويب.",
    },
    "home_cta_download": {"en": "Download the App", "fr": "Télécharger l'application", "ar": "نزّل التطبيق"},
    "home_cta_continue_web": {"en": "Continue on web", "fr": "Continuer sur le web", "ar": "المتابعة على الويب"},
    # Phone-mockup labels (share_public_badge is too long for the tiny pill).
    "home_mock_public": {"en": "Public", "fr": "Public", "ar": "عام"},
    "home_mock_taxi": {"en": "Taxi", "fr": "Taxi", "ar": "تاكسي"},
    "home_mock_trip_title": {"en": "Marrakech in a Day", "fr": "Marrakech en un jour", "ar": "مراكش في يوم واحد"},
    "home_mock_desc": {
        "en": "One perfect day in the Red City — souks, palaces and gardens. Every stop is worth it!",
        "fr": "Une journée parfaite dans la ville rouge — souks, palais et jardins. Chaque étape en vaut la peine !",
        "ar": "يوم مثالي في المدينة الحمراء — أسواق وقصور وحدائق. كل محطة تستحق الزيارة!",
    },
    "home_mock_advice": {
        "en": "Go early — the souks are calm at sunrise",
        "fr": "Partez tôt — les souks sont calmes au lever du soleil",
        "ar": "انطلق باكرًا — الأسواق هادئة عند الشروق",
    },
    # ── Waitlist modal ────────────────────────────────────────────────────
    "wl_title": {"en": "Be first to know", "fr": "Soyez informé en premier", "ar": "كن أول من يعلم"},
    "wl_sub": {
        "en": "Leave your email or WhatsApp and we'll notify you the moment the app lands on your platform.",
        "fr": "Laissez votre e-mail ou WhatsApp et nous vous préviendrons dès que l'application arrive sur votre plateforme.",
        "ar": "اترك بريدك الإلكتروني أو رقم واتساب وسنخطرك فور وصول التطبيق إلى منصتك.",
    },
    "wl_email_label": {"en": "Email address", "fr": "Adresse e-mail", "ar": "البريد الإلكتروني"},
    "wl_or": {"en": "or", "fr": "ou", "ar": "أو"},
    "wl_whatsapp_label": {"en": "WhatsApp number", "fr": "Numéro WhatsApp", "ar": "رقم واتساب"},
    "wl_notify_me": {"en": "Notify me", "fr": "Prévenez-moi", "ar": "أخطرني"},
    "wl_no_spam": {
        "en": "No spam. One email when the app is ready.",
        "fr": "Pas de spam. Un seul e-mail quand l'application est prête.",
        "ar": "لا رسائل مزعجة. رسالة واحدة عندما يصبح التطبيق جاهزًا.",
    },
    "wl_success_title": {"en": "You're on the list!", "fr": "Vous êtes sur la liste !", "ar": "أنت على القائمة!"},
    "wl_success_sub": {
        "en": "We'll reach out as soon as NTripi lands on your platform. Stay tuned!",
        "fr": "Nous vous contacterons dès que NTripi arrive sur votre plateforme. Restez à l'écoute !",
        "ar": "سنتواصل معك فور وصول NTripi إلى منصتك. ترقّب!",
    },
    "wl_done": {"en": "Done", "fr": "Terminé", "ar": "تم"},
    "wl_err_contact_required": {
        "en": "Please enter your email or WhatsApp number.",
        "fr": "Veuillez saisir votre e-mail ou numéro WhatsApp.",
        "ar": "يرجى إدخال بريدك الإلكتروني أو رقم واتساب.",
    },
    "wl_err_network": {
        "en": "Network error. Please check your connection and try again.",
        "fr": "Erreur réseau. Vérifiez votre connexion et réessayez.",
        "ar": "خطأ في الشبكة. تحقق من اتصالك وحاول مجددًا.",
    },
    "wl_sending": {"en": "Sending…", "fr": "Envoi en cours…", "ar": "جارٍ الإرسال…"},
    "wl_err_generic": {
        "en": "Something went wrong. Please try again.",
        "fr": "Une erreur est survenue. Veuillez réessayer.",
        "ar": "حدث خطأ ما. يرجى المحاولة مجددًا.",
    },
    # ── Legal ─────────────────────────────────────────────────────────────
    "legal_en_only_notice": {
        "en": "",
        "fr": "Cette page n'est disponible qu'en anglais.",
        "ar": "هذه الصفحة متوفرة باللغة الإنجليزية فقط.",
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
    # first tag whose primary subtag is supported wins (fr-CA → fr, ar-MA → ar)
    for part in accept.split(","):
        tag = part.split(";")[0].strip().lower()
        primary = tag.split("-")[0]
        if primary in SUPPORTED:
            return primary
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
