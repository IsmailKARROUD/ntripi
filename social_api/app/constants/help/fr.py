"""
constants/help/fr.py — the French help centre.

English (en.py) is authoritative and is the route table. Everything
structural — slug, category, schema, block anchors and kinds, related, the
updated date — is identical to en.py by construction: the anchor is both the
in-page fragment and the HowToStep url, and `kind` is what FAQPage.mainEntity
and HowTo.step are built from, so a translation that moved one would empty the
structured data while the page still looked right.

`keywords` are the exception that is deliberately NOT a translation: they are
search synonyms, so they carry the words someone actually types in this
language rather than the English list rendered word for word.
"""

from __future__ import annotations

from app.constants.help.models import (
    KIND_DIAGRAM,
    KIND_FAQ,
    KIND_STEP,
    SCHEMA_CONTACT,
    SCHEMA_FAQ,
    SCHEMA_HOWTO,
    SCHEMA_RELEASES,
    Article,
    Block,
    Category,
    Release,
)

CATEGORIES: tuple[Category, ...] = (
    Category(
        id="getting-started",
        title="Premiers pas",
        blurb="Créez un compte et planifiez votre premier voyage.",
        icon="rocket",
    ),
    Category(
        id="building",
        title="Construire un voyage",
        blurb="Les étapes, les lieux, les transits et les notes qui vont avec.",
        icon="article",
    ),
    Category(
        id="sharing",
        title="Partage et visibilité",
        blurb="Décidez qui voit un voyage, et comment vous le leur envoyez.",
        icon="lock",
    ),
    Category(
        id="community",
        title="Communauté",
        blurb="Abonnements, évaluations, voyages enregistrés et fil.",
        icon="group",
    ),
    Category(
        id="account",
        title="Compte et paramètres",
        blurb="Connexion, notifications, autorisations et vos données.",
        icon="person",
    ),
    Category(
        id="safety",
        title="Sécurité et modération",
        blurb="Signalement, blocage, contenus masqués et recours.",
        icon="flag",
    ),
    Category(
        id="troubleshooting",
        title="Dépannage",
        blurb="Quand quelque chose ne fonctionne pas comme prévu.",
        icon="warning",
    ),
    Category(
        id="about",
        title="À propos de Ntripi",
        blurb="Nous contacter, et ce qui a changé dans la dernière version.",
        icon="info",
    ),
)

RELEASES: tuple[Release, ...] = (
    Release(
        version="0.3.0",
        date="2026-09-01",
        headline="Édition collaborative, notifications push et un centre d’aide",
        entries=(
            "**Invitez des personnes à modifier un voyage.** Un propriétaire peut désormais accorder l’accès en modification à d’autres comptes, une seule personne modifiant à la fois pour que le travail de personne ne soit écrasé.",
            "**Notifications push** sur iOS et Android, pour les abonnements, les évaluations, les enregistrements et les avis de modération.",
            "**Ce centre d’aide**, avec tout ce qui précède mis par écrit.",
        ),
    ),
)

ARTICLES: tuple[Article, ...] = (
    Article(
        slug="getting-started",
        title="Comment commencer à planifier un voyage dans Ntripi",
        summary="Créez un compte, découvrez les cinq onglets et construisez votre premier voyage en quelques minutes.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Ntripi est une application de voyage qui sert à construire des plans de voyage à partir d’étapes réelles — avec ce que coûte chacune, le temps qu’elle prend et comment on passe de l’une à l’autre — et à les partager avec qui vous voulez. Créez un compte, ouvrez l’onglet **Itinéraires** et ajoutez votre premier voyage.",
        blocks=(
            Block(
                anchor="create-an-account",
                heading="Créer un compte",
                kind=KIND_STEP,
                body="""Trois façons de s’inscrire : avec une adresse e-mail et un mot de passe, avec **Se connecter avec Google**, ou avec **Se connecter avec Apple**. Les trois mènent au même endroit.

On vous demandera un nom affiché, un nom d’utilisateur et votre date de naissance. Ntripi impose un âge minimum de 16 ans. Votre date de naissance n’apparaît jamais sur votre profil et aucun autre utilisateur ne peut la voir.

Votre nom affiché peut être n’importe quoi, dans n’importe quelle langue, jusqu’à 50 caractères. Votre nom d’utilisateur est le `@nom` que les autres utilisent pour vous trouver, et c’est lui qui s’affiche si vous ne définissez jamais de nom affiché.""",
            ),
            Block(
                anchor="verify-your-email",
                heading="Vérifier votre adresse e-mail",
                kind=KIND_STEP,
                body="""Certaines actions restent bloquées tant que votre adresse e-mail n’est pas vérifiée : créer un voyage, en évaluer un, et suivre des personnes. Cela évite que des comptes jetables pèsent sur les évaluations.

Cherchez le lien de vérification dans votre boîte de réception. Si vous vous êtes inscrit avec Google en utilisant la même adresse, se connecter avec Google la vérifie pour vous — une bannière sur votre profil vous le propose.""",
            ),
            Block(
                anchor="the-five-tabs",
                heading="S’orienter : les cinq onglets",
                kind=KIND_STEP,
                body="""La barre du bas comporte cinq onglets. De gauche à droite :

- **Recherche** — trouve des *personnes*, pas des voyages. Cherchez par nom d’utilisateur.
- **Profil** — votre propre profil, et l’icône d’engrenage qui ouvre tous les paramètres.
- **Itinéraires** — les voyages qui vous appartiennent, plus ceux que l’on vous a invité à modifier.
- **Enregistrés** — les voyages que vous avez mis en favori.
- **Fil** — les voyages publics de tout le monde, dans l’ordre **Top** et **Récents**.

La cloche à côté de l’engrenage, sur votre profil, ouvre vos notifications.""",
            ),
            Block(
                anchor="build-your-first-trip",
                heading="Construire votre premier voyage",
                kind=KIND_STEP,
                body="""Ouvrez **Itinéraires** et appuyez sur **+**. Donnez un titre au voyage et choisissez la devise dans laquelle vous noterez les coûts, puis commencez à ajouter des étapes.

Les nouveaux voyages ne sont visibles que par **vous seul** tant que vous ne changez rien, donc expérimenter ne présente aucun risque. Voir [comment planifier un itinéraire de voyage](/help/plan-a-trip-itinerary) pour le parcours complet.""",
            ),
            Block(
                anchor="where-to-get-help",
                heading="Obtenir de l’aide dans l’application",
                body="""La plupart des champs de formulaire ont une petite icône **?** à côté de leur libellé. Appuyer dessus explique à quoi sert ce champ, sans quitter l’écran — c’est le moyen le plus rapide de comprendre un champ que vous n’avez jamais utilisé.

**Paramètres ▸ Centre d’aide** rassemble les questions courantes et les moyens de nous contacter. Si quelque chose est cassé, voir [comment signaler un bug](/help/contact).""",
            ),
        ),
        keywords=(
            "inscription",
            "s’inscrire",
            "créer un compte",
            "nouveau compte",
            "première fois",
            "débutant",
            "découverte",
            "bases",
            "démarrer",
            "commencer",
            "prise en main",
        ),
        related=("plan-a-trip-itinerary", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="Envie de planifier quelque chose ? Lancez votre premier voyage.",
    ),
    Article(
        slug="plan-a-trip-itinerary",
        title="Comment planifier un itinéraire de voyage, étape par étape",
        summary="Construisez un itinéraire avec de vraies étapes, des coûts, du temps et des transits — d’un voyage vide à un voyage partageable.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Un voyage dans Ntripi est une liste ordonnée d’étapes. Chaque étape est un lieu réel avec une position, un coût approximatif et le temps que vous comptez y passer. Entre les étapes, vous notez comment vous vous déplacez. Construisez-le en quatre passages : créer le voyage, ajouter les étapes, les relier, puis choisir qui peut le voir.",
        blocks=(
            Block(
                anchor="create-the-trip",
                heading="Créer le voyage",
                kind=KIND_STEP,
                body="""Dans l’onglet **Itinéraires**, appuyez sur **+**. Il faut un titre pour démarrer ; tout le reste peut attendre.

- **Titre** — ce qu’est le voyage. « Quatre jours à Marrakech » vaut mieux que « Maroc ».
- **Devise** — chaque coût que vous notez l’utilise, pour que le total ait un sens. Choisissez celle que vous allez réellement dépenser.
- **Image de couverture** — facultative, et vous pouvez l’ajouter plus tard. C’est ce que les gens voient dans le fil et dans un lien partagé.
- **Meilleure période** — les mois où ce voyage fonctionne. Utile pour tout ce qui est saisonnier.""",
            ),
            Block(
                anchor="add-stops",
                heading="Ajouter vos étapes",
                kind=KIND_STEP,
                body="""Appuyez sur **+** à l’intérieur du voyage pour ajouter une étape. Une étape contient :

- **Nom et adresse** — comment s’appelle le lieu.
- **Position** — choisissez un point sur la carte, ou collez un lien Google Maps et laissez Ntripi en extraire les coordonnées.
- **Type de lieu** — manger et boire, dormir, visites, nature, achats, etc. C’est ce qui dessine la bonne icône sur la carte et dans la liste.
- **Coût** — approximativement ce que cela coûte par personne. Laissez vide ou marquez-le gratuit.
- **Temps à prévoir** — combien de temps compter. C’est ce qui rend un plan réaliste plutôt qu’optimiste.
- **Notes** — tout ce dont vous voulez vous souvenir.

Ajoutez les étapes dans l’ordre où vous les visiterez. Vous pourrez les déplacer ensuite.""",
            ),
            Block(
                anchor="connect-the-stops",
                heading="Noter comment vous passez d’une étape à l’autre",
                kind=KIND_STEP,
                body="""Entre deux étapes, vous pouvez ajouter un **transit** : comment vous voyagez, combien de temps cela prend et ce que cela coûte.

Un transit peut comporter plusieurs trajets — un bus jusqu’à la gare, puis un train — et chaque trajet peut porter le numéro de ligne et la direction, c’est-à-dire exactement le détail dont on ne se souvient pas le jour même.""",
            ),
            Block(
                anchor="add-warnings-and-tips",
                heading="Ajouter des avertissements et des conseils",
                kind=KIND_STEP,
                body="""Toute étape, et le voyage dans son ensemble, peut porter de courtes notes de quatre sortes : **conseil**, **prudence**, **éviter** et **info**. Elles s’affichent en pastilles colorées, donc difficiles à manquer.

C’est là que « acheter les billets à l’avance » et « l’entrée nord est fermée » ont leur place — les choses qu’un simple itinéraire ne dit jamais.""",
            ),
            Block(
                anchor="choose-who-sees-it",
                heading="Choisir qui peut le voir",
                kind=KIND_STEP,
                body="""Les nouveaux voyages démarrent en **moi uniquement**. Quand vous êtes prêt, ouvrez les paramètres du voyage et choisissez l’un des quatre niveaux — public, abonnés, personnes précises, ou vous seul.

Voir [comment partager un voyage sans le rendre public](/help/share-an-itinerary-privately) pour ce que chaque niveau signifie en pratique.""",
            ),
        ),
        keywords=(
            "planificateur de voyage",
            "itinéraire de voyage",
            "itinéraires",
            "jour par jour",
            "planifier des vacances",
            "organiser un voyage",
            "parcours",
            "programme",
            "étapes",
            "budget",
            "coût",
            "planification",
        ),
        related=("plan-alternative-options", "share-an-itinerary-privately", "getting-started"),
        updated="2026-09-01",
        cta="Planifiez votre propre itinéraire — comptez une dizaine de minutes.",
    ),
    Article(
        slug="app-map",
        title="Les écrans et les icônes de Ntripi, expliqués",
        summary="Une visite guidée des cinq onglets, de l’écran d’itinéraire et des icônes que vous croiserez en chemin.",
        category="getting-started",
        intro="Ntripi a cinq onglets en bas et très peu d’habillage au-dessus. Presque tout ce que vous pouvez changer se trouve soit derrière l’engrenage de votre profil, soit derrière un appui long sur l’élément lui-même. Cette page nomme chaque chose.",
        blocks=(
            Block(
                anchor="bottom-nav",
                heading="Les cinq onglets",
                kind=KIND_DIAGRAM,
                body="""1. **Recherche** — trouve des **personnes**, pas des voyages. Cherchez par nom d’utilisateur. Les voyages publics se découvrent plutôt dans le Fil.
2. **Profil** — votre propre profil. L’engrenage ouvre tous les paramètres ; la cloche à côté ouvre vos notifications.
3. **Itinéraires** — les voyages qui vous appartiennent, et une seconde vue pour ceux que d’autres vous ont invité à modifier.
4. **Enregistrés** — les voyages mis en favori, avec un champ de filtre.
5. **Fil** — les voyages publics de tout le monde, dans l’ordre **Top** et **Récents**.

Appuyer sur l’onglet où vous êtes déjà vous ramène en haut de celui-ci, c’est le moyen le plus rapide de sortir d’un écran profond.""",
            ),
            Block(
                anchor="itinerary-screen",
                heading="Lire un itinéraire",
                kind=KIND_DIAGRAM,
                body="""1. **La pastille de visibilité** sous le titre — qui peut ouvrir ce voyage. Appuyez dessus (en tant que propriétaire) pour la changer.
2. **Une deuxième colonne** signifie que ces deux étapes sont des alternatives l’une de l’autre, pas une suite. Voir [comment prévoir deux options pour la même journée](/help/plan-alternative-options).
3. **Une ligne de transit** entre deux étapes — comment aller de l’une à l’autre, et en combien de temps.
4. **Une pastille colorée** sur une étape est une note : conseil, prudence, éviter ou info.
5. **La ligne d’évaluation** — la moyenne et le nombre de personnes qui ont évalué. Les moyennes apparaissent à partir de trois évaluations.""",
            ),
            Block(
                anchor="icons",
                heading="Les icônes que vous croiserez",
                body="""| Icône | Ce qu’elle fait |
|---|---|
| **?** | Explique le champ à côté, sans quitter l’écran |
| Marque-page | Enregistre le voyage dans votre onglet Enregistrés |
| Crayon | Modifier — affiché seulement si vous en avez le droit |
| Drapeau | Nous le signaler |
| Engrenage | Paramètres, sur votre propre profil |
| Cloche | Notifications, avec un point quand il y a du nouveau |

Le **?** vaut la peine d’être connu : presque chaque champ de chaque formulaire en a un, et c’est plus rapide que de venir ici.""",
            ),
            Block(
                anchor="long-press",
                heading="Les raccourcis par appui long",
                body="""Garder le doigt sur une partie d’un voyage qui vous appartient mène directement à la modification de cette partie — le titre, la couverture, une étape, une note. Cela évite de repasser par l’écran de modification.

Sur le voyage de quelqu’un d’autre, le même geste propose de signaler ou de bloquer. Les deux ne se chevauchent jamais, vous ne pouvez donc pas signaler votre propre voyage par accident ni modifier celui d’un autre.""",
            ),
        ),
        keywords=(
            "icônes",
            "boutons",
            "menu",
            "navigation",
            "onglets",
            "où se trouve",
            "à quoi sert ce bouton",
            "interface",
            "disposition",
            "écrans",
        ),
        related=("getting-started", "app-settings"),
        updated="2026-09-01",
        cta="Voyez par vous-même — ouvrez Ntripi.",
    ),
    Article(
        slug="plan-alternative-options",
        title="Comment prévoir deux options pour la même journée",
        summary="Placez des lieux alternatifs côte à côte dans un même voyage, pour qu’un jour de pluie ou un autre budget n’exige pas un second plan.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="La plupart des planificateurs imposent un lieu par créneau. Ntripi vous laisse empiler des **alternatives côte à côte** : deux ou trois lieux qui occupent le même point du voyage, pour que celui qui voyage choisisse le jour même. En interne, ces colonnes s’appellent des **pistes**.",
        blocks=(
            Block(
                anchor="what-a-track-is",
                heading="Ce qu’est une piste",
                body="""Une **piste** est une colonne verticale d’étapes qui sont des alternatives les unes des autres. Un voyage à une seule piste est un itinéraire linéaire ordinaire. Ajoutez une deuxième piste au même endroit et vous avez deux façons de passer cette partie du voyage.

Les pistes servent chaque fois que la réponse est « ça dépend » :

- **Météo** — une option en extérieur et une en intérieur.
- **Budget** — le restaurant cher et le bon pas cher.
- **Énergie** — la longue randonnée et la petite balade.
- **Goûts** — le musée pour une moitié du groupe et le marché pour l’autre.""",
            ),
            Block(
                anchor="add-an-alternative",
                heading="Ajouter une alternative",
                kind=KIND_STEP,
                body="""Ouvrez le voyage et trouvez l’étape à laquelle vous voulez une alternative. Utilisez la commande d’ajout à côté d’elle et choisissez de placer la nouvelle étape dans une **nouvelle piste** plutôt qu’après l’existante.

Les deux étapes sont maintenant côte à côte. Aucune n’est la « vraie » — elles sont à égalité, et quiconque lit le voyage voit les deux.""",
            ),
            Block(
                anchor="move-a-stop",
                heading="Déplacer une étape d’une piste à l’autre",
                kind=KIND_STEP,
                body="""Une étape peut être déplacée vers une autre piste après coup, vous n’êtes donc pas prisonnier de l’ordre dans lequel vous avez ajouté les choses. Ouvrez l’étape et utilisez l’action de déplacement pour choisir sa piste.

Une piste n’existe que tant qu’elle contient au moins une étape. Déplacez ou supprimez la dernière étape et la colonne vide disparaît d’elle-même — il n’y a rien à ranger.""",
            ),
            Block(
                anchor="reorder",
                heading="Réorganiser les pistes et les étapes",
                kind=KIND_STEP,
                body="Faites glisser pour réorganiser les étapes à l’intérieur d’une piste, et pour réorganiser les pistes elles-mêmes. La première piste d’un voyage est traitée comme le point de départ et la dernière comme la destination, c’est ce que la carte relie.",
            ),
            Block(
                anchor="transport-warning",
                heading="Pourquoi insérer une piste déclenche parfois un avertissement",
                body="""Un transit se note entre deux pistes *voisines*. Si vous insérez une nouvelle piste entre deux qui sont déjà reliées par un transit, cette liaison n’a plus où se loger — les deux pistes ne sont plus voisines.

Ntripi demande confirmation plutôt que de supprimer discrètement le transit que vous avez saisi. Confirmez, et la liaison concernée est supprimée ; annulez, et rien ne change.""",
            ),
        ),
        keywords=(
            "parallèle",
            "piste",
            "pistes",
            "alternative",
            "alternatives",
            "options",
            "facultatif",
            "plan b",
            "solution de repli",
            "branche",
            "colonne",
            "au choix",
            "jour de pluie",
            "météo",
            "choix",
        ),
        related=("plan-a-trip-itinerary", "getting-started"),
        updated="2026-09-01",
        cta="Planifiez un voyage avec de vraies alternatives, pas une seule ligne fragile.",
    ),
    Article(
        slug="add-places-to-an-itinerary",
        title="Comment ajouter des lieux, des coûts et du temps à un plan de voyage",
        summary="Tout ce qu’une étape peut contenir — ce que c’est, où c’est, ce que cela coûte et combien de temps prévoir.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Une étape est un lieu où vous serez vraiment. Au-delà de son nom, les deux champs qui rendent un plan utilisable sont le **coût** et le **temps à prévoir** — ce sont eux qui transforment une liste de lieux en quelque chose que l’on peut budgéter et faire tenir dans une journée.",
        blocks=(
            Block(
                anchor="add-a-stop",
                heading="Ajouter une étape",
                kind=KIND_STEP,
                body="""Ouvrez le voyage et appuyez sur **+**. Donnez au lieu un nom — celui que vous diriez à voix haute, pas son intitulé officiel — et une adresse si vous en avez une.

Les étapes s’ajoutent dans l’ordre de visite. Vous pouvez les faire glisser dans un autre ordre à tout moment ensuite.""",
            ),
            Block(
                anchor="place-type",
                heading="Choisir un type de lieu",
                kind=KIND_STEP,
                body="""Le type de lieu dessine la bonne icône sur la carte et dans la liste, pour qu’une journée se lise d’un coup d’œil. Il y en a onze :

- **Manger & boire** · **Dormir** · **Acheter**
- **Apprendre & voir** · **Site** · **Divertissement**
- **Jouer & regarder** · **Nature** · **Soin & bains**
- **Prier** · **Voyager**

C’est facultatif. Une étape sans type fonctionne quand même ; elle ressemble simplement à toutes les autres étapes sans type.""",
            ),
            Block(
                anchor="cost",
                heading="Noter ce que cela coûte",
                kind=KIND_STEP,
                body="""Saisissez le coût approximatif **par personne**, dans la devise du voyage. Une approximation suffit — ce qui compte, c’est le total à la fin, pas une facture.

Si un lieu est gratuit, marquez-le gratuit plutôt que de laisser le champ vide. Vide signifie « je ne me suis pas renseigné », et la différence compte pour qui lit votre plan.""",
            ),
            Block(
                anchor="time-to-spend",
                heading="Noter combien de temps prévoir",
                kind=KIND_STEP,
                body="""C’est le champ qui empêche un plan d’être un fantasme. Quatre sites en un après-midi paraît raisonnable en liste et devient impossible une fois que chacun porte quatre-vingt-dix minutes.

Prévoyez le temps que vous voudriez vraiment y passer, pas le minimum en lequel c’est faisable.""",
            ),
            Block(
                anchor="notes",
                heading="Ajouter vos propres notes",
                body="""Le champ notes est du texte libre — références de réservation, quoi commander, quelle entrée utiliser, pourquoi vous avez choisi ce lieu plutôt que celui d’à côté.

Pour un avertissement qui doit être difficile à manquer plutôt que lu en passant, utilisez plutôt [une note conseil ou prudence](/help/travel-notes-and-warnings) : celles-ci s’affichent en pastilles colorées.""",
            ),
        ),
        keywords=(
            "étape",
            "étapes",
            "lieu",
            "lieux",
            "ajouter",
            "budget",
            "prix",
            "durée",
            "combien de temps",
            "catégorie",
            "restaurant",
            "hôtel",
            "musée",
        ),
        related=("plan-a-trip-itinerary", "add-locations-from-google-maps", "travel-notes-and-warnings"),
        updated="2026-09-01",
        cta="Lancez un voyage et ajoutez votre première étape.",
    ),
    Article(
        slug="add-locations-from-google-maps",
        title="Comment ajouter un lieu depuis un lien Google Maps",
        summary="Collez un lien Maps et Ntripi en extrait les coordonnées, ou placez vous-même le point sur la carte.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Une étape peut obtenir sa position de deux façons : choisir le point sur la carte de Ntripi, ou coller un lien Google Maps et laisser Ntripi en extraire les coordonnées. La seconde est en général plus rapide, parce que vous avez probablement déjà trouvé le lieu là-bas.",
        blocks=(
            Block(
                anchor="paste-a-link",
                heading="Coller un lien Google Maps",
                kind=KIND_STEP,
                body="""Dans le champ de position de l’étape, basculez sur l’option lien et collez l’URL. Ntripi en extrait les coordonnées et conserve le lien, si bien que l’étape affiche un petit aperçu de carte et que vous pourrez ouvrir le lieu dans Maps plus tard.

L’URL longue du bureau comme le lien de partage court fonctionnent. Seules les adresses Google Maps sont acceptées — un lien vers autre chose est refusé plutôt que stocké et ignoré en silence.""",
            ),
            Block(
                anchor="pick-on-the-map",
                heading="Ou placez le point vous-même",
                kind=KIND_STEP,
                body="""Basculez sur les coordonnées et ouvrez le sélecteur de carte. Déplacez et zoomez jusqu’à l’endroit voulu : le point au centre est ce qui sera enregistré.

C’est la meilleure option pour un lieu absent de Maps — un point de vue, un départ de sentier, une plage sans nom.""",
            ),
            Block(
                anchor="locate-me",
                heading="Centrer la carte sur votre position",
                kind=KIND_STEP,
                body="""Le bouton de localisation centre la carte sur votre position actuelle, ce qui évite de traverser un continent pour retrouver la ville où vous vous trouvez.

Il demande l’autorisation de localisation la première fois. **Refuser ne bloque rien** — la carte s’ouvre simplement ailleurs et vous vous déplacez jusqu’où vous voulez. Voir [quelles autorisations Ntripi demande](/help/permissions).""",
            ),
            Block(
                anchor="opening-in-maps",
                heading="Ouvrir une étape dans votre application de cartes",
                body="""Une étape qui a une position propose de s’ouvrir dans l’application de cartes que vous avez installée, pour obtenir l’itinéraire le jour même sans rien retaper.

La carte de Ntripi sert à lire le plan ; votre application de cartes sert à le parcourir.""",
            ),
        ),
        keywords=(
            "google maps",
            "lien",
            "coller",
            "coordonnées",
            "gps",
            "point",
            "position",
            "sélecteur de carte",
            "latitude",
            "longitude",
            "où",
        ),
        related=("add-places-to-an-itinerary", "permissions"),
        updated="2026-09-01",
        cta="Placez votre première étape sur la carte.",
    ),
    Article(
        slug="plan-transport-between-stops",
        title="Comment prévoir les transports entre les étapes",
        summary="Notez comment vous passez d’un lieu au suivant — le mode, la durée, le coût et le numéro de ligne dont vous ne vous souviendrez pas.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Entre deux étapes quelconques, vous pouvez noter un **transit** : comment vous voyagez, combien de temps cela prend et ce que cela coûte. Un transit peut comporter plusieurs trajets, si bien qu’un déplacement bus-puis-train reste une seule liaison plutôt que deux trous inexpliqués.",
        blocks=(
            Block(
                anchor="add-a-segment",
                heading="Ajouter une liaison",
                kind=KIND_STEP,
                body="""Entre deux étapes, utilisez la commande d’ajout de transport. Choisissez le mode — à pied, à vélo, bus, train, métro, taxi, voiture, ferry, avion — et donnez-lui une durée.

Le coût est par personne, dans la devise du voyage, et s’additionne au total du voyage à côté des étapes.""",
            ),
            Block(
                anchor="multiple-legs",
                heading="Ajouter plus d’un trajet",
                kind=KIND_STEP,
                body="""Un déplacement utilise rarement un seul véhicule. Ajoutez un trajet pour chaque partie — la marche jusqu’à l’arrêt, le bus, la correspondance, le train — et chacun garde son mode et sa durée.

La liaison affiche alors le vrai temps de porte à porte, c’est-à-dire le chiffre qui décide si l’après-midi tient debout.""",
            ),
            Block(
                anchor="line-and-direction",
                heading="Noter la ligne et la direction",
                kind=KIND_STEP,
                body="""Chaque trajet peut porter une ligne — `M4`, `Bus 12`, `RER B` — et une direction, c’est-à-dire le terminus affiché à l’avant du véhicule.

La direction est le détail qui compte le jour même. Savoir que vous voulez le M4 n’aide en rien sur un quai où les rames partent dans les deux sens.""",
            ),
            Block(
                anchor="orphaned-connections",
                heading="Pourquoi insérer une étape peut déclencher un avertissement",
                body="""Une liaison vit *entre deux voisines*. Si vous insérez une nouvelle colonne entre deux qui en ont déjà une, cette liaison n’a plus où se placer.

Ntripi demande confirmation plutôt que d’abandonner discrètement ce que vous avez saisi. Confirmez et la liaison concernée est supprimée ; annulez et rien ne change.""",
            ),
        ),
        keywords=(
            "transport",
            "transit",
            "bus",
            "train",
            "métro",
            "taxi",
            "marche",
            "voiture",
            "avion",
            "correspondance",
            "trajet",
            "liaison",
            "comment s’y rendre",
        ),
        related=("add-places-to-an-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Cartographiez un déplacement, correspondances comprises.",
    ),
    Article(
        slug="travel-notes-and-warnings",
        title="Comment ajouter des avertissements et des conseils de voyage",
        summary="Quatre sortes de notes — conseil, prudence, éviter et info — qui s’affichent en pastilles colorées pour que personne ne passe à côté.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Ce qui tourne mal en voyage est rarement dans le guide. Ntripi propose quatre types de notes — **conseil**, **prudence**, **éviter** et **info** — qui s’attachent à une seule étape ou au voyage entier et s’affichent en pastilles colorées, si bien qu’un lecteur les rencontre plutôt qu’il ne les découvre.",
        blocks=(
            Block(
                anchor="the-four-types",
                heading="À quoi sert chaque type",
                body="""- **Conseil** — faites ceci, et cela ira mieux. « Achetez le billet en ligne, la file dure une heure. »
- **Prudence** — ça va, mais faites attention. « Fréquenté le soir ; gardez votre sac devant vous. »
- **Éviter** — non. « La station de taxis devant surfacture ; marchez deux rues et hélez-en un. »
- **Info** — bon à savoir, rien à faire. « Fermé le mardi. »

Le type ne change que la couleur et le libellé, choisissez donc celui qu’un inconnu lirait comme vous l’entendiez.""",
            ),
            Block(
                anchor="add-to-a-stop",
                heading="Ajouter une note à une étape",
                kind=KIND_STEP,
                body="""Ouvrez l’étape et ajoutez-y une note. Elle appartient à ce lieu et le suit si vous réorganisez le voyage.

C’est là qu’a sa place tout ce qui concerne une entrée précise, une file, un horaire d’ouverture ou un danger local.""",
            ),
            Block(
                anchor="add-to-the-trip",
                heading="Ajouter une note au voyage entier",
                kind=KIND_STEP,
                body="""Depuis l’itinéraire lui-même, une note s’applique au voyage dans son ensemble — formalités de visa, saison, quelle carte SIM fonctionne, quoi emporter.

Les notes au niveau du voyage s’affichent près du haut, avant les étapes, parce qu’il faut généralement les lire avant de planifier une journée.""",
            ),
            Block(
                anchor="notes-vs-notes",
                heading="Notes colorées et champ notes",
                body="""Chaque étape a aussi un simple champ **notes**. Utilisez-le pour vos propres pense-bêtes — une référence de réservation, quoi commander.

Utilisez une note colorée pour tout ce sur quoi un lecteur doit *agir*. La différence tient à ce qu’il doit être facile ou non de passer outre.""",
            ),
        ),
        keywords=(
            "note",
            "notes",
            "avertissement",
            "avertissements",
            "conseil",
            "conseils",
            "astuce",
            "prudence",
            "éviter",
            "info",
            "annotation",
            "sécurité",
            "arnaque",
        ),
        related=("add-places-to-an-itinerary", "plan-a-trip-itinerary"),
        updated="2026-09-01",
        cta="Écrivez ce que vous auriez aimé qu’on vous dise.",
    ),
    Article(
        slug="trip-cover-photos",
        title="Comment ajouter une photo de couverture à votre voyage",
        summary="Choisissez une image de couverture, recadrez-la, et sachez ce qui est refusé avant de l’envoyer.",
        category="building",
        intro="La couverture est ce que les gens voient dans le fil et dans un lien partagé, elle travaille donc plus que n’importe quel autre champ. Seul le **propriétaire** du voyage peut la définir — une personne invitée à modifier peut changer le contenu, mais pas le visage public du voyage.",
        blocks=(
            Block(
                anchor="add-a-cover",
                heading="Ajouter ou changer la couverture",
                body="""Ouvrez l’écran de modification du voyage et appuyez sur la zone de couverture. Votre photothèque s’ouvre ; choisissez une image et recadrez-la au cadre.

Le recadrage est large, parce que c’est la forme qu’utilise un aperçu de lien. Une photo verticale perdra son haut et son bas, choisissez-en donc une dont le sujet est au milieu.""",
            ),
            Block(
                anchor="what-gets-refused",
                heading="Ce qui est refusé, et pourquoi",
                body="""Une image peut être refusée pour trois raisons :

- **Trop petite.** En dessous de 600 pixels sur son plus petit côté, elle paraîtra floue sur un écran moderne.
- **Un format non pris en charge.** JPEG, PNG et les formats photo habituels conviennent.
- **Le contenu.** Les envois sont vérifiés automatiquement au regard des [règles de la communauté](/guidelines) avant d’être stockés.

Si vous pensez qu’un refus était injustifié, [dites-le-nous](/help/contact).""",
            ),
            Block(
                anchor="what-we-strip",
                heading="Ce que Ntripi retire de votre photo",
                body="""Chaque image envoyée voit ses **métadonnées EXIF supprimées** avant d’être stockée. C’est le bloc de données cachées qu’un appareil photo attache — surtout les **coordonnées GPS du lieu de la prise de vue**, ainsi que le modèle de l’appareil et l’horodatage.

Cela vaut que le voyage soit public ou non, et ne peut pas être désactivé. Une photo de votre rue ne devrait pas publier votre rue.""",
            ),
            Block(
                anchor="no-cover",
                heading="Si vous n’en ajoutez pas",
                body="""Un voyage sans couverture reçoit un visuel de remplacement généré à partir de son parcours, il n’a donc jamais l’air cassé.

Mieux vaut tout de même en ajouter une vraie avant de partager publiquement : dans un fil de photographies, c’est le visuel de remplacement que l’on fait défiler.""",
            ),
        ),
        keywords=(
            "couverture",
            "photo",
            "image",
            "envoyer",
            "téléverser",
            "recadrer",
            "bannière",
            "vignette",
            "refusée",
            "trop petite",
        ),
        related=("plan-a-trip-itinerary", "share-a-trip-link"),
        updated="2026-09-01",
        cta="Donnez un visage à votre voyage.",
    ),
    Article(
        slug="plan-a-trip-with-friends",
        title="Comment planifier un voyage à plusieurs",
        summary="Invitez des personnes à modifier un voyage, et comprenez pourquoi une seule d’entre elles peut écrire à la fois.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Un voyage a un propriétaire et un nombre quelconque d’**éditeurs**. Un éditeur peut changer le contenu — étapes, transits, notes, titre — mais pas qui peut le voir, ni la couverture, ni la liste des éditeurs. Une seule personne modifie à la fois, pour que le travail de personne ne soit écrasé.",
        blocks=(
            Block(
                anchor="invite-an-editor",
                heading="Inviter quelqu’un à modifier",
                kind=KIND_STEP,
                body="""Ouvrez l’écran de modification du voyage et trouvez la liste des éditeurs. Ajoutez la personne par son nom d’utilisateur. Elle reçoit une notification qui nomme le voyage, ce qui est précisément ce qui lui permet de le retrouver — un voyage privé n’est dans aucun fil ni aucune recherche.

Seul le **propriétaire** peut ajouter ou retirer des éditeurs. Un éditeur ne peut pas en recruter d’autres : l’invitation est votre décision de confiance et ne s’accompagne pas du pouvoir de la transmettre.""",
            ),
            Block(
                anchor="cannot-see-it",
                heading="S’ils ne voient pas encore le voyage",
                kind=KIND_STEP,
                body="""Modifier suppose de pouvoir d’abord voir. Si vous invitez quelqu’un qui ne le peut pas, Ntripi demande s’il faut aussi lui donner l’accès, plutôt que d’échouer.

Répondre oui l’ajoute à la liste d’autorisation de ce voyage, et rien d’autre. Cela n’élargit jamais la visibilité du voyage — transformer « abonnés » en « personnes précises » couperait silencieusement tous les autres, cela reste donc une décision que vous prenez délibérément.""",
            ),
            Block(
                anchor="one-at-a-time",
                heading="Pourquoi une seule personne peut modifier à la fois",
                body="""Quand vous ouvrez un voyage pour le modifier, vous le tenez. Toute autre personne voit **« quelqu’un d’autre est en train de modifier »** et peut lire mais pas enregistrer.

L’alternative, c’est deux personnes qui écrivent dans la même étape et l’une des deux qui perd tout sans qu’on le lui dise. Le maintien est bref — il est relâché quand vous partez, et il expire de lui-même si vous êtes distrait.""",
            ),
            Block(
                anchor="taking-over",
                heading="Reprendre la main sur quelqu’un",
                kind=KIND_STEP,
                body="""Si le voyage est resté inactif un moment, toute personne pouvant le modifier peut le reprendre. En tant que propriétaire, vous pouvez toujours le reprendre — y compris depuis votre propre autre appareil, ce qui est la raison habituelle d’un blocage.

Reprendre la main est toujours une deuxième étape délibérée, jamais automatique.""",
            ),
            Block(
                anchor="losing-the-lock",
                heading="Si quelqu’un reprend la main pendant que vous écrivez",
                body="""Une bannière apparaît et Enregistrer cesse de fonctionner. **Rien de ce que vous avez saisi n’est perdu** — chaque champ reste exactement tel que vous l’avez laissé, et vous pouvez toujours y sélectionner et copier.

Reprenez le voyage et enregistrez, ou copiez votre texte et collez-le quand l’autre personne a fini. Ntripi ne fermera pas l’écran et ne videra pas un champ à votre place, parce qu’à cet instant votre texte non enregistré en est la seule copie.""",
            ),
            Block(
                anchor="finding-shared-trips",
                heading="Retrouver un voyage que l’on a partagé avec vous",
                body="L’onglet **Itinéraires** comporte une seconde vue pour les voyages que l’on vous a invité à modifier. C’est le chemin durable pour y revenir — la notification qui l’a annoncé finit par disparaître, et un voyage privé n’apparaît dans aucun fil ni aucune recherche.",
            ),
        ),
        keywords=(
            "collaborer",
            "collaboration",
            "ensemble",
            "partagé",
            "éditeur",
            "éditeurs",
            "inviter",
            "groupe",
            "amis",
            "famille",
            "à plusieurs",
            "quelqu’un d’autre modifie",
            "verrou",
        ),
        related=("share-an-itinerary-privately", "plan-alternative-options", "troubleshooting"),
        updated="2026-09-01",
        cta="Planifiez votre prochain voyage avec ceux qui le feront.",
    ),
    Article(
        slug="share-an-itinerary-privately",
        title="Comment partager un itinéraire de voyage sans le rendre public",
        summary="Quatre niveaux de visibilité décident qui peut ouvrir un voyage — de tout internet à une poignée de personnes nommées.",
        category="sharing",
        schema=SCHEMA_FAQ,
        intro="Chaque voyage a l’un des quatre niveaux de visibilité, et vous pouvez le changer à tout moment. Les nouveaux voyages démarrent en **moi uniquement**. Pour partager avec un groupe précis sans publier, utilisez **personnes précises** et ajoutez-les par nom d’utilisateur.",
        blocks=(
            Block(
                anchor="the-four-levels",
                heading="Quels sont les quatre niveaux de visibilité ?",
                kind=KIND_FAQ,
                body="""- **Public** — n’importe qui peut l’ouvrir, y compris des personnes non connectées. Il peut apparaître dans le fil et être trouvé par les moteurs de recherche via son lien de partage.
- **Abonnés** — toutes les personnes qui vous suivent. Si votre compte est privé, cela ne concerne que les abonnés que vous avez acceptés.
- **Personnes précises** — seulement les noms d’utilisateur que vous ajoutez. Personne d’autre, quelle que soit la façon dont il a obtenu le lien.
- **Moi uniquement** — personne à part vous et ceux que vous avez désignés éditeurs.""",
            ),
            Block(
                anchor="share-with-a-few-people",
                heading="Comment partager avec quelques personnes seulement ?",
                kind=KIND_FAQ,
                body="""Réglez le voyage sur **personnes précises** et ajoutez-les par nom d’utilisateur. Envoyez-leur ensuite le lien de partage du voyage.

Le lien n’est pas un mot de passe secret — c’est l’adresse du voyage. L’accès est vérifié par rapport à votre liste chaque fois que quelqu’un l’ouvre, donc transférer le lien à une personne absente de la liste ne lui donne rien.""",
            ),
            Block(
                anchor="what-others-see",
                heading="Que voit une personne sans accès ?",
                kind=KIND_FAQ,
                body="""Une page indiquant que le voyage n’est pas disponible. Elle ne dit pas que le voyage existe, ni à qui il appartient, ni comment il s’appelle — un voyage que vous ne pouvez pas voir est indiscernable d’un voyage qui n’a jamais été créé.

Il en va de même pour un profil qui vous a bloqué.""",
            ),
            Block(
                anchor="change-later",
                heading="Puis-je changer la visibilité plus tard ?",
                kind=KIND_FAQ,
                body="""Oui, à tout moment, dans les deux sens. Passer à un niveau plus restreint prend effet immédiatement — toute personne qui ne remplit plus les conditions cesse de pouvoir l’ouvrir.

Seul le propriétaire du voyage peut changer la visibilité. Une personne que vous avez invitée à modifier peut changer le contenu, mais pas qui le voit.""",
            ),
            Block(
                anchor="link-previews",
                heading="Qu’est-ce qui s’affiche quand je colle le lien quelque part ?",
                kind=KIND_FAQ,
                body="""Un voyage public génère une carte d’aperçu avec son image de couverture, son titre, sa durée, son coût et son évaluation.

Un voyage qui n’est pas public ne génère aucun aperçu — l’aperçu divulguerait le titre à tout le monde dans la conversation, y compris à ceux qui ne peuvent pas l’ouvrir.""",
            ),
        ),
        keywords=(
            "privé",
            "en privé",
            "visibilité",
            "qui peut voir",
            "public",
            "abonnés",
            "restreint",
            "moi uniquement",
            "masquer",
            "caché",
            "secret",
            "lien de partage",
            "autorisations",
            "amis seulement",
            "inviter",
        ),
        related=("plan-a-trip-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Planifiez un voyage et partagez-le exactement avec les personnes visées.",
    ),
    Article(
        slug="share-a-trip-link",
        title="Comment partager votre voyage sous forme de lien",
        summary="Envoyez un voyage à n’importe qui par un lien, en sachant ce que la carte d’aperçu montrera avant de le coller.",
        category="sharing",
        intro="Chaque voyage a une adresse web. Partager, c’est simplement l’envoyer — le lien est l’emplacement du voyage, pas un mot de passe, et l’accès est revérifié par rapport à votre [réglage de visibilité](/help/share-an-itinerary-privately) chaque fois que quelqu’un l’ouvre.",
        blocks=(
            Block(
                anchor="get-the-link",
                heading="Obtenir le lien",
                body="""Ouvrez le voyage et utilisez l’action de partage. La feuille de partage habituelle de votre appareil apparaît, le lien peut donc partir vers n’importe quelle application — messages, e-mail, notes.

La page s’ouvre dans un navigateur : la personne à qui vous l’envoyez n’a pas besoin de l’application pour la lire.""",
            ),
            Block(
                anchor="what-the-preview-shows",
                heading="Ce que montre la carte d’aperçu",
                body="""Un voyage **public** génère une carte d’aperçu dans la plupart des messageries : l’image de couverture, le titre, la durée et le coût totaux, le nombre d’étapes, et l’évaluation s’il en a une.

Un voyage qui n’est **pas** public ne génère aucun aperçu. C’est délibéré — un aperçu montrerait le titre à tout le monde dans la conversation de groupe, y compris à ceux qui ne peuvent pas l’ouvrir.""",
            ),
            Block(
                anchor="what-they-see",
                heading="Ce que reçoit le lecteur",
                body="""Le voyage entier : les étapes dans l’ordre, les options parallèles, les transits entre elles, les coûts, vos notes et avertissements, et les évaluations.

Il peut tout lire sans compte. L’enregistrer, l’évaluer ou en copier des étapes en demande un.""",
            ),
            Block(
                anchor="unsharing",
                heading="Revenir en arrière",
                body="""Changez la visibilité du voyage et le lien cesse de fonctionner, immédiatement, pour quiconque ne remplit plus les conditions. Inutile de courir après le message envoyé.

Ce que vous ne pouvez pas défaire, c’est une capture d’écran : traitez donc la publication comme une publication.""",
            ),
        ),
        keywords=(
            "partager",
            "lien",
            "url",
            "envoyer",
            "whatsapp",
            "aperçu",
            "copier",
            "publier",
            "public",
        ),
        related=("share-an-itinerary-privately", "trip-cover-photos"),
        updated="2026-09-01",
        cta="Construisez quelque chose qui mérite d’être envoyé.",
    ),
    Article(
        slug="follow-and-private-accounts",
        title="Abonnés, demandes d’abonnement et comptes privés",
        summary="Comment fonctionne l’abonnement, ce qu’un compte privé masque, et comment approuver ou refuser une demande.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Suivre quelqu’un met ses voyages publics sous vos yeux et lui permet de partager des voyages avec ses abonnés. Si votre compte est **privé**, un abonnement devient une **demande** que vous approuvez ou refusez.",
        blocks=(
            Block(
                anchor="how-to-follow",
                heading="Comment suivre quelqu’un ?",
                kind=KIND_FAQ,
                body="""Trouvez la personne dans l’onglet **Recherche** — il cherche parmi les noms d’utilisateur — et utilisez Suivre sur son profil.

Si son compte est public, vous la suivez immédiatement. S’il est privé, le bouton devient **Demandé** jusqu’à sa décision.""",
            ),
            Block(
                anchor="what-private-hides",
                heading="Que masque un compte privé ?",
                kind=KIND_FAQ,
                body="""Les voyages réglés sur **abonnés** ne deviennent visibles que pour les abonnés que vous avez réellement acceptés, plutôt que pour quiconque a appuyé sur Suivre.

Les voyages que vous réglez sur **public** restent publics — privé concerne qui compte comme abonné, ce n’est pas un verrou général. Si vous voulez tout masquer, réglez les voyages eux-mêmes sur [moi uniquement ou personnes précises](/help/share-an-itinerary-privately).""",
            ),
            Block(
                anchor="handling-requests",
                heading="Où approuver les demandes ?",
                kind=KIND_FAQ,
                body="""Une bannière sur votre profil affiche le compte, et **Paramètres ▸ Demandes d’abonnement** les liste. Acceptez ou refusez chacune.

Le refus n’est pas annoncé. La demande cesse simplement d’être en attente et la personne peut redemander.""",
            ),
            Block(
                anchor="going-public",
                heading="Que se passe-t-il si je passe de privé à public ?",
                kind=KIND_FAQ,
                body="""Toute demande en attente est acceptée automatiquement. Laisser des gens en file derrière un portail que vous venez de retirer ferait une file que personne n’allait jamais rouvrir.

Dans l’autre sens, de public à privé, vos abonnés existants ne sont pas retirés.""",
            ),
            Block(
                anchor="unfollow-vs-block",
                heading="Quelle différence entre se désabonner et bloquer ?",
                kind=KIND_FAQ,
                body="""**Se désabonner** empêche simplement ses voyages d’atteindre votre fil. La personne voit toujours ce qu’elle voyait avant.

**Bloquer** coupe la visibilité dans les deux sens, et la personne bloquée n’en est pas informée. Voir [signaler et bloquer](/help/report-and-block).""",
            ),
        ),
        keywords=(
            "suivre",
            "abonné",
            "abonnés",
            "abonnements",
            "demande",
            "privé",
            "compte public",
            "approuver",
            "accepter",
            "se désabonner",
            "bloquer",
        ),
        related=("share-an-itinerary-privately", "report-and-block"),
        updated="2026-09-01",
        cta="Trouvez les gens dont vous voulez piquer les voyages.",
    ),
    Article(
        slug="rate-a-trip",
        title="Comment fonctionnent les évaluations : sécurité, accessibilité, affluence et plus",
        summary="Une note globale plus cinq dimensions facultatives, et pourquoi les moyennes n’apparaissent qu’à partir de trois évaluations.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Une évaluation, c’est une note **globale** obligatoire sur cinq, et jusqu’à cinq dimensions facultatives : sécurité, expérience, accessibilité, adapté aux familles et affluence. Vous pouvez y joindre un commentaire écrit.",
        blocks=(
            Block(
                anchor="the-dimensions",
                heading="Que signifient les cinq dimensions ?",
                kind=KIND_FAQ,
                body="""- **Sécurité** — à quel point on s’y est senti en sécurité.
- **Expérience** — à quel point c’était réellement bien.
- **Accessibilité** — à quel point cela fonctionne avec une mobilité réduite, une poussette ou de gros bagages.
- **Adapté aux familles** — à quel point cela fonctionne avec des enfants.
- **Affluence** — à quel point c’était agréablement peu fréquenté.

Toutes les dimensions suivent la règle **plus c’est haut, mieux c’est**, affluence comprise : cinq signifie agréablement calme, un signifie bondé. Elles sont toutes facultatives — n’évaluez que ce dont vous pouvez parler.""",
            ),
            Block(
                anchor="three-ratings",
                heading="Pourquoi je ne vois pas de moyenne ?",
                kind=KIND_FAQ,
                body="""Une dimension n’affiche sa moyenne qu’à partir de **trois** évaluations.

L’opinion d’une seule personne présentée comme une moyenne se lit comme un fait sur le lieu plutôt que comme un point de vue, et deux ne valent guère mieux. En dessous de trois, vous voyez les évaluations individuelles à la place.""",
            ),
            Block(
                anchor="who-can-rate",
                heading="Qui peut évaluer un voyage ?",
                kind=KIND_FAQ,
                body="""Toute personne qui peut le voir et dont l’adresse e-mail est vérifiée, sauf son propriétaire. Vous pouvez modifier votre propre évaluation à tout moment — réévaluer la remplace plutôt que d’en ajouter une seconde.

L’exigence de l’e-mail est ce qui tient les comptes jetables à l’écart des notes.""",
            ),
            Block(
                anchor="written-notes",
                heading="Puis-je écrire un avis, pas seulement une note ?",
                kind=KIND_FAQ,
                body="""Oui — la boîte de dialogue d’évaluation comporte un champ de commentaire, et c’est la partie que les autres voyageurs lisent vraiment. Une note dit comment cela s’est passé ; le commentaire dit pourquoi.

Les commentaires sont soumis aux [règles de la communauté](/guidelines) comme tout ce qui est publié.""",
            ),
            Block(
                anchor="disagreeing",
                heading="Quelqu’un a mal évalué mon voyage",
                kind=KIND_FAQ,
                body="""Vous ne pouvez pas supprimer une évaluation de votre propre voyage, et c’est bien l’intention — une note que l’auteur peut effacer ne vaut rien pour le lecteur suivant.

Si une évaluation enfreint les règles plutôt que de simplement vous déplaire, [signalez-la](/help/report-and-block) et une personne l’examinera.""",
            ),
        ),
        keywords=(
            "évaluation",
            "évaluations",
            "noter",
            "avis",
            "commentaire",
            "étoiles",
            "note",
            "sécurité",
            "accessibilité",
            "familles",
            "affluence",
            "fréquentation",
        ),
        related=("save-trips-and-find-new-ones", "report-and-block"),
        updated="2026-09-01",
        cta="Évaluez un voyage que vous avez vraiment fait.",
    ),
    Article(
        slug="save-trips-and-find-new-ones",
        title="Comment enregistrer des voyages et en découvrir de nouveaux",
        summary="Mettez en favori tout ce qui mérite d’être gardé, et comprenez la différence entre les fils Top et Récents.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="L’onglet **Fil** montre les voyages publics de tout le monde. Tout ce qui mérite d’être gardé se met en favori dans l’onglet **Enregistrés**, qui n’appartient qu’à vous — personne n’est informé que vous avez enregistré son voyage.",
        blocks=(
            Block(
                anchor="saving",
                heading="Comment enregistrer un voyage ?",
                kind=KIND_FAQ,
                body="""Appuyez sur le marque-page de n’importe quel voyage que vous pouvez voir. Il apparaît dans votre onglet **Enregistrés**, qui dispose de son propre champ de filtre dès que la liste s’allonge.

Le marque-page ne s’affiche pas sur vos propres voyages — enregistrer ce que vous avez écrit ne servirait à rien.""",
            ),
            Block(
                anchor="saved-changes",
                heading="Et si un voyage enregistré change ou disparaît ?",
                kind=KIND_FAQ,
                body="""Vous voyez toujours la version actuelle, pas celle que vous avez enregistrée.

Si l’auteur en restreint la visibilité ou le supprime, il quitte votre onglet Enregistrés. Un favori est un renvoi, pas une copie — l’auteur garde le contrôle de son propre travail.""",
            ),
            Block(
                anchor="top-vs-recent",
                heading="Quelle différence entre Top et Récents ?",
                kind=KIND_FAQ,
                body="""**Récents**, c’est tout ce qui est public, du plus récent au plus ancien. **Top** est trié par évaluation, et un voyage a besoin de quelques évaluations avant de pouvoir y apparaître.

Récents, c’est là qu’on trouve du nouveau ; Top, c’est là qu’on trouve ce que d’autres ont approuvé.""",
            ),
            Block(
                anchor="not-in-top",
                heading="Pourquoi mon voyage n’est-il pas dans Top ?",
                kind=KIND_FAQ,
                body="""Il doit être public, et il lui faut assez d’évaluations. Un voyage avec une seule note élogieuse ne prouve rien, le fil Top en attend donc quelques-unes.

Partagez-le par [lien](/help/share-a-trip-link) aux gens qui y sont allés — c’est ce qui fait rentrer les premières évaluations.""",
            ),
            Block(
                anchor="finding-people",
                heading="Comment trouver une personne en particulier ?",
                kind=KIND_FAQ,
                body="""L’onglet **Recherche** cherche parmi les noms d’utilisateur, pas les voyages. Les voyages se trouvent par le fil, par un lien qu’on vous a envoyé, ou par un profil une fois la personne trouvée.

Un voyage privé n’est dans aucun fil ni aucune recherche, par conception ; le seul chemin vers lui est une invitation ou un lien de la part de quelqu’un qui peut le voir.""",
            ),
        ),
        keywords=(
            "enregistrer",
            "enregistrés",
            "favori",
            "favoris",
            "marque-page",
            "fil",
            "découvrir",
            "explorer",
            "top",
            "récents",
            "tendances",
            "parcourir",
        ),
        related=("rate-a-trip", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="Trouvez un voyage qui mérite d’être piqué.",
    ),
    Article(
        slug="notifications",
        title="Comment choisir les notifications que Ntripi envoie",
        summary="Les huit choses dont Ntripi vous informera, les trois que vous pouvez désactiver, et pourquoi les autres restent actives.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="La cloche à côté de l’engrenage sur votre profil, c’est toute la liste. Trois sortes de notifications peuvent être désactivées dans **Paramètres ▸ Notifications** ; les autres restent actives parce qu’on ne peut pas agir à temps sur ce qu’on n’a pas vu.",
        blocks=(
            Block(
                anchor="what-you-get",
                heading="De quoi Ntripi va-t-il me prévenir ?",
                kind=KIND_FAQ,
                body="""- Quelqu’un a demandé à vous suivre, ou s’est abonné à vous
- Quelqu’un a accepté votre demande d’abonnement *(facultatif)*
- Quelqu’un a évalué l’un de vos voyages *(facultatif)*
- Quelqu’un a enregistré l’un de vos voyages *(facultatif)*
- Vous avez été invité à modifier un voyage
- On vous a donné accès à un voyage
- Une décision de modération a touché votre contenu ou votre compte

Rien d’autre. Pas de marketing, pas de relance pour vous faire revenir, pas de résumé périodique.""",
            ),
            Block(
                anchor="switching-off",
                heading="Comment en désactiver certaines ?",
                kind=KIND_FAQ,
                body="""**Paramètres ▸ Notifications** comporte trois interrupteurs : évaluations, enregistrements, et abonnement accepté. En désactiver un empêche la notification d’être créée du tout, et pas seulement de s’afficher.

Pour tout faire taire, désactivez les notifications de Ntripi dans les réglages de votre téléphone — voir [les autorisations](/help/permissions).""",
            ),
            Block(
                anchor="always-on",
                heading="Pourquoi ne puis-je pas désactiver les autres ?",
                kind=KIND_FAQ,
                body="""Les demandes d’abonnement, les octrois d’accès et les décisions de modération réclament tous une réponse de votre part dans un délai utile.

Une demande d’abonnement que personne ne voit n’obtient jamais de réponse. Un voyage que l’on a partagé avec vous n’est dans aucun fil ni aucune recherche : un avis que vous n’avez pas reçu est un accès dont vous n’avez jamais su qu’il existait. Et une décision de modération a un délai de recours — le silence vous coûterait le recours.""",
            ),
            Block(
                anchor="arrival",
                heading="Pourquoi certaines arrivent-elles en retard ?",
                kind=KIND_FAQ,
                body="""La distribution push relève partout du meilleur effort : les gestionnaires de batterie arrêtent les processus en arrière-plan, les téléphones brident, les connexions tombent.

Ntripi vérifie donc aussi de lui-même environ une fois par minute quand il est ouvert, pour que la cloche soit juste même si aucun push n’est arrivé. Si le push est désactivé ou refusé, cette vérification est le seul canal — et elle fonctionne toujours.""",
            ),
            Block(
                anchor="clearing",
                heading="Puis-je supprimer des notifications ?",
                kind=KIND_FAQ,
                body="""Oui, une par une ou toutes d’un coup, avec quelques secondes pour annuler avant que ce soit définitif.

Supprimer un avis de modération ne supprime pas la décision — elle reste dans **Paramètres ▸ État du compte**, avec le bouton de recours. Les notifications lues sont effacées au bout de quatre-vingt-dix jours ; les non lues restent plus longtemps, parce qu’elles sont votre seule trace qu’il s’est passé quelque chose.""",
            ),
        ),
        keywords=(
            "notification",
            "notifications",
            "push",
            "alertes",
            "cloche",
            "pastille",
            "couper",
            "désactiver",
            "e-mail",
            "silence",
        ),
        related=("permissions", "follow-and-private-accounts"),
        updated="2026-09-01",
        cta="Suivez vos voyages sans le bruit.",
    ),
    Article(
        slug="app-settings",
        title="Langue, mode sombre, sons et retours haptiques",
        summary="Tous les réglages derrière l’engrenage de votre profil, et ce que chacun change.",
        category="account",
        intro="L’engrenage de votre propre profil ouvre tout. Les réglages sont stockés sur votre appareil, ils sont donc propres à chaque installation : changer le thème sur votre téléphone ne le change pas sur votre tablette.",
        blocks=(
            Block(
                anchor="language",
                heading="Langue",
                body="""Ntripi est disponible en anglais, français, arabe, allemand, espagnol et chinois. L’application suit la langue de votre appareil quand c’est l’une des six, et vous pouvez la remplacer ici.

L’arabe bascule toute l’interface de droite à gauche. Ce choix suit aussi les documents juridiques et ce centre d’aide quand vous les ouvrez depuis l’application.""",
            ),
            Block(
                anchor="theme",
                heading="Thème",
                body="""Système, Clair ou Sombre. **Système** suit votre téléphone, y compris son passage automatique jour/nuit, et c’est la valeur par défaut.

Le mode sombre est un vrai noir, pas un gris — bon à savoir si vous lisez vos plans au lit.""",
            ),
            Block(
                anchor="sounds-and-haptics",
                heading="Effets sonores et retours haptiques",
                body="""Deux interrupteurs indépendants. Les **effets sonores** sont les petits repères — une notification qui arrive, une évaluation qui se pose. Les **retours haptiques** sont les impulsions que vous sentez, dont une courte vibration par étoile quand vous donnez une note.

Chacun s’annonce lui-même avec le réglage que vous venez de choisir, pour que vous entendiez ou sentiez ce que vous activez.""",
            ),
            Block(
                anchor="shake-to-report",
                heading="Secouer pour signaler",
                body="""Activé par défaut sur téléphone : secouer capture l’écran et ouvre un signalement de bug. Si vous gesticulez beaucoup en lisant, désactivez-le ici — **Paramètres ▸ Assistance ▸ Secouer pour signaler**.

C’est délibérément difficile à déclencher par accident : il faut deux secousses distinctes, l’application vous ignore si elle n’est pas au premier plan, et elle attend quelques secondes avant de pouvoir se redéclencher.""",
            ),
            Block(
                anchor="account-rows",
                heading="Le reste du menu",
                body="""- **État du compte** — décisions de modération et recours
- **Comptes bloqués** — toutes les personnes que vous avez bloquées, et un appui pour débloquer
- **Demandes d’abonnement** — affiché seulement si votre compte est privé
- **Centre d’aide** et **À propos** — dont ce site

Changer votre mot de passe ou supprimer votre compte se trouve sur l’écran de modification de votre profil, sous Sécurité.""",
            ),
        ),
        keywords=(
            "paramètres",
            "réglages",
            "langue",
            "traduire",
            "mode sombre",
            "mode clair",
            "thème",
            "son",
            "sons",
            "haptique",
            "vibration",
            "préférences",
        ),
        related=("app-map", "notifications", "permissions"),
        updated="2026-09-01",
        cta="Faites de l’application la vôtre.",
    ),
    Article(
        slug="permissions",
        title="Quelles autorisations Ntripi demande, et pourquoi",
        summary="Localisation, notifications, photos et mouvement — à quoi sert chacune, quand on vous la demande, et comment changer d’avis.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi demande quatre choses, chacune au moment où elle devient utile plutôt qu’au lancement. **Elle ne demande jamais votre appareil photo, vos contacts, votre micro, ni votre position en arrière-plan.** Refuser l’une d’elles laisse l’application fonctionnelle.",
        blocks=(
            Block(
                anchor="location",
                heading="Localisation — pourquoi ?",
                kind=KIND_FAQ,
                body="""Pour centrer la carte sur votre position quand vous ajoutez une étape, afin de ne pas traverser un continent pour retrouver la ville où vous vous tenez.

Elle est demandée la première fois que vous utilisez le bouton de localisation de la carte, et **uniquement pendant que vous utilisez l’application** — pas de position en arrière-plan, pas de pistage. La refuser ne bloque rien : la carte s’ouvre ailleurs et vous vous déplacez jusqu’à votre point.""",
            ),
            Block(
                anchor="notifications",
                heading="Notifications — pourquoi, et pourquoi une seule fois ?",
                kind=KIND_FAQ,
                body="""Pour vous informer des demandes d’abonnement, des évaluations, des enregistrements et des décisions de modération.

Elles sont demandées la première fois que vous ouvrez l’**écran des notifications** — c’est-à-dire au moment où vous venez de montrer que vous les voulez. iOS n’autorise qu’une seule demande par installation : la poser au lancement, devant une application que vous n’avez pas encore vue, dépenserait cette unique chance auprès d’un inconnu.""",
            ),
            Block(
                anchor="photos",
                heading="Photos — que voit Ntripi ?",
                kind=KIND_FAQ,
                body="""Seulement l’image que vous choisissez. Ntripi ouvre le sélecteur de photos de votre système, qui renvoie un seul fichier et rien d’autre — l’application n’a aucune vue sur votre photothèque.

Chaque envoi voit ses **métadonnées EXIF supprimées**, y compris les coordonnées GPS du lieu de la prise de vue. Voir [les photos de couverture](/help/trip-cover-photos).""",
            ),
            Block(
                anchor="motion",
                heading="Mouvement et vibration — pour quoi faire ?",
                kind=KIND_FAQ,
                body="""Secouer le téléphone dépose un signalement de bug, et le téléphone vibre brièvement pour accuser réception de choses comme une note donnée.

Les deux se désactivent dans les **Paramètres** : **Secouer pour signaler** et **Retours haptiques**. Rien de vos mouvements ne quitte l’appareil.""",
            ),
            Block(
                anchor="never-asked",
                heading="Que Ntripi ne demande jamais",
                kind=KIND_FAQ,
                body="""L’**appareil photo**, vos **contacts**, votre **micro**, et la **position en arrière-plan**. Aucun n’apparaît dans l’application, et aucun n’est déclaré dans les versions que nous publions.

Si quelque chose prétend un jour que Ntripi demande l’un d’eux, ce n’est pas nous — [dites-le-nous](/help/contact).""",
            ),
            Block(
                anchor="changing-your-mind",
                heading="Comment changer une autorisation plus tard ?",
                kind=KIND_FAQ,
                body="""Les autorisations appartiennent à votre système d’exploitation, pas à Ntripi, elles se changent donc là-bas :

- **iPhone ou iPad** — Réglages ▸ faire défiler jusqu’à Ntripi ▸ activer ou désactiver Position ou Notifications.
- **Android** — Paramètres ▸ Applications ▸ Ntripi ▸ Autorisations.

Cela compte surtout pour les notifications, qu’iOS ne redemandera pas : une fois refusées, l’application Réglages est le seul retour possible.""",
            ),
        ),
        keywords=(
            "autorisation",
            "autorisations",
            "permissions",
            "confidentialité",
            "localisation",
            "gps",
            "appareil photo",
            "caméra",
            "photos",
            "notifications",
            "micro",
            "contacts",
            "pistage",
            "suivi",
            "autoriser",
            "refuser",
        ),
        related=("your-data-and-privacy", "notifications", "add-locations-from-google-maps"),
        updated="2026-09-01",
        cta="Voyez exactement ce que l’application demande — et ne demande pas.",
    ),
    Article(
        slug="your-data-and-privacy",
        title="Quelles données Ntripi conserve, et comment les supprimer",
        summary="Un résumé en langage clair de ce qui est conservé, de qui peut le voir, et de comment supprimer votre compte pour de bon.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi conserve ce que vous écrivez et ce que vous envoyez, plus ce qu’il faut pour vous connecter. Il n’y a pas de publicité, pas de pistage publicitaire tiers, et rien n’est vendu. La [politique de confidentialité](/privacy) est le texte qui fait foi ; ceci en est la version courte.",
        blocks=(
            Block(
                anchor="what-is-stored",
                heading="Quelles données Ntripi conserve-t-il sur moi ?",
                kind=KIND_FAQ,
                body="""- **Votre compte** — nom affiché, nom d’utilisateur, adresse e-mail et date de naissance (jamais montrée à personne).
- **Ce que vous créez** — voyages, étapes, notes, évaluations et toutes les images que vous envoyez.
- **Vos liens** — qui vous suivez, qui vous suit, qui vous avez bloqué.
- **Données de session** — de quoi vous garder connecté, et un jeton d’appareil si vous avez activé les notifications push.

Les images envoyées voient leurs métadonnées EXIF supprimées, y compris les coordonnées GPS du lieu de la prise de vue.""",
            ),
            Block(
                anchor="who-sees-it",
                heading="Qui peut voir ce que j’écris ?",
                kind=KIND_FAQ,
                body="""Ceux que désigne votre [réglage de visibilité](/help/share-an-itinerary-privately), et personne d’autre. Un voyage réglé sur **moi uniquement** est visible par vous et par les personnes que vous avez invitées à le modifier.

Votre date de naissance n’est jamais visible par un autre utilisateur, quel que soit le réglage. Votre adresse e-mail n’apparaît pas sur votre profil.""",
            ),
            Block(
                anchor="moderation",
                heading="Est-ce que quelqu’un chez Ntripi lit mes voyages ?",
                kind=KIND_FAQ,
                body="""Pas de façon systématique. Les textes et les images sont vérifiés automatiquement à la publication, et une personne ne regarde quelque chose que lorsque c’est signalé ou marqué par ces vérifications.

Les vérifications automatiques envoient le contenu et rien d’autre — pas d’identifiant, pas d’e-mail, pas de nom.""",
            ),
            Block(
                anchor="deleting",
                heading="Comment supprimer mon compte ?",
                kind=KIND_FAQ,
                body="""Sur l’écran de modification de votre profil, sous Sécurité ▸ **Supprimer le compte**. Vous confirmez avec votre mot de passe, ou avec Google si c’est ainsi que vous vous connectez.

La suppression est définitive et emporte vos voyages avec elle. Les voyages que d’autres avaient enregistrés cessent de fonctionner, puisqu’un favori est un renvoi et non une copie.""",
            ),
            Block(
                anchor="requests",
                heading="Comment demander une copie de mes données ?",
                kind=KIND_FAQ,
                body="""Écrivez à **[privacy@ntripi.app](mailto:privacy@ntripi.app)**. Cette adresse est le contact de protection des données nommé dans la [politique de confidentialité](/privacy), et elle atteint les personnes capables de traiter réellement une demande.

La même adresse couvre les demandes de rectification, de limitation et d’opposition.""",
            ),
        ),
        keywords=(
            "confidentialité",
            "vie privée",
            "données",
            "rgpd",
            "supprimer mon compte",
            "effacer",
            "exporter",
            "données personnelles",
            "pistage",
            "publicité",
            "qui peut voir",
        ),
        related=("permissions", "sign-in-and-account-security", "share-an-itinerary-privately"),
        updated="2026-09-01",
    ),
    Article(
        slug="sign-in-and-account-security",
        title="Connexion, mots de passe et suppression du compte",
        summary="Connexion par e-mail, Google ou Apple, réinitialisation d’un mot de passe, pourquoi certaines actions exigent un e-mail vérifié, et comment partir.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Vous pouvez vous connecter avec une adresse e-mail et un mot de passe, avec Google, ou avec Apple. Les trois mènent au même compte, et vous pouvez ajouter un mot de passe plus tard à un compte créé avec Google.",
        blocks=(
            Block(
                anchor="forgot-password",
                heading="J’ai oublié mon mot de passe",
                kind=KIND_FAQ,
                body="""Utilisez **Mot de passe oublié** sur l’écran de connexion. Un lien de réinitialisation arrive par e-mail et reste valable un court moment.

Si aucun message n’arrive, regardez dans les indésirables et vérifiez que vous utilisez bien l’adresse avec laquelle vous vous êtes inscrit. Si vous vous êtes inscrit avec Google, vous n’avez peut-être aucun mot de passe — connectez-vous avec Google.""",
            ),
            Block(
                anchor="verify-email",
                heading="Pourquoi ne puis-je pas créer un voyage, évaluer ou suivre ?",
                kind=KIND_FAQ,
                body="""Ces trois actions exigent une adresse e-mail vérifiée. Cherchez le lien de vérification dans votre boîte de réception, ou utilisez la bannière de votre profil pour en renvoyer un.

Se connecter avec Google sur la même adresse la vérifie aussi. Cette exigence est ce qui tient les comptes jetables à l’écart des évaluations et des listes d’abonnés.""",
            ),
            Block(
                anchor="changing-password",
                heading="Comment changer mon mot de passe ?",
                kind=KIND_FAQ,
                body="""Profil ▸ modifier ▸ **Sécurité ▸ Changer le mot de passe**. Vous confirmez avec l’actuel.

Le changer déconnecte toutes les **autres** sessions et conserve celle que vous utilisez — si vous le changez parce que vous pensez que quelqu’un s’est introduit, cela seul l’expulse.""",
            ),
            Block(
                anchor="age",
                heading="Pourquoi Ntripi demande-t-il ma date de naissance ?",
                kind=KIND_FAQ,
                body="""Ntripi impose un âge minimum de **16 ans**, et les [conditions](/terms) le disent, ce qui suppose de le demander plutôt que de le supposer.

Elle n’apparaît jamais sur votre profil et n’est jamais visible par un autre utilisateur. Elle est demandée une fois et ne l’est plus.""",
            ),
            Block(
                anchor="suspended",
                heading="Mon compte est suspendu",
                kind=KIND_FAQ,
                body="""Vous aurez reçu un e-mail expliquant pourquoi, avec un lien pour former un recours. Les recours sont lus par une personne.

Si vous n’avez plus l’e-mail, le formulaire de recours peut vous envoyer un nouveau lien. Voir [contenus masqués et recours](/help/hidden-content-and-appeals).""",
            ),
            Block(
                anchor="deleting",
                heading="Comment supprimer mon compte ?",
                kind=KIND_FAQ,
                body="""Profil ▸ modifier ▸ **Sécurité ▸ Supprimer le compte**, confirmé par votre mot de passe ou par Google.

C’est définitif, et cela emporte vos voyages. Si vous voulez seulement disparaître de la vue, régler vos voyages sur [moi uniquement](/help/share-an-itinerary-privately) et passer votre compte en privé est réversible, là où la suppression ne l’est pas.""",
            ),
        ),
        keywords=(
            "connexion",
            "se connecter",
            "identifiant",
            "mot de passe",
            "mot de passe oublié",
            "réinitialiser",
            "google",
            "apple",
            "vérifier",
            "vérification",
            "e-mail",
            "bloqué dehors",
            "supprimer le compte",
            "âge",
            "16 ans",
        ),
        related=("your-data-and-privacy", "troubleshooting"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-and-block",
        title="Comment signaler un contenu ou bloquer quelqu’un",
        summary="Signalez un voyage, un avis ou un profil qui enfreint les règles, et coupez court avec quelqu’un dont vous préférez vous passer.",
        category="safety",
        schema=SCHEMA_HOWTO,
        intro="Signaler envoie quelque chose à la modération ; bloquer retire une personne de votre expérience. Ce sont deux outils différents et vous pouvez utiliser les deux. Ni l’un ni l’autre n’informe l’autre personne de ce que vous avez fait.",
        blocks=(
            Block(
                anchor="report",
                heading="Signaler un voyage, un avis ou un profil",
                kind=KIND_STEP,
                body="""Utilisez l’action drapeau sur l’élément lui-même — un voyage, une étape, un avis, une note ou un profil. Choisissez un motif et ajoutez tout ce qui peut aider.

Signaler depuis l’élément emporte le contexte avec lui, c’est pourquoi cela vaut mieux que de nous envoyer une description par e-mail. Vous n’avez pas besoin de compte pour signaler depuis une page de partage publique.""",
            ),
            Block(
                anchor="reasons",
                heading="Choisir un motif",
                body="""Les motifs sont : contenu d’abus sexuel sur mineur, contenu sexuel, violence ou menaces, discours haineux, harcèlement, spam, et autre.

Choisissez le plus proche — c’est lui qui décide de l’urgence du traitement. **Tout ce qui implique un enfant est traité en priorité absolue** et part dans une file distincte.""",
            ),
            Block(
                anchor="what-happens",
                heading="Que se passe-t-il après un signalement ?",
                body="""Il rejoint la file de modération. Un contenu signalé par plusieurs personnes différentes, ou corroboré par les vérifications automatiques, peut être masqué immédiatement pendant qu’une personne l’examine.

L’auteur n’apprend jamais qui l’a signalé. Vous n’aurez généralement pas de réponse — le résultat, c’est le contenu qui reste ou qui part.""",
            ),
            Block(
                anchor="block",
                heading="Bloquer quelqu’un",
                kind=KIND_STEP,
                body="""Depuis son profil, ou en gardant le doigt sur quelque chose qu’il a publié.

Bloquer coupe la visibilité **dans les deux sens** : vous cessez de le voir et il cesse de vous voir. Tout abonnement entre vous est supprimé. La personne n’en est pas informée, et votre profil devient pour elle indiscernable d’un profil qui n’a jamais existé.""",
            ),
            Block(
                anchor="unblock",
                heading="Débloquer quelqu’un",
                kind=KIND_STEP,
                body="""**Paramètres ▸ Comptes bloqués** liste toutes les personnes que vous avez bloquées, avec un appui pour revenir en arrière.

Débloquer ne rétablit pas l’abonnement supprimé par le blocage — l’un ou l’autre peut se réabonner s’il le souhaite.""",
            ),
            Block(
                anchor="urgent",
                heading="Si quelqu’un est en danger",
                body="""Contactez d’abord vos services d’urgence locaux. Ntripi ne peut joindre personne assez vite pour être le bon premier appel.

Écrivez ensuite à **[abuse@ntripi.app](mailto:abuse@ntripi.app)**, qui est surveillée exactement pour cela.""",
            ),
        ),
        keywords=(
            "signaler",
            "signalement",
            "drapeau",
            "bloquer",
            "abus",
            "harcèlement",
            "spam",
            "dangereux",
            "inapproprié",
            "débloquer",
            "sécurité",
        ),
        related=("hidden-content-and-appeals", "follow-and-private-accounts", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="hidden-content-and-appeals",
        title="Pourquoi votre contenu a été masqué, et comment former un recours",
        summary="Ce que signifie un voyage ou un avis masqué, où en voir le motif, et comment demander qu’une personne le réexamine.",
        category="safety",
        schema=SCHEMA_FAQ,
        intro="Si quelque chose que vous avez publié a été masqué, vous recevez une notification et un motif, et **Paramètres ▸ État du compte** en garde la trace. La plupart des décisions peuvent être contestées, et un recours est lu par une personne.",
        blocks=(
            Block(
                anchor="what-hidden-means",
                heading="Que signifie « masqué » ?",
                kind=KIND_FAQ,
                body="""Personne d’autre ne peut l’ouvrir. **Vous, si** — cela reste dans votre liste avec une bannière expliquant pourquoi, et rien n’est supprimé tant qu’un recours est possible.

Masquer est réversible là où supprimer ne l’est pas, c’est pourquoi c’est la première étape et non la dernière.""",
            ),
            Block(
                anchor="why",
                heading="Pourquoi le mien a-t-il été masqué ?",
                kind=KIND_FAQ,
                body="""Soit assez de personnes différentes l’ont signalé, soit une vérification automatique l’a marqué, soit un modérateur a estimé qu’il enfreint les [règles de la communauté](/guidelines).

Le motif est sur la bannière et dans **Paramètres ▸ État du compte**. Certains masquages sont provisoires — appliqués automatiquement en attendant qu’une personne s’en occupe — et c’est précisément pourquoi ils sont contestables.""",
            ),
            Block(
                anchor="appealing",
                heading="Comment former un recours ?",
                kind=KIND_FAQ,
                body="""**Paramètres ▸ État du compte** liste chaque décision avec un bouton de recours. Expliquez avec vos mots pourquoi vous la jugez erronée.

Un seul recours ouvert par décision, et une seule tentative par décision sur un mois — cette limite existe pour que la file reste assez courte pour que les recours soient réellement lus.""",
            ),
            Block(
                anchor="warnings",
                heading="J’ai reçu un avertissement mais rien n’a été masqué",
                kind=KIND_FAQ,
                body="""Un avertissement est une mention sur votre compte, sans retrait. C’est un signal, et c’est aussi une trace — un deuxième avertissement est enregistré comme un deuxième, il n’est pas fondu dans le premier.

Les avertissements peuvent être contestés comme le reste.""",
            ),
            Block(
                anchor="suspended",
                heading="Tout mon compte est suspendu",
                kind=KIND_FAQ,
                body="""Vous ne pouvez pas vous connecter, le recours ne peut donc pas vivre dans l’application. L’e-mail de suspension contient un lien vers un formulaire web ; si vous ne l’avez plus, le formulaire peut envoyer un nouveau lien à votre adresse.

Les suspensions sont réversibles, et un recours qui aboutit rétablit le compte plutôt que de le reconstruire.""",
            ),
            Block(
                anchor="after",
                heading="Que se passe-t-il après mon recours ?",
                kind=KIND_FAQ,
                body="""Une personne le lit et soit rétablit le contenu, soit maintient la décision, et on vous dit laquelle des deux.

Si une décision est annulée, le contenu revient tel qu’il était — rien n’avait été supprimé entre-temps.""",
            ),
        ),
        keywords=(
            "masqué",
            "caché",
            "supprimé",
            "retrait",
            "modération",
            "recours",
            "contestation",
            "banni",
            "suspendu",
            "avertissement",
            "contenu bloqué",
            "rétabli",
        ),
        related=("report-and-block", "sign-in-and-account-security", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="troubleshooting",
        title="Ntripi ne fonctionne pas : problèmes courants et solutions",
        summary="Les messages que l’on rencontre le plus souvent, ce que chacun veut vraiment dire, et quoi faire ensuite.",
        category="troubleshooting",
        schema=SCHEMA_FAQ,
        intro="La plupart des problèmes dans Ntripi viennent de trois choses : deux personnes qui modifient le même voyage, une connexion perdue, ou une étape de compte qui n’a pas encore été faite. Trouvez ci-dessous le message que vous avez vu.",
        blocks=(
            Block(
                anchor="modified-please-reload",
                heading="« Cet itinéraire a été modifié, veuillez recharger »",
                kind=KIND_FAQ,
                body="""Le voyage a changé après que votre écran l’a chargé — généralement parce que vous l’avez ouvert sur un autre appareil, ou parce qu’une personne que vous avez invitée à modifier a enregistré avant vous.

Rechargez le voyage et refaites votre modification. Ntripi refuse l’enregistrement plutôt que d’écraser en silence ce qui est arrivé pendant que vous écriviez.""",
            ),
            Block(
                anchor="someone-else-is-editing",
                heading="« Quelqu’un d’autre est en train de modifier ce voyage »",
                kind=KIND_FAQ,
                body="""Une seule personne peut modifier un voyage à la fois. Quelqu’un d’autre — ou vous, sur un autre appareil — le détient actuellement.

Attendez qu’il ait fini, ou reprenez la main s’il est resté inactif un moment. Si vous êtes le propriétaire, vous pouvez toujours la reprendre. Reprendre la main met fin à la session de l’autre personne : elle en sera informée plutôt que de perdre son travail en silence.""",
            ),
            Block(
                anchor="lost-the-edit",
                heading="J’étais en train de modifier et l’enregistrement ne marche plus",
                kind=KIND_FAQ,
                body="""Quelqu’un a repris le voyage pendant que vous l’aviez ouvert. **Ce que vous avez saisi n’est pas perdu** — l’écran reste exactement tel qu’il était, tous les champs encore remplis.

Deux sorties possibles, et toutes deux préservent votre travail : reprenez le voyage et enregistrez, ou copiez votre texte et collez-le une fois l’autre personne terminée. Rien n’est jeté tant que vous ne quittez pas l’écran vous-même.""",
            ),
            Block(
                anchor="image-rejected",
                heading="Ma photo a été refusée lors de l’envoi",
                kind=KIND_FAQ,
                body="""Les envois sont vérifiés automatiquement avant d’être stockés. Une image peut être refusée parce qu’elle est trop petite, parce que son format n’est pas pris en charge, ou pour un contenu qui ne respecte pas les [règles de la communauté](/guidelines).

Essayez une image plus grande, au moins 600 pixels sur son plus petit côté. Si vous pensez qu’un refus était injustifié, [contactez-nous](/help/contact).""",
            ),
            Block(
                anchor="text-rejected",
                heading="Mon texte a été refusé au moment d’enregistrer",
                kind=KIND_FAQ,
                body="""Le texte que vous écrivez est vérifié au regard des [règles de la communauté](/guidelines) avant d’être stocké.

Vous pouvez aussi voir un discret message d’avertissement sous un champ pendant que vous tapez. Celui-là n’est qu’un avertissement — il ne vous bloque jamais et ne modifie jamais ce que vous avez écrit. Les noms de lieux en particulier peuvent déclencher un avertissement sans poser le moindre problème.""",
            ),
            Block(
                anchor="cannot-create",
                heading="Je ne peux pas créer de voyage, en évaluer un, ni suivre quelqu’un",
                kind=KIND_FAQ,
                body="""Ces actions exigent une adresse e-mail vérifiée. Cherchez le lien de vérification dans votre boîte de réception, ou utilisez la bannière de votre profil pour en renvoyer un.

Se connecter avec Google sur la même adresse la vérifie aussi.""",
            ),
            Block(
                anchor="offline",
                heading="Une barre m’indique que je suis hors ligne",
                kind=KIND_FAQ,
                body="""Ntripi a remarqué que la connexion est tombée. Vous pouvez continuer à lire tout ce qui est déjà chargé ; les commandes qui auraient besoin du serveur sont estompées jusqu’à votre retour.

La barre disparaît d’elle-même au retour de la connexion — il n’y a rien à toucher.""",
            ),
            Block(
                anchor="still-stuck",
                heading="Rien de tout cela ne correspond à ce que je vois",
                kind=KIND_FAQ,
                body="Signalez-le depuis l’application : **secouez votre téléphone** et Ntripi capture l’écran pour que vous puissiez entourer le problème avant d’envoyer. Voir [comment nous contacter](/help/contact).",
            ),
        ),
        keywords=(
            "erreur",
            "problème",
            "problèmes",
            "cassé",
            "ne fonctionne pas",
            "échec",
            "bloqué",
            "impossible d’enregistrer",
            "recharger",
            "hors ligne",
            "plantage",
            "bug",
            "réparer",
            "aide",
        ),
        related=("contact", "getting-started"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-a-bug",
        title="Comment signaler un bug dans Ntripi",
        summary="Secouez votre téléphone pour capturer l’écran, entourez ce qui cloche et envoyez — ou utilisez le bouton sur le web.",
        category="troubleshooting",
        schema=SCHEMA_HOWTO,
        intro="**Secouez votre téléphone.** Ntripi capture l’écran que vous regardiez, vous tend un stylo pour entourer le problème, et l’envoie avec votre commentaire. C’est bien plus rapide que de décrire une mise en page avec des mots, et l’appareil et la version sont joints pour vous.",
        blocks=(
            Block(
                anchor="shake",
                heading="Secouer le téléphone",
                kind=KIND_STEP,
                body="""N’importe où dans l’application, au moment où quelque chose semble anormal. Une capture de cet écran précis est prise.

Il faut deux secousses distinctes, donc une marche ou un trajet en bus ne le déclenchera pas. C’est aussi ignoré quand l’application est en arrière-plan, et il faut attendre quelques secondes avant un nouveau déclenchement.""",
            ),
            Block(
                anchor="draw",
                heading="Entourer le problème",
                kind=KIND_STEP,
                body="""Dessinez directement sur la capture d’écran. Un cercle autour de ce qui ne va pas remplace un paragraphe entier d’explications.

Vous pouvez naviguer pendant que le rapporteur est ouvert si vous devez capturer un autre écran.""",
            ),
            Block(
                anchor="describe",
                heading="Choisir une catégorie et décrire",
                kind=KIND_STEP,
                body="""Choisissez parmi : plantage, visuel, données, lenteur, ou autre. Dites ensuite ce que vous avez fait, ce que vous attendiez, et ce qui s’est produit.

Rien n’est envoyé tant que vous n’appuyez pas sur envoyer.""",
            ),
            Block(
                anchor="what-is-sent",
                heading="Ce qui part avec le signalement",
                body="""Votre commentaire, votre catégorie, la capture d’écran, et des détails techniques sur l’appareil et la version de l’application — les choses fastidieuses à saisir et qui sont toujours les premières questions.

La capture d’écran voit ses métadonnées supprimées comme tout autre envoi. Elle n’est jamais montrée à un autre utilisateur, et les signalements de bugs sont supprimés une fois clos et anciens, parce qu’une capture d’écran peut contenir les informations de quelqu’un d’autre.""",
            ),
            Block(
                anchor="web-and-off",
                heading="Sur le web, ou avec le geste désactivé",
                body="""Les navigateurs ne savent pas détecter une secousse : sur le web, utilisez **Paramètres ▸ Assistance ▸ Signaler un bug**, qui ouvre le même rapporteur.

Si vous avez désactivé le geste sur un téléphone, la même entrée de menu fonctionne toujours. Pour le réactiver : **Paramètres ▸ Assistance ▸ Secouer pour signaler**.""",
            ),
        ),
        keywords=(
            "bug",
            "bugs",
            "signaler",
            "cassé",
            "plantage",
            "retour",
            "secouer",
            "capture d’écran",
            "problème",
            "anomalie",
        ),
        related=("troubleshooting", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="contact",
        title="Comment contacter l’assistance Ntripi",
        summary="Où envoyer un bug, un problème de sécurité, une demande de confidentialité ou une question générale — et quoi y mettre.",
        category="about",
        schema=SCHEMA_CONTACT,
        intro="Le moyen le plus rapide de signaler un problème dans l’application est de **secouer votre téléphone** — Ntripi capture l’écran et vous laisse dessiner dessus avant l’envoi. Pour tout le reste, utilisez ci-dessous l’adresse qui correspond à votre besoin.",
        blocks=(
            Block(
                anchor="report-a-bug",
                heading="Signaler un bug depuis l’application",
                body="""**Secouez votre téléphone.** Ntripi prend une capture d’écran, vous tend un stylo pour entourer ce qui ne va pas, et vous laisse ajouter un commentaire et une catégorie avant l’envoi.

La capture part avec le signalement, ce qui vous évite de décrire une mise en page avec des mots. Rien n’est envoyé tant que vous n’appuyez pas sur envoyer.

Vous pouvez désactiver le geste dans **Paramètres ▸ Assistance ▸ Secouer pour signaler**. Sur le web il n’y a pas de secousse : utilisez **Paramètres ▸ Assistance ▸ Signaler un bug**.""",
            ),
            Block(
                anchor="email-us",
                heading="Nous écrire",
                body="""- **[support@ntripi.app](mailto:support@ntripi.app)** — l’application est cassée, ou vous êtes bloqué.
- **[abuse@ntripi.app](mailto:abuse@ntripi.app)** — un contenu ou un comportement qui enfreint les [règles de la communauté](/guidelines), et tout ce qui est urgent concernant la sécurité de quelqu’un.
- **[privacy@ntripi.app](mailto:privacy@ntripi.app)** — demandes de protection des données, et tout ce que couvre la [politique de confidentialité](/privacy).
- **[contact@ntripi.app](mailto:contact@ntripi.app)** — tout le reste.""",
            ),
            Block(
                anchor="what-to-include",
                heading="Quoi indiquer",
                body="""Un signalement est bien plus rapide à traiter avec :

- **Ce que vous avez fait**, dans l’ordre où vous l’avez fait.
- **Ce que vous attendiez**, et ce qui s’est produit à la place.
- **Une capture d’écran**, si le problème est visible.
- **Votre appareil et la version de l’application** — le rapporteur intégré les joint automatiquement, une raison de plus de l’utiliser quand c’est possible.""",
            ),
            Block(
                anchor="reporting-content",
                heading="Signaler un contenu plutôt qu’un bug",
                body="""Pour signaler quelque chose qu’une autre personne a publié, utilisez l’action drapeau sur le voyage, l’avis ou le profil lui-même plutôt que l’e-mail. Cela rejoint directement la file de modération et emporte le contexte avec soi.

Les signalements ne sont pas montrés à la personne signalée.""",
            ),
        ),
        keywords=(
            "assistance",
            "support",
            "e-mail",
            "contact",
            "aide",
            "retour",
            "bug",
            "bugs",
            "signaler",
            "abus",
            "confidentialité",
            "réclamation",
        ),
        related=("troubleshooting",),
        updated="2026-09-01",
    ),
    Article(
        slug="whats-new",
        title="Nouveautés de Ntripi",
        summary="Versions récentes : ce qui a été ajouté, ce qui a changé et ce qui a été corrigé.",
        category="about",
        schema=SCHEMA_RELEASES,
        intro="Ntripi est en développement actif avant son lancement public. Chaque version ci-dessous indique ce qui a changé et pourquoi cela peut vous concerner.",
        releases=RELEASES,
        keywords=(
            "journal des modifications",
            "notes de version",
            "mises à jour",
            "nouveautés",
            "version",
            "changements",
            "ce qui a changé",
            "historique",
        ),
        related=("getting-started", "contact"),
        updated="2026-09-01",
    ),
)
