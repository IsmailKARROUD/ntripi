"""
constants/help/en.py — the English help centre. Authoritative.

One module per language, mirroring constants/legal/: a reviewer for fr.py reads
everything a French visitor will ever see, in one place. English is the spine —
articles() in __init__.py substitutes English per *slug*, so a half-finished
translation ships what it has beside English for the rest.

Titles are problem-shaped, not feature-shaped: someone who has never heard of
Ntripi searches for the problem ("plan two options for the same day"), not for
our word for the solution ("tracks"). The feature name lives in a block heading
and in `keywords` so it stays findable either way.

`intro` is the direct answer in 40-60 words. It is what a search engine lifts
into a featured snippet and what an assistant quotes, so it must stand alone
without the blocks beneath it.
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

# ---------------------------------------------------------------------------
# Categories. Declared in hub display order. A category with no articles yet is
# skipped by the hub template, so this list can run ahead of the content.
# ---------------------------------------------------------------------------

CATEGORIES: tuple[Category, ...] = (
    Category(
        id="getting-started",
        title="Getting started",
        blurb="Set up an account and plan your first trip.",
        icon="rocket",
    ),
    Category(
        id="building",
        title="Building a trip",
        blurb="Stops, places, transport and the notes that go with them.",
        icon="article",
    ),
    Category(
        id="sharing",
        title="Sharing and visibility",
        blurb="Decide who sees a trip, and how you send it to them.",
        icon="lock",
    ),
    Category(
        id="community",
        title="Community",
        blurb="Following, ratings, saved trips and the feed.",
        icon="group",
    ),
    Category(
        id="account",
        title="Account and settings",
        blurb="Sign-in, notifications, permissions and your data.",
        icon="person",
    ),
    Category(
        id="safety",
        title="Safety and moderation",
        blurb="Reporting, blocking, hidden content and appeals.",
        icon="flag",
    ),
    Category(
        id="troubleshooting",
        title="Troubleshooting",
        blurb="When something does not work the way you expected.",
        icon="warning",
    ),
    Category(
        id="about",
        title="About Ntripi",
        blurb="Contact us, and what changed in the latest release.",
        icon="info",
    ),
)

# ---------------------------------------------------------------------------
# Release notes, newest first. Rendered at /help/whats-new.
# ---------------------------------------------------------------------------

RELEASES: tuple[Release, ...] = (
    Release(
        version="0.3.0",
        date="2026-09-01",
        headline="Collaborative editing, push notifications and a help centre",
        entries=(
            "**Invite people to edit a trip.** An owner can now grant edit access "
            "to other accounts, with one person editing at a time so nobody's work "
            "is overwritten.",
            "**Push notifications** on iOS and Android, for follows, ratings, "
            "saves and moderation notices.",
            "**This help centre**, with everything above written down.",
        ),
    ),
)

# ---------------------------------------------------------------------------
# Articles. `en.ARTICLES` is the route table — the sitemap, llms.txt and the
# search index all derive from it, and a slug that is not here does not exist.
# ---------------------------------------------------------------------------

ARTICLES: tuple[Article, ...] = (
    # ── Get started ─────────────────────────────────────────────────────────
    Article(
        slug="getting-started",
        title="How to start planning a trip in Ntripi",
        summary=(
            "Create an account, learn the five tabs, and build your first trip "
            "plan in a few minutes."
        ),
        category="getting-started",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "sign up", "signup", "register", "registration", "new account",
            "first time", "beginner", "tour", "basics", "onboarding", "start",
        ),
        related=("plan-a-trip-itinerary", "share-an-itinerary-privately"),
        cta="Ready to plan something? Start your first trip.",
        intro=(
            "Ntripi is a travel app for building trip plans out of real stops — "
            "with what each one costs, how long it takes and how you get between "
            "them — and sharing them with whoever you choose. Create an account, "
            "open the **Itineraries** tab, and add your first trip."
        ),
        blocks=(
            Block(
                anchor="create-an-account",
                heading="Create an account",
                kind=KIND_STEP,
                body=(
                    "You can sign up three ways: with an email address and a "
                    "password, with **Sign in with Google**, or with **Sign in "
                    "with Apple**. All three land you in the same place.\n\n"
                    "You will be asked for a display name, a username, and your "
                    "date of birth. Ntripi has a minimum age of 16. Your date of "
                    "birth is never shown on your profile and no other user can "
                    "see it.\n\n"
                    "Your display name can be anything, in any language, up to 50 "
                    "characters. Your username is the `@name` other people use to "
                    "find you, and it is what shows if you never set a display name."
                ),
            ),
            Block(
                anchor="verify-your-email",
                heading="Verify your email address",
                kind=KIND_STEP,
                body=(
                    "Some actions are held back until your email address is "
                    "verified: creating a trip, rating one, and following people. "
                    "This keeps throwaway accounts out of the ratings.\n\n"
                    "Check your inbox for the verification link. If you signed up "
                    "with Google using the same address, signing in with Google "
                    "verifies it for you — a banner on your profile offers this."
                ),
            ),
            Block(
                anchor="the-five-tabs",
                heading="Find your way around: the five tabs",
                kind=KIND_STEP,
                body=(
                    "The bar along the bottom has five tabs. From left to right:\n\n"
                    "- **Search** — finds *people*, not trips. Search by username.\n"
                    "- **Profile** — your own profile, and the gear icon that opens "
                    "every setting.\n"
                    "- **Itineraries** — trips you own, plus any you have been "
                    "invited to edit.\n"
                    "- **Saved** — trips you bookmarked.\n"
                    "- **Feed** — public trips from everyone, in **Top** and "
                    "**Recent** order.\n\n"
                    "The bell beside the gear on your profile opens your "
                    "notifications."
                ),
            ),
            Block(
                anchor="build-your-first-trip",
                heading="Build your first trip",
                kind=KIND_STEP,
                body=(
                    "Open **Itineraries** and tap **+**. Give the trip a title and "
                    "pick the currency you will record costs in, then start adding "
                    "stops.\n\n"
                    "New trips are visible to **only you** until you change that, "
                    "so there is no risk in experimenting. See [how to plan a trip "
                    "itinerary](/help/plan-a-trip-itinerary) for the full walk-through."
                ),
            ),
            Block(
                anchor="where-to-get-help",
                heading="Getting help inside the app",
                body=(
                    "Most form fields have a small **?** icon beside their label. "
                    "Tapping it explains what that field is for, without leaving the "
                    "screen — this is the fastest way to understand a field you have "
                    "not used before.\n\n"
                    "**Settings ▸ Help Center** has the common questions and the "
                    "ways to contact us. If something is broken, see [how to report "
                    "a bug](/help/contact)."
                ),
            ),
        ),
    ),
    Article(
        slug="plan-a-trip-itinerary",
        title="How to plan a trip itinerary, step by step",
        summary=(
            "Build a travel itinerary with real stops, costs, time and transport — "
            "from an empty trip to one you can share."
        ),
        category="getting-started",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "trip planner", "travel itinerary", "itineraries", "day by day",
            "plan a holiday", "vacation planner", "route", "schedule",
            "stops", "budget", "cost", "planning",
        ),
        related=(
            "plan-alternative-options",
            "share-an-itinerary-privately",
            "getting-started",
        ),
        cta="Plan your own itinerary — it takes about ten minutes.",
        intro=(
            "A trip in Ntripi is an ordered list of stops. Each stop is a real "
            "place with a location, a rough cost, and how long you expect to spend "
            "there. Between stops you record how you travel. Build it in four "
            "passes: create the trip, add stops, connect them, then choose who "
            "can see it."
        ),
        blocks=(
            Block(
                anchor="create-the-trip",
                heading="Create the trip",
                kind=KIND_STEP,
                body=(
                    "In the **Itineraries** tab, tap **+**. You need a title to "
                    "start; everything else can wait.\n\n"
                    "- **Title** — what the trip is. \"Four days in Marrakech\" "
                    "beats \"Morocco\".\n"
                    "- **Currency** — every cost you record uses this, so the total "
                    "adds up. Pick the one you will actually be spending.\n"
                    "- **Cover image** — optional, and you can add it later. It is "
                    "what people see in the feed and in a shared link.\n"
                    "- **Best time to visit** — the months this trip works. Useful "
                    "for anything seasonal."
                ),
            ),
            Block(
                anchor="add-stops",
                heading="Add your stops",
                kind=KIND_STEP,
                body=(
                    "Tap **+** inside the trip to add a stop. A stop holds:\n\n"
                    "- **Name and address** — what the place is called.\n"
                    "- **Location** — pick a point on the map, or paste a Google "
                    "Maps link and let Ntripi read the coordinates out of it.\n"
                    "- **Place type** — food and drink, sleep, sights, nature, "
                    "shopping and so on. This is what draws the right icon on the "
                    "map and in the list.\n"
                    "- **Cost** — roughly what it costs per person. Leave it empty "
                    "or mark it free.\n"
                    "- **Time to spend** — how long to allow. This is what makes a "
                    "plan realistic rather than optimistic.\n"
                    "- **Notes** — anything you want to remember.\n\n"
                    "Add stops in the order you will visit them. You can drag them "
                    "around afterwards."
                ),
            ),
            Block(
                anchor="connect-the-stops",
                heading="Record how you get between stops",
                kind=KIND_STEP,
                body=(
                    "Between two stops you can add a **transit segment**: how you "
                    "travel, how long it takes, and what it costs.\n\n"
                    "A segment can have more than one leg — a bus to the station, "
                    "then a train — and each leg can carry the line number and the "
                    "direction, which is exactly the detail you cannot remember on "
                    "the day."
                ),
            ),
            Block(
                anchor="add-warnings-and-tips",
                heading="Add warnings and tips",
                kind=KIND_STEP,
                body=(
                    "Any stop, and the trip as a whole, can carry short notes in "
                    "four flavours: **advice**, **caution**, **avoid** and **info**. "
                    "They render as coloured chips so they are hard to miss.\n\n"
                    "This is where \"buy tickets before you go\" and \"the north "
                    "entrance is closed\" belong — the things a plain itinerary "
                    "never tells you."
                ),
            ),
            Block(
                anchor="choose-who-sees-it",
                heading="Choose who can see it",
                kind=KIND_STEP,
                body=(
                    "New trips start as **only me**. When you are ready, open the "
                    "trip's settings and pick one of four levels — public, "
                    "followers, specific people, or only you.\n\n"
                    "See [how to share a trip without making it "
                    "public](/help/share-an-itinerary-privately) for what each "
                    "level means in practice."
                ),
            ),
        ),
    ),
    Article(
        slug="app-map",
        title="Ntripi's screens and icons, explained",
        summary=(
            "A guided tour of the five tabs, the itinerary screen and the icons "
            "you will meet along the way."
        ),
        category="getting-started",
        updated="2026-09-01",
        keywords=(
            "icons", "buttons", "menu", "navigation", "tabs", "where is",
            "what does this button do", "interface", "layout",
        ),
        related=("getting-started", "app-settings"),
        cta="See it for yourself — open Ntripi.",
        intro=(
            "Ntripi has five tabs along the bottom and very little chrome above "
            "them. Almost everything you can change lives either behind the gear "
            "on your profile or behind a long press on the thing itself. This "
            "page names each one."
        ),
        blocks=(
            Block(
                anchor="bottom-nav",
                heading="The five tabs",
                kind=KIND_DIAGRAM,
                body=(
                    "1. **Search** — finds **people**, not trips. Search by "
                    "username. Public trips are discovered through the Feed "
                    "instead.\n"
                    "2. **Profile** — your own profile. The gear opens every "
                    "setting; the bell beside it opens your notifications.\n"
                    "3. **Itineraries** — trips you own, and a second view for "
                    "trips other people invited you to edit.\n"
                    "4. **Saved** — trips you bookmarked, with a filter box.\n"
                    "5. **Feed** — public trips from everyone, in **Top** and "
                    "**Recent** order.\n\n"
                    "Tapping the tab you are already on returns you to the top of "
                    "it, which is the fastest way out of a deep screen."
                ),
            ),
            Block(
                anchor="itinerary-screen",
                heading="Reading an itinerary",
                kind=KIND_DIAGRAM,
                body=(
                    "1. **The visibility pill** under the title — who can open "
                    "this trip. Tap it (as the owner) to change it.\n"
                    "2. **A second column** means these two stops are "
                    "alternatives to each other, not a sequence. See [how to plan "
                    "two options for the same day](/help/plan-alternative-options).\n"
                    "3. **A transport row** between two stops — how you get from "
                    "one to the next, and how long it takes.\n"
                    "4. **A coloured chip** on a stop is a note: advice, caution, "
                    "avoid or info.\n"
                    "5. **The rating row** — the average and how many people have "
                    "rated it. Averages appear once three people have."
                ),
            ),
            Block(
                anchor="icons",
                heading="Icons you will meet",
                body=(
                    "| Icon | What it does |\n"
                    "|---|---|\n"
                    "| **?** | Explains the field beside it, without leaving the screen |\n"
                    "| Bookmark | Saves the trip to your Saved tab |\n"
                    "| Pencil | Edit — shown only if you can edit this |\n"
                    "| Flag | Report this to us |\n"
                    "| Gear | Settings, on your own profile |\n"
                    "| Bell | Notifications, with a dot when something is new |\n\n"
                    "The **?** is worth knowing about: nearly every field in "
                    "every form has one, and it is faster than coming here."
                ),
            ),
            Block(
                anchor="long-press",
                heading="Long-press shortcuts",
                body=(
                    "Holding your finger on part of a trip you own jumps straight "
                    "to editing that part — the title, the cover, a stop, a note. "
                    "It saves walking back through the edit screen.\n\n"
                    "On somebody else's trip the same gesture offers to report or "
                    "block instead. The two never overlap, so you cannot report "
                    "your own trip by accident or edit someone else's."
                ),
            ),
        ),
    ),
    # ── Building a trip ─────────────────────────────────────────────────────
    Article(
        slug="plan-alternative-options",
        title="How to plan two options for the same day",
        summary=(
            "Put alternative places side by side in one trip, so a rainy day or a "
            "different budget does not need a second plan."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "parallel", "track", "tracks", "alternative", "alternatives",
            "options", "optional", "plan b", "backup", "branch", "column",
            "either or", "rainy day", "weather", "choice", "choices",
        ),
        related=("plan-a-trip-itinerary", "getting-started"),
        cta="Plan a trip with real alternatives, not a single fragile line.",
        intro=(
            "Most trip planners force one place per slot. Ntripi lets you stack "
            "**alternatives side by side**: two or three places that occupy the "
            "same point in the trip, so whoever is travelling picks on the day. "
            "Internally these columns are called **tracks**."
        ),
        blocks=(
            Block(
                anchor="what-a-track-is",
                heading="What a track is",
                body=(
                    "A **track** is a vertical column of stops that are "
                    "alternatives to each other. A trip with one track is an "
                    "ordinary straight-line itinerary. Add a second track at the "
                    "same point and you have two ways to spend that part of the "
                    "trip.\n\n"
                    "Tracks are useful whenever the answer is \"it depends\":\n\n"
                    "- **Weather** — an outdoor option and an indoor one.\n"
                    "- **Budget** — the expensive restaurant and the good cheap one.\n"
                    "- **Energy** — the long hike and the short walk.\n"
                    "- **Taste** — the museum for one half of the group and the "
                    "market for the other."
                ),
            ),
            Block(
                anchor="add-an-alternative",
                heading="Add an alternative",
                kind=KIND_STEP,
                body=(
                    "Open the trip and find the stop you want an alternative to. "
                    "Use the add control beside it and choose to place the new stop "
                    "in a **new track** rather than after the existing one.\n\n"
                    "The two stops now sit side by side. Neither is the \"real\" "
                    "one — they are equals, and anyone reading the trip sees both."
                ),
            ),
            Block(
                anchor="move-a-stop",
                heading="Move a stop between tracks",
                kind=KIND_STEP,
                body=(
                    "A stop can be moved into another track after the fact, so you "
                    "are not committed by the order you happened to add things in. "
                    "Open the stop and use the move action to pick its track.\n\n"
                    "A track exists only while it has at least one stop in it. Move "
                    "or delete the last stop and the empty column disappears by "
                    "itself — there is nothing to tidy up."
                ),
            ),
            Block(
                anchor="reorder",
                heading="Reorder tracks and stops",
                kind=KIND_STEP,
                body=(
                    "Drag to reorder stops within a track, and to reorder the "
                    "tracks themselves. The first track in a trip is treated as the "
                    "starting point and the last as the destination, which is what "
                    "the map draws between."
                ),
            ),
            Block(
                anchor="transport-warning",
                heading="Why inserting a track sometimes warns you",
                body=(
                    "Transport is recorded between two *neighbouring* tracks. If "
                    "you insert a new track between two that already have transport "
                    "connecting them, that connection no longer has anywhere to "
                    "live — the two tracks are no longer neighbours.\n\n"
                    "Ntripi asks before doing this rather than quietly dropping the "
                    "transport you entered. Confirm, and the affected connection is "
                    "removed; cancel, and nothing changes."
                ),
            ),
        ),
    ),
    Article(
        slug="add-places-to-an-itinerary",
        title="How to add places, costs and time to a trip plan",
        summary=(
            "Everything a stop can hold — what it is, where it is, what it costs "
            "and how long to allow."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "stop", "stops", "place", "places", "add", "budget", "price",
            "duration", "how long", "category", "restaurant", "hotel", "museum",
        ),
        related=("plan-a-trip-itinerary", "add-locations-from-google-maps",
                 "travel-notes-and-warnings"),
        cta="Start a trip and add your first stop.",
        intro=(
            "A stop is one place you will actually be. Beyond its name, the two "
            "fields that make a plan usable are **cost** and **time to spend** — "
            "they are what turn a list of places into something you can budget "
            "and fit into a day."
        ),
        blocks=(
            Block(
                anchor="add-a-stop",
                heading="Add a stop",
                kind=KIND_STEP,
                body=(
                    "Open the trip and tap **+**. Give the place a name — what you "
                    "would call it out loud, not its official title — and an "
                    "address if you have one.\n\n"
                    "Stops are added in visiting order. You can drag them into a "
                    "different order at any point afterwards."
                ),
            ),
            Block(
                anchor="place-type",
                heading="Choose a place type",
                kind=KIND_STEP,
                body=(
                    "The place type draws the right icon on the map and in the "
                    "list, so a day reads at a glance. There are eleven:\n\n"
                    "- **Eat & drink** · **Sleep** · **Buy**\n"
                    "- **Learn & see** · **Sight** · **Entertainment**\n"
                    "- **Play & watch** · **Nature** · **Heal & bathe**\n"
                    "- **Pray** · **Travel**\n\n"
                    "It is optional. A stop with no type still works; it just "
                    "looks the same as every other untyped one."
                ),
            ),
            Block(
                anchor="cost",
                heading="Record what it costs",
                kind=KIND_STEP,
                body=(
                    "Enter the rough cost **per person**, in the trip's currency. "
                    "Approximate is fine — the point is the total at the end, not "
                    "an invoice.\n\n"
                    "If a place is free, mark it free rather than leaving the "
                    "field empty. Empty means \"I have not looked into it\", and "
                    "the difference matters to anyone reading your plan."
                ),
            ),
            Block(
                anchor="time-to-spend",
                heading="Record how long to allow",
                kind=KIND_STEP,
                body=(
                    "This is the field that stops a plan being a fantasy. Four "
                    "sights in an afternoon looks reasonable as a list and "
                    "impossible once each one carries ninety minutes.\n\n"
                    "Allow the time you would actually want there, not the "
                    "minimum it can be done in."
                ),
            ),
            Block(
                anchor="notes",
                heading="Add your own notes",
                body=(
                    "The notes field is free text — booking references, what to "
                    "order, which entrance to use, why you picked this place over "
                    "the one nearby.\n\n"
                    "For a warning that should be hard to miss rather than read "
                    "in passing, use an [advice or caution "
                    "note](/help/travel-notes-and-warnings) instead: those render "
                    "as coloured chips."
                ),
            ),
        ),
    ),
    Article(
        slug="add-locations-from-google-maps",
        title="How to add a place from a Google Maps link",
        summary=(
            "Paste a Maps link and Ntripi reads the coordinates out of it, or drop "
            "the pin yourself on the map."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "google maps", "link", "paste", "coordinates", "gps", "pin",
            "location", "map picker", "latitude", "longitude", "where",
        ),
        related=("add-places-to-an-itinerary", "permissions"),
        cta="Pin your first stop on the map.",
        intro=(
            "A stop can get its location two ways: pick the point on Ntripi's own "
            "map, or paste a Google Maps link and let Ntripi read the coordinates "
            "out of it. The second is usually faster, because you have probably "
            "already found the place there."
        ),
        blocks=(
            Block(
                anchor="paste-a-link",
                heading="Paste a Google Maps link",
                kind=KIND_STEP,
                body=(
                    "In the stop's location field, switch to the link option and "
                    "paste the URL. Ntripi extracts the coordinates and keeps the "
                    "link, so the stop shows a small map preview and you can open "
                    "the place in Maps later.\n\n"
                    "Both the long desktop URL and the short share link work. Only "
                    "Google Maps addresses are accepted — a link to anywhere else "
                    "is refused rather than stored and quietly ignored."
                ),
            ),
            Block(
                anchor="pick-on-the-map",
                heading="Or drop the pin yourself",
                kind=KIND_STEP,
                body=(
                    "Switch to coordinates and open the map picker. Pan and zoom to "
                    "the spot, and the pin in the centre is what gets saved.\n\n"
                    "This is the better option for a place with no Maps entry — a "
                    "viewpoint, a trailhead, a beach with no name."
                ),
            ),
            Block(
                anchor="locate-me",
                heading="Centring the map on where you are",
                kind=KIND_STEP,
                body=(
                    "The locate button centres the map on your current position, "
                    "which saves scrolling across a continent to find the town you "
                    "are standing in.\n\n"
                    "It asks for location permission the first time. **Refusing "
                    "does not block anything** — the map simply opens somewhere "
                    "else and you pan to where you want. See [what permissions "
                    "Ntripi asks for](/help/permissions)."
                ),
            ),
            Block(
                anchor="opening-in-maps",
                heading="Opening a stop in your maps app",
                body=(
                    "A stop with a location offers to open in whichever maps app "
                    "you have installed, so you can get directions on the day "
                    "without retyping anything.\n\n"
                    "Ntripi's own map is for reading the plan; your maps app is for "
                    "walking it."
                ),
            ),
        ),
    ),
    Article(
        slug="plan-transport-between-stops",
        title="How to plan transport between stops",
        summary=(
            "Record how you get from one place to the next — the mode, the time, "
            "the cost and the line number you will not remember."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "transport", "transit", "bus", "train", "metro", "taxi", "walk",
            "drive", "flight", "connection", "leg", "segment", "how to get there",
        ),
        related=("add-places-to-an-itinerary", "plan-alternative-options"),
        cta="Map out a journey, connections and all.",
        intro=(
            "Between any two stops you can record a **transit segment**: how you "
            "travel, how long it takes and what it costs. A segment can have "
            "several legs, so a bus-then-train journey stays one connection rather "
            "than two unexplained gaps."
        ),
        blocks=(
            Block(
                anchor="add-a-segment",
                heading="Add a connection",
                kind=KIND_STEP,
                body=(
                    "Between two stops, use the add-transport control. Choose the "
                    "mode — walking, cycling, bus, train, metro, taxi, car, ferry, "
                    "flight — and give it a duration.\n\n"
                    "Cost is per person, in the trip's currency, and adds into the "
                    "trip total alongside the stops."
                ),
            ),
            Block(
                anchor="multiple-legs",
                heading="Add more than one leg",
                kind=KIND_STEP,
                body=(
                    "A journey rarely uses one vehicle. Add a leg for each part — "
                    "the walk to the stop, the bus, the change, the train — and "
                    "each keeps its own mode and duration.\n\n"
                    "The connection then shows the true door-to-door time, which "
                    "is the number that decides whether the afternoon works."
                ),
            ),
            Block(
                anchor="line-and-direction",
                heading="Record the line and the direction",
                kind=KIND_STEP,
                body=(
                    "Each leg can carry a line — `M4`, `Bus 12`, `RER B` — and a "
                    "direction, which is the terminus shown on the front of the "
                    "vehicle.\n\n"
                    "The direction is the detail that matters on the day. Knowing "
                    "you want the M4 is no help on a platform with trains going "
                    "both ways."
                ),
            ),
            Block(
                anchor="orphaned-connections",
                heading="Why inserting a stop can warn you",
                body=(
                    "A connection lives *between two neighbours*. If you insert a "
                    "new column between two that already have one, that connection "
                    "no longer has anywhere to sit.\n\n"
                    "Ntripi asks before doing this rather than quietly discarding "
                    "what you entered. Confirm and the affected connection is "
                    "removed; cancel and nothing changes."
                ),
            ),
        ),
    ),
    Article(
        slug="travel-notes-and-warnings",
        title="How to add travel warnings and tips to a trip",
        summary=(
            "Four kinds of note — advice, caution, avoid and info — that render as "
            "coloured chips so nobody scrolls past them."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "note", "notes", "warning", "warnings", "tip", "tips", "advice",
            "caution", "avoid", "info", "annotation", "safety", "scam",
        ),
        related=("add-places-to-an-itinerary", "plan-a-trip-itinerary"),
        cta="Write down what you wish someone had told you.",
        intro=(
            "The things that go wrong on a trip are rarely in the guidebook. "
            "Ntripi has four note types — **advice**, **caution**, **avoid** and "
            "**info** — that attach to a single stop or to the whole trip and draw "
            "as coloured chips, so a reader meets them rather than finds them."
        ),
        blocks=(
            Block(
                anchor="the-four-types",
                heading="What each type is for",
                body=(
                    "- **Advice** — do this, and it will go better. \"Buy the "
                    "ticket online, the queue is an hour.\"\n"
                    "- **Caution** — this is fine, but be careful. \"Busy at night; "
                    "keep your bag in front.\"\n"
                    "- **Avoid** — don't. \"The taxi rank outside overcharges; walk "
                    "two streets and hail one.\"\n"
                    "- **Info** — worth knowing, no action needed. \"Closed on "
                    "Tuesdays.\"\n\n"
                    "The type only changes the colour and the label, so pick the "
                    "one a stranger would read the way you meant it."
                ),
            ),
            Block(
                anchor="add-to-a-stop",
                heading="Add a note to one stop",
                kind=KIND_STEP,
                body=(
                    "Open the stop and add a note there. It belongs to that place "
                    "and travels with it if you reorder the trip.\n\n"
                    "This is where anything about a specific entrance, queue, "
                    "opening time or local hazard belongs."
                ),
            ),
            Block(
                anchor="add-to-the-trip",
                heading="Add a note to the whole trip",
                kind=KIND_STEP,
                body=(
                    "From the itinerary itself, a note applies to the trip as a "
                    "whole — visa requirements, the season, which SIM card works, "
                    "what to pack.\n\n"
                    "Trip-level notes are shown near the top, before the stops, "
                    "because they usually need reading before anyone plans a day."
                ),
            ),
            Block(
                anchor="notes-vs-notes",
                heading="Notes versus the notes field",
                body=(
                    "Every stop also has a plain **notes** field. Use that for your "
                    "own reminders — a booking reference, what to order.\n\n"
                    "Use a coloured note for anything a reader needs to *act* on. "
                    "The difference is whether it should be easy to skim past."
                ),
            ),
        ),
    ),
    Article(
        slug="trip-cover-photos",
        title="How to add a cover photo to your trip",
        summary=(
            "Pick a cover image, crop it, and know what gets refused before you "
            "upload."
        ),
        category="building",
        updated="2026-09-01",
        keywords=(
            "cover", "photo", "image", "picture", "upload", "crop", "banner",
            "thumbnail", "rejected", "too small",
        ),
        related=("plan-a-trip-itinerary", "share-a-trip-link"),
        cta="Give your trip a face.",
        intro=(
            "The cover is what people see in the feed and in a shared link, so it "
            "does more work than any other single field. Only the trip's **owner** "
            "can set it — someone invited to edit can change the content but not "
            "the trip's public face."
        ),
        blocks=(
            Block(
                anchor="add-a-cover",
                heading="Add or change the cover",
                body=(
                    "Open the trip's edit screen and tap the cover area. Your "
                    "photo library opens; pick an image and crop it to the frame.\n\n"
                    "The crop is wide, because that is the shape a link preview "
                    "uses. A tall photo will lose its top and bottom, so choose one "
                    "whose subject sits in the middle."
                ),
            ),
            Block(
                anchor="what-gets-refused",
                heading="What gets refused, and why",
                body=(
                    "An image can be refused for three reasons:\n\n"
                    "- **Too small.** Anything under 600 pixels on its shortest "
                    "side will look soft on a modern screen.\n"
                    "- **An unsupported format.** JPEG, PNG and the usual photo "
                    "formats are fine.\n"
                    "- **Content.** Uploads are checked automatically against the "
                    "[community guidelines](/guidelines) before they are stored.\n\n"
                    "If you believe a refusal was wrong, [tell us](/help/contact)."
                ),
            ),
            Block(
                anchor="what-we-strip",
                heading="What Ntripi removes from your photo",
                body=(
                    "Every uploaded image has its **EXIF metadata stripped** before "
                    "it is stored. That is the block of hidden data a camera "
                    "attaches — most importantly the **GPS coordinates of where the "
                    "photo was taken**, along with the device model and timestamp.\n\n"
                    "This happens whether or not the trip is public, and it cannot "
                    "be switched off. A photo of your street should not publish "
                    "your street."
                ),
            ),
            Block(
                anchor="no-cover",
                heading="If you don't add one",
                body=(
                    "A trip with no cover gets a generated placeholder drawn from "
                    "its route, so it never looks broken.\n\n"
                    "It is worth adding a real one before sharing publicly, though "
                    "— in a feed of photographs, the placeholder is the one people "
                    "scroll past."
                ),
            ),
        ),
    ),
    Article(
        slug="plan-a-trip-with-friends",
        title="How to plan a trip together with other people",
        summary=(
            "Invite people to edit a trip, and understand why only one of you can "
            "be typing at a time."
        ),
        category="building",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "collaborate", "collaboration", "together", "shared", "editor",
            "editors", "invite", "group", "friends", "family", "co-edit",
            "someone else is editing", "lock",
        ),
        related=("share-an-itinerary-privately", "plan-alternative-options",
                 "troubleshooting"),
        cta="Plan your next trip with the people going on it.",
        intro=(
            "A trip has one owner and any number of **editors**. An editor can "
            "change the content — stops, transport, notes, the title — but not who "
            "can see it, the cover, or the editor list. Only one person edits at a "
            "time, so nobody's work is overwritten."
        ),
        blocks=(
            Block(
                anchor="invite-an-editor",
                heading="Invite someone to edit",
                kind=KIND_STEP,
                body=(
                    "Open the trip's edit screen and find the editors list. Add "
                    "them by username. They get a notification naming the trip, "
                    "which is what lets them find it — a private trip is in no feed "
                    "and no search.\n\n"
                    "Only the **owner** can add or remove editors. An editor cannot "
                    "recruit more: the invitation is your trust decision and does "
                    "not carry the power to hand it on."
                ),
            ),
            Block(
                anchor="cannot-see-it",
                heading="If they can't see the trip yet",
                kind=KIND_STEP,
                body=(
                    "Editing requires being able to see it first. If you invite "
                    "someone who cannot, Ntripi asks whether to give them access "
                    "too, rather than failing.\n\n"
                    "Saying yes adds them to that trip's allowlist and nothing "
                    "else. It never widens the trip's visibility — turning "
                    "\"followers\" into \"specific people\" would silently cut off "
                    "everyone else, so that stays a decision you make deliberately."
                ),
            ),
            Block(
                anchor="one-at-a-time",
                heading="Why only one person can edit at a time",
                body=(
                    "When you open a trip for editing you hold it. Anyone else sees "
                    "**\"someone else is editing\"** and can read but not save.\n\n"
                    "The alternative is two people typing into the same stop and "
                    "one of them losing everything without being told. Holding it "
                    "is brief — it is released when you leave, and it lapses on its "
                    "own if you get distracted."
                ),
            ),
            Block(
                anchor="taking-over",
                heading="Taking over from someone",
                kind=KIND_STEP,
                body=(
                    "If the trip has been idle for a while, anyone who can edit may "
                    "take it. As the owner you can always take it back — including "
                    "from your own other device, which is the usual reason it is "
                    "stuck.\n\n"
                    "Taking over is always a deliberate second step, never "
                    "automatic."
                ),
            ),
            Block(
                anchor="losing-the-lock",
                heading="If someone takes it while you're typing",
                body=(
                    "A banner appears and Save stops working. **Nothing you typed "
                    "is lost** — every field stays exactly as you left it, and you "
                    "can still select and copy from them.\n\n"
                    "Take the trip back and save, or copy your text out and paste "
                    "it in when the other person is done. Ntripi will not close the "
                    "screen or clear a field on you, because at that moment your "
                    "unsaved text is the only copy of it."
                ),
            ),
            Block(
                anchor="finding-shared-trips",
                heading="Finding a trip someone shared with you",
                body=(
                    "The **Itineraries** tab has a second view for trips you were "
                    "invited to edit. That is the durable way back to one — the "
                    "notification that announced it is eventually cleared away, and "
                    "a private trip appears in no feed and no search."
                ),
            ),
        ),
    ),
    # ── Sharing and visibility ──────────────────────────────────────────────
    Article(
        slug="share-an-itinerary-privately",
        title="How to share a travel itinerary without making it public",
        summary=(
            "Four visibility levels decide who can open a trip — from everyone on "
            "the internet down to a named handful of people."
        ),
        category="sharing",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "private", "privately", "visibility", "who can see", "public",
            "followers", "restricted", "only me", "hide", "hidden", "secret",
            "share link", "permissions", "friends only", "invite",
        ),
        related=("plan-a-trip-itinerary", "plan-alternative-options"),
        cta="Plan a trip and share it with exactly the people you mean to.",
        intro=(
            "Every trip has one of four visibility levels, and you can change it "
            "at any time. New trips start at **only me**. To share with a specific "
            "group without publishing, use **specific people** and add them by "
            "username."
        ),
        blocks=(
            Block(
                anchor="the-four-levels",
                heading="What are the four visibility levels?",
                kind=KIND_FAQ,
                body=(
                    "- **Public** — anyone can open it, including people who are "
                    "not signed in. It can appear in the feed and be found by "
                    "search engines through its share link.\n"
                    "- **Followers** — everyone who follows you. If your account is "
                    "private, that means only followers you have accepted.\n"
                    "- **Specific people** — only the usernames you add. Nobody "
                    "else, however they got the link.\n"
                    "- **Only me** — nobody but you and anyone you have made an "
                    "editor."
                ),
            ),
            Block(
                anchor="share-with-a-few-people",
                heading="How do I share with just a few people?",
                kind=KIND_FAQ,
                body=(
                    "Set the trip to **specific people** and add them by username. "
                    "Then send them the trip's share link.\n\n"
                    "The link is not a secret password — it is the address of the "
                    "trip. Access is checked against your list every time someone "
                    "opens it, so forwarding the link to someone who is not on the "
                    "list gets them nothing."
                ),
            ),
            Block(
                anchor="what-others-see",
                heading="What does someone without access see?",
                kind=KIND_FAQ,
                body=(
                    "A page that says the trip is not available. It does not say "
                    "the trip exists, who owns it, or what it is called — a trip "
                    "you cannot see is indistinguishable from one that was never "
                    "created.\n\n"
                    "The same holds for a profile you have been blocked by."
                ),
            ),
            Block(
                anchor="change-later",
                heading="Can I change the visibility later?",
                kind=KIND_FAQ,
                body=(
                    "Yes, at any time, in both directions. Changing to a narrower "
                    "level takes effect immediately — anyone who no longer qualifies "
                    "stops being able to open it.\n\n"
                    "Only the trip's owner can change visibility. Someone you have "
                    "invited to edit can change the content, but not who sees it."
                ),
            ),
            Block(
                anchor="link-previews",
                heading="What shows up when I paste the link somewhere?",
                kind=KIND_FAQ,
                body=(
                    "A public trip generates a preview card with its cover image, "
                    "title, duration, cost and rating.\n\n"
                    "A trip that is not public generates no such preview — the "
                    "preview would leak the title to everyone in the chat, "
                    "including people who cannot open it."
                ),
            ),
        ),
    ),
    Article(
        slug="share-a-trip-link",
        title="How to share your trip as a link",
        summary=(
            "Send a trip to anyone with a link, and know what the preview card "
            "will show before you paste it."
        ),
        category="sharing",
        updated="2026-09-01",
        keywords=(
            "share", "link", "url", "send", "whatsapp", "preview", "copy",
            "publish", "public",
        ),
        related=("share-an-itinerary-privately", "trip-cover-photos"),
        cta="Build something worth sending.",
        intro=(
            "Every trip has a web address. Sharing is just sending it — the link "
            "is the trip's location, not a password, and access is re-checked "
            "against your [visibility "
            "setting](/help/share-an-itinerary-privately) every time anyone opens "
            "it."
        ),
        blocks=(
            Block(
                anchor="get-the-link",
                heading="Get the link",
                body=(
                    "Open the trip and use the share action. Your device's normal "
                    "share sheet appears, so the link can go to any app — messages, "
                    "email, notes.\n\n"
                    "The page opens in a browser, so the person you send it to does "
                    "not need the app to read it."
                ),
            ),
            Block(
                anchor="what-the-preview-shows",
                heading="What the preview card shows",
                body=(
                    "A **public** trip generates a preview card in most chat apps: "
                    "the cover image, the title, the total duration and cost, the "
                    "number of stops, and the rating if it has one.\n\n"
                    "A trip that is **not** public generates no preview. That is "
                    "deliberate — a preview would show the title to everyone in the "
                    "group chat, including people who cannot open it."
                ),
            ),
            Block(
                anchor="what-they-see",
                heading="What the reader gets",
                body=(
                    "The whole trip: the stops in order, the parallel options, the "
                    "transport between them, the costs, your notes and warnings, "
                    "and the ratings.\n\n"
                    "They can read all of it without an account. Saving it, rating "
                    "it or copying stops from it needs one."
                ),
            ),
            Block(
                anchor="unsharing",
                heading="Taking it back",
                body=(
                    "Change the trip's visibility and the link stops working for "
                    "anyone who no longer qualifies, immediately. There is no need "
                    "to chase the message you sent.\n\n"
                    "What you cannot undo is a screenshot, so treat publishing as "
                    "publishing."
                ),
            ),
        ),
    ),
    # ── Community ───────────────────────────────────────────────────────────
    Article(
        slug="follow-and-private-accounts",
        title="Followers, follow requests and private accounts",
        summary=(
            "How following works, what a private account hides, and how to approve "
            "or refuse a request."
        ),
        category="community",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "follow", "follower", "followers", "following", "request", "private",
            "public account", "approve", "accept", "unfollow", "block",
        ),
        related=("share-an-itinerary-privately", "report-and-block"),
        cta="Find the people whose trips you want to steal.",
        intro=(
            "Following someone puts their public trips in front of you and lets "
            "them share trips with followers. If your account is **private**, a "
            "follow becomes a **request** you approve or refuse."
        ),
        blocks=(
            Block(
                anchor="how-to-follow",
                heading="How do I follow someone?",
                kind=KIND_FAQ,
                body=(
                    "Find them in the **Search** tab — it searches usernames — and "
                    "use Follow on their profile.\n\n"
                    "If their account is public you are following straight away. If "
                    "it is private the button becomes **Requested** until they "
                    "decide."
                ),
            ),
            Block(
                anchor="what-private-hides",
                heading="What does a private account hide?",
                kind=KIND_FAQ,
                body=(
                    "Trips set to **followers** become visible only to followers "
                    "you have actually accepted, rather than anyone who tapped "
                    "Follow.\n\n"
                    "Trips you set to **public** stay public — private is about who "
                    "counts as a follower, not a blanket lock. If you want "
                    "everything hidden, set the trips themselves to [only me or "
                    "specific people](/help/share-an-itinerary-privately)."
                ),
            ),
            Block(
                anchor="handling-requests",
                heading="Where do I approve requests?",
                kind=KIND_FAQ,
                body=(
                    "A banner on your profile shows the count, and **Settings ▸ "
                    "Follow requests** lists them. Accept or refuse each one.\n\n"
                    "Refusing does not tell them. They simply stop being requested "
                    "and can ask again."
                ),
            ),
            Block(
                anchor="going-public",
                heading="What happens if I switch from private to public?",
                kind=KIND_FAQ,
                body=(
                    "Every pending request is accepted automatically. Leaving "
                    "people queued behind a gate you have just removed would be a "
                    "queue nobody was ever going to look at again.\n\n"
                    "Going the other way, from public to private, does not remove "
                    "your existing followers."
                ),
            ),
            Block(
                anchor="unfollow-vs-block",
                heading="What's the difference between unfollowing and blocking?",
                kind=KIND_FAQ,
                body=(
                    "**Unfollowing** just stops their trips reaching your feed. "
                    "They can still see whatever they could see before.\n\n"
                    "**Blocking** cuts visibility in both directions, and the "
                    "blocked person is not told. See [reporting and "
                    "blocking](/help/report-and-block)."
                ),
            ),
        ),
    ),
    Article(
        slug="rate-a-trip",
        title="How trip ratings work: safety, accessibility, crowds and more",
        summary=(
            "One overall score plus five optional dimensions, and why averages only "
            "appear once three people have rated."
        ),
        category="community",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "rating", "ratings", "rate", "review", "reviews", "stars", "score",
            "safety", "accessibility", "family friendly", "crowded", "crowdedness",
        ),
        related=("save-trips-and-find-new-ones", "report-and-block"),
        cta="Rate a trip you have actually done.",
        intro=(
            "A rating is one required **overall** score out of five, and up to five "
            "optional dimensions: safety, experience, accessibility, "
            "family-friendliness and crowdedness. You can leave a written note "
            "alongside it."
        ),
        blocks=(
            Block(
                anchor="the-dimensions",
                heading="What do the five dimensions mean?",
                kind=KIND_FAQ,
                body=(
                    "- **Safety** — how safe it felt.\n"
                    "- **Experience** — how good it actually was.\n"
                    "- **Accessibility** — how well it works with limited mobility, "
                    "a pushchair, or heavy luggage.\n"
                    "- **Family-friendly** — how well it works with children.\n"
                    "- **Crowdedness** — how pleasantly uncrowded it was.\n\n"
                    "Every dimension is **higher is better**, crowdedness included: "
                    "five means pleasantly quiet, one means overrun. They are all "
                    "optional — rate only what you can speak to."
                ),
            ),
            Block(
                anchor="three-ratings",
                heading="Why don't I see an average?",
                kind=KIND_FAQ,
                body=(
                    "A dimension shows its average only once **three** people have "
                    "rated it.\n\n"
                    "One person's opinion presented as an average reads as a fact "
                    "about the place rather than a view of it, and two is not much "
                    "better. Below three you see the individual ratings instead."
                ),
            ),
            Block(
                anchor="who-can-rate",
                heading="Who can rate a trip?",
                kind=KIND_FAQ,
                body=(
                    "Anyone who can see it and has a verified email address, except "
                    "its owner. You can update your own rating at any time — "
                    "rating again replaces it rather than adding a second.\n\n"
                    "The email requirement is what keeps throwaway accounts out of "
                    "the scores."
                ),
            ),
            Block(
                anchor="written-notes",
                heading="Can I write a review, not just a score?",
                kind=KIND_FAQ,
                body=(
                    "Yes — the rating dialog has a note field, and it is the part "
                    "other travellers actually read. A score says how it went; the "
                    "note says why.\n\n"
                    "Notes are subject to the [community "
                    "guidelines](/guidelines) like anything else published."
                ),
            ),
            Block(
                anchor="disagreeing",
                heading="Someone rated my trip unfairly",
                kind=KIND_FAQ,
                body=(
                    "You cannot remove a rating of your own trip, and that is the "
                    "point — a score the author can delete is worth nothing to the "
                    "next reader.\n\n"
                    "If a rating breaks the guidelines rather than merely "
                    "disagreeing with you, [report it](/help/report-and-block) and "
                    "a person will look."
                ),
            ),
        ),
    ),
    Article(
        slug="save-trips-and-find-new-ones",
        title="How to save trips and discover new ones",
        summary=(
            "Bookmark anything worth keeping, and understand the difference between "
            "the Top and Recent feeds."
        ),
        category="community",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "save", "saved", "bookmark", "favourite", "favorite", "feed",
            "discover", "explore", "top", "recent", "trending", "browse",
        ),
        related=("rate-a-trip", "share-an-itinerary-privately"),
        cta="Find a trip worth stealing.",
        intro=(
            "The **Feed** tab shows public trips from everyone. Anything worth "
            "keeping gets bookmarked into the **Saved** tab, which is yours alone — "
            "nobody is told that you saved their trip."
        ),
        blocks=(
            Block(
                anchor="saving",
                heading="How do I save a trip?",
                kind=KIND_FAQ,
                body=(
                    "Tap the bookmark on any trip you can see. It appears in your "
                    "**Saved** tab, which has its own filter box once the list "
                    "grows.\n\n"
                    "The bookmark is not shown on your own trips — saving something "
                    "you wrote would do nothing."
                ),
            ),
            Block(
                anchor="saved-changes",
                heading="What if a saved trip changes or disappears?",
                kind=KIND_FAQ,
                body=(
                    "You always see the current version, not the one you saved.\n\n"
                    "If the author narrows its visibility or deletes it, it leaves "
                    "your Saved tab. A bookmark is a pointer, not a copy — the "
                    "author keeps control of their own work."
                ),
            ),
            Block(
                anchor="top-vs-recent",
                heading="What's the difference between Top and Recent?",
                kind=KIND_FAQ,
                body=(
                    "**Recent** is everything public, newest first. **Top** is "
                    "sorted by rating, and a trip needs a few ratings before it can "
                    "appear there at all.\n\n"
                    "Recent is where you find new work; Top is where you find work "
                    "other people have vouched for."
                ),
            ),
            Block(
                anchor="not-in-top",
                heading="Why isn't my trip in Top?",
                kind=KIND_FAQ,
                body=(
                    "It needs to be public, and it needs enough ratings. A trip with "
                    "one glowing score is not evidence of anything, so the Top feed "
                    "waits for a few.\n\n"
                    "Share it with a [link](/help/share-a-trip-link) to the people "
                    "who have been there — that is what gets the first ratings in."
                ),
            ),
            Block(
                anchor="finding-people",
                heading="How do I find a particular person?",
                kind=KIND_FAQ,
                body=(
                    "The **Search** tab searches usernames, not trips. Trips are "
                    "found through the feed, through a link someone sent you, or "
                    "through a profile once you have found the person.\n\n"
                    "A private trip is in no feed and no search by design; the only "
                    "way to it is an invitation or a link from someone who can see "
                    "it."
                ),
            ),
        ),
    ),
    # ── Account and settings ────────────────────────────────────────────────
    Article(
        slug="notifications",
        title="How to control which notifications Ntripi sends",
        summary=(
            "The eight things Ntripi will tell you about, which three you can "
            "switch off, and why the rest stay on."
        ),
        category="account",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "notification", "notifications", "push", "alerts", "bell", "badge",
            "mute", "turn off", "email", "quiet",
        ),
        related=("permissions", "follow-and-private-accounts"),
        cta="Keep up with your trips without the noise.",
        intro=(
            "The bell beside the gear on your profile is the whole list. Three "
            "kinds of notification can be switched off in **Settings ▸ "
            "Notifications**; the rest stay on because an unseen one cannot be "
            "acted on in time."
        ),
        blocks=(
            Block(
                anchor="what-you-get",
                heading="What will Ntripi notify me about?",
                kind=KIND_FAQ,
                body=(
                    "- Someone asked to follow you, or started following you\n"
                    "- Someone accepted your follow request *(optional)*\n"
                    "- Someone rated one of your trips *(optional)*\n"
                    "- Someone saved one of your trips *(optional)*\n"
                    "- You were invited to edit a trip\n"
                    "- You were given access to a trip\n"
                    "- A moderation decision affected your content or account\n\n"
                    "Nothing else. There is no marketing, no re-engagement nudging, "
                    "and no digest."
                ),
            ),
            Block(
                anchor="switching-off",
                heading="How do I switch some off?",
                kind=KIND_FAQ,
                body=(
                    "**Settings ▸ Notifications** has three switches: ratings, "
                    "saves, and follow-accepted. Turning one off stops the "
                    "notification being created at all, not merely hidden.\n\n"
                    "To silence everything, turn Ntripi's notifications off in your "
                    "phone's own settings — see [permissions](/help/permissions)."
                ),
            ),
            Block(
                anchor="always-on",
                heading="Why can't I switch off the others?",
                kind=KIND_FAQ,
                body=(
                    "Follow requests, access grants and moderation decisions all "
                    "need an answer from you within a useful window.\n\n"
                    "A follow request nobody sees is never answered. A trip someone "
                    "shared with you is in no feed and no search, so a notice you "
                    "did not get is access you never knew you had. And a moderation "
                    "decision has an appeal window — silence there would cost you "
                    "the appeal."
                ),
            ),
            Block(
                anchor="arrival",
                heading="Why do some arrive late?",
                kind=KIND_FAQ,
                body=(
                    "Push delivery is best-effort everywhere: battery managers stop "
                    "background processes, phones throttle, connections drop.\n\n"
                    "Ntripi therefore also checks for itself roughly once a minute "
                    "while open, so the bell is right even when a push never "
                    "arrived. If push is off or refused, that check is the only "
                    "channel — and it still works."
                ),
            ),
            Block(
                anchor="clearing",
                heading="Can I delete notifications?",
                kind=KIND_FAQ,
                body=(
                    "Yes, individually or all at once, with a few seconds to undo "
                    "before it is final.\n\n"
                    "Deleting a moderation notice does not delete the decision — "
                    "that stays on **Settings ▸ Account status**, along with the "
                    "appeal button. Read notifications are cleared out after ninety "
                    "days; unread ones stay longer, because they are your only "
                    "record that something happened."
                ),
            ),
        ),
    ),
    Article(
        slug="app-settings",
        title="Language, dark mode, sounds and haptics",
        summary=(
            "Every switch behind the gear on your profile, and what each one "
            "changes."
        ),
        category="account",
        updated="2026-09-01",
        keywords=(
            "settings", "language", "translate", "dark mode", "light mode",
            "theme", "sound", "sounds", "haptics", "vibration", "preferences",
        ),
        related=("app-map", "notifications", "permissions"),
        cta="Make the app yours.",
        intro=(
            "The gear on your own profile opens everything. Settings are stored on "
            "your device, so they are per-install: changing the theme on your phone "
            "does not change it on your tablet."
        ),
        blocks=(
            Block(
                anchor="language",
                heading="Language",
                body=(
                    "Ntripi is available in English, French, Arabic, German, "
                    "Spanish and Chinese. It follows your device's language when "
                    "that is one of the six, and you can override it here.\n\n"
                    "Arabic switches the whole interface to right-to-left. The "
                    "choice also travels with legal documents and this help centre "
                    "when you open them from the app."
                ),
            ),
            Block(
                anchor="theme",
                heading="Theme",
                body=(
                    "System, Light or Dark. **System** follows your phone, "
                    "including its automatic day-and-night schedule, and is the "
                    "default.\n\n"
                    "Dark mode is a true dark, not a grey — worth knowing if you "
                    "read plans in bed."
                ),
            ),
            Block(
                anchor="sounds-and-haptics",
                heading="Sound effects and haptics",
                body=(
                    "Two independent switches. **Sound effects** are the small cues "
                    "— a notification arriving, a rating landing. **Haptics** are "
                    "the taps you feel, including one short buzz per star as you "
                    "set a rating.\n\n"
                    "Each acknowledges itself with the setting you just chose, so "
                    "you can hear or feel what you are turning on."
                ),
            ),
            Block(
                anchor="shake-to-report",
                heading="Shake to report",
                body=(
                    "On by default on phones: shaking captures the screen and opens "
                    "a bug report. If you gesture a lot while reading, turn it off "
                    "here — **Settings ▸ Support ▸ Shake to report**.\n\n"
                    "It is deliberately hard to trigger by accident: it wants two "
                    "distinct shakes, ignores you unless the app is in front, and "
                    "waits a few seconds before it can fire again."
                ),
            ),
            Block(
                anchor="account-rows",
                heading="The rest of the menu",
                body=(
                    "- **Account status** — moderation decisions and appeals\n"
                    "- **Blocked accounts** — everyone you have blocked, and "
                    "one tap to unblock\n"
                    "- **Follow requests** — only shown if your account is private\n"
                    "- **Help Center** and **About** — including this site\n\n"
                    "Changing your password or deleting your account is on your "
                    "profile's edit screen, under Security."
                ),
            ),
        ),
    ),
    Article(
        slug="permissions",
        title="What permissions Ntripi asks for, and why",
        summary=(
            "Location, notifications, photos and motion — what each is for, when "
            "you are asked, and how to change your mind."
        ),
        category="account",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "permission", "permissions", "privacy", "location", "gps", "camera",
            "photos", "notifications", "microphone", "contacts", "tracking",
            "access", "allow", "deny",
        ),
        related=("your-data-and-privacy", "notifications",
                 "add-locations-from-google-maps"),
        cta="See exactly what the app does — and does not — ask for.",
        intro=(
            "Ntripi asks for four things, each at the moment it is first useful "
            "rather than at launch. **It never asks for your camera, your "
            "contacts, your microphone, or your location in the background.** "
            "Refusing any of them leaves the app working."
        ),
        blocks=(
            Block(
                anchor="location",
                heading="Location — why?",
                kind=KIND_FAQ,
                body=(
                    "To centre the map on where you are when you add a stop, so you "
                    "are not scrolling across a continent to find the town you are "
                    "standing in.\n\n"
                    "It is asked the first time you use the map's locate button, "
                    "and **only while you are using the app** — there is no "
                    "background location and no tracking. Refusing does not block "
                    "anything: the map opens elsewhere and you pan to your spot."
                ),
            ),
            Block(
                anchor="notifications",
                heading="Notifications — why, and why only once?",
                kind=KIND_FAQ,
                body=(
                    "To tell you about follow requests, ratings, saves and "
                    "moderation decisions.\n\n"
                    "You are asked the first time you open the **notifications "
                    "screen** — that is, at the moment you have just shown you want "
                    "them. iOS allows an app exactly one prompt per install, so "
                    "asking at launch, in front of an app you have not seen yet, "
                    "would spend that one chance on a stranger."
                ),
            ),
            Block(
                anchor="photos",
                heading="Photos — what does Ntripi see?",
                kind=KIND_FAQ,
                body=(
                    "Only the image you pick. Ntripi opens your system's photo "
                    "picker, which hands back a single file and nothing else — it "
                    "has no view of your library.\n\n"
                    "Every upload has its **EXIF metadata stripped**, including the "
                    "GPS coordinates of where the photo was taken. See [cover "
                    "photos](/help/trip-cover-photos)."
                ),
            ),
            Block(
                anchor="motion",
                heading="Motion and vibration — what for?",
                kind=KIND_FAQ,
                body=(
                    "Shaking the phone files a bug report, and the phone buzzes "
                    "briefly to acknowledge things like setting a rating.\n\n"
                    "Both can be switched off in **Settings**: **Shake to report** "
                    "and **Haptics**. Nothing about your movement leaves the "
                    "device."
                ),
            ),
            Block(
                anchor="never-asked",
                heading="What does Ntripi never ask for?",
                kind=KIND_FAQ,
                body=(
                    "The **camera**, your **contacts**, your **microphone**, and "
                    "**background location**. None of them appear in the app, and "
                    "none are declared in the builds we ship.\n\n"
                    "If something ever claims Ntripi is asking for one of these, it "
                    "is not us — [tell us](/help/contact)."
                ),
            ),
            Block(
                anchor="changing-your-mind",
                heading="How do I change a permission later?",
                kind=KIND_FAQ,
                body=(
                    "Permissions belong to your operating system, not to Ntripi, so "
                    "they are changed there:\n\n"
                    "- **iPhone or iPad** — Settings ▸ scroll to Ntripi ▸ toggle "
                    "Location or Notifications.\n"
                    "- **Android** — Settings ▸ Apps ▸ Ntripi ▸ Permissions.\n\n"
                    "This matters most for notifications, which iOS will not "
                    "re-prompt for: once refused, the Settings app is the only way "
                    "back."
                ),
            ),
        ),
    ),
    Article(
        slug="your-data-and-privacy",
        title="What data Ntripi stores, and how to delete it",
        summary=(
            "A plain-language summary of what is kept, who can see it, and how to "
            "remove your account for good."
        ),
        category="account",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "privacy", "data", "gdpr", "delete account", "remove", "export",
            "personal data", "tracking", "ads", "advertising", "who can see",
        ),
        related=("permissions", "sign-in-and-account-security",
                 "share-an-itinerary-privately"),
        intro=(
            "Ntripi stores what you type and what you upload, plus what it needs to "
            "sign you in. There is no advertising, no third-party ad tracking, and "
            "nothing is sold. The [privacy policy](/privacy) is the authoritative "
            "text; this is the short version."
        ),
        blocks=(
            Block(
                anchor="what-is-stored",
                heading="What does Ntripi store about me?",
                kind=KIND_FAQ,
                body=(
                    "- **Your account** — display name, username, email address, "
                    "and date of birth (never shown to anyone).\n"
                    "- **What you create** — trips, stops, notes, ratings, and any "
                    "images you upload.\n"
                    "- **Your connections** — who you follow, who follows you, who "
                    "you have blocked.\n"
                    "- **Session data** — enough to keep you signed in, and a "
                    "device token if you turned push notifications on.\n\n"
                    "Uploaded images have their EXIF metadata stripped, including "
                    "the GPS coordinates of where a photo was taken."
                ),
            ),
            Block(
                anchor="who-sees-it",
                heading="Who can see what I write?",
                kind=KIND_FAQ,
                body=(
                    "Whoever your [visibility "
                    "setting](/help/share-an-itinerary-privately) says, and nobody "
                    "else. A trip set to **only me** is visible to you and to "
                    "anyone you invited to edit it.\n\n"
                    "Your date of birth is never visible to another user, on any "
                    "setting. Your email address is not shown on your profile."
                ),
            ),
            Block(
                anchor="moderation",
                heading="Does anyone at Ntripi read my trips?",
                kind=KIND_FAQ,
                body=(
                    "Not routinely. Text and images are checked automatically when "
                    "published, and a person only looks at something when it is "
                    "reported or flagged by those checks.\n\n"
                    "Automated checks send the content and nothing else — no user "
                    "id, no email, no name."
                ),
            ),
            Block(
                anchor="deleting",
                heading="How do I delete my account?",
                kind=KIND_FAQ,
                body=(
                    "Your profile's edit screen, under Security ▸ **Delete "
                    "account**. You confirm with your password, or with Google if "
                    "that is how you sign in.\n\n"
                    "Deletion is permanent and takes your trips with it. Trips "
                    "other people saved stop working, since a bookmark is a pointer "
                    "rather than a copy."
                ),
            ),
            Block(
                anchor="requests",
                heading="How do I ask for a copy of my data?",
                kind=KIND_FAQ,
                body=(
                    "Write to **[privacy@ntripi.app](mailto:privacy@ntripi.app)**. "
                    "That address is the data-protection contact named in the "
                    "[privacy policy](/privacy), and it reaches the people who can "
                    "actually action a request.\n\n"
                    "The same address covers correction, restriction and objection "
                    "requests."
                ),
            ),
        ),
    ),
    Article(
        slug="sign-in-and-account-security",
        title="Signing in, passwords and deleting your account",
        summary=(
            "Email, Google or Apple sign-in, resetting a password, why some actions "
            "need a verified email, and how to leave."
        ),
        category="account",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "login", "log in", "sign in", "password", "forgot password", "reset",
            "google", "apple", "verify", "verification", "email", "locked out",
            "delete account", "age", "16",
        ),
        related=("your-data-and-privacy", "troubleshooting"),
        intro=(
            "You can sign in with an email address and password, with Google, or "
            "with Apple. All three reach the same account, and you can add a "
            "password later to an account created with Google."
        ),
        blocks=(
            Block(
                anchor="forgot-password",
                heading="I've forgotten my password",
                kind=KIND_FAQ,
                body=(
                    "Use **Forgot password** on the sign-in screen. A reset link "
                    "arrives by email and is valid for a short window.\n\n"
                    "If no mail arrives, check the spam folder and confirm you are "
                    "using the address you signed up with. If you signed up with "
                    "Google, you may have no password at all — sign in with Google "
                    "instead."
                ),
            ),
            Block(
                anchor="verify-email",
                heading="Why can't I create a trip, rate, or follow?",
                kind=KIND_FAQ,
                body=(
                    "Those three need a verified email address. Check your inbox "
                    "for the verification link, or use the banner on your profile "
                    "to send another.\n\n"
                    "Signing in with Google on the same address also verifies it. "
                    "The requirement is what keeps throwaway accounts out of the "
                    "ratings and out of people's followers."
                ),
            ),
            Block(
                anchor="changing-password",
                heading="How do I change my password?",
                kind=KIND_FAQ,
                body=(
                    "Profile ▸ edit ▸ **Security ▸ Change password**. You confirm "
                    "with your current one.\n\n"
                    "Changing it signs out every **other** session and keeps the one "
                    "you are using — so if you are changing it because you think "
                    "someone else got in, that alone removes them."
                ),
            ),
            Block(
                anchor="age",
                heading="Why does Ntripi ask my date of birth?",
                kind=KIND_FAQ,
                body=(
                    "Ntripi has a minimum age of **16**, and the [terms](/terms) "
                    "say so, which means it has to be asked rather than assumed.\n\n"
                    "It is never shown on your profile and never visible to another "
                    "user. It is asked once and not asked again."
                ),
            ),
            Block(
                anchor="suspended",
                heading="My account is suspended",
                kind=KIND_FAQ,
                body=(
                    "You will have had an email explaining why, with a link to "
                    "appeal. Appeals are read by a person.\n\n"
                    "If you no longer have the email, the appeal form can send you "
                    "a fresh link. See [hidden content and "
                    "appeals](/help/hidden-content-and-appeals)."
                ),
            ),
            Block(
                anchor="deleting",
                heading="How do I delete my account?",
                kind=KIND_FAQ,
                body=(
                    "Profile ▸ edit ▸ **Security ▸ Delete account**, confirmed with "
                    "your password or with Google.\n\n"
                    "It is permanent, and it takes your trips with it. If you only "
                    "want to disappear from view, setting your trips to [only "
                    "me](/help/share-an-itinerary-privately) and making your account "
                    "private is reversible where deletion is not."
                ),
            ),
        ),
    ),
    # ── Safety and moderation ───────────────────────────────────────────────
    Article(
        slug="report-and-block",
        title="How to report content or block someone",
        summary=(
            "Flag a trip, review or profile that breaks the rules, and cut off "
            "someone you would rather not deal with."
        ),
        category="safety",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "report", "flag", "block", "abuse", "harassment", "spam", "unsafe",
            "inappropriate", "unblock", "safety",
        ),
        related=("hidden-content-and-appeals", "follow-and-private-accounts",
                 "contact"),
        intro=(
            "Reporting sends something to moderation; blocking removes a person "
            "from your experience. They are different tools and you can use both. "
            "Neither tells the other person what you did."
        ),
        blocks=(
            Block(
                anchor="report",
                heading="Report a trip, a review or a profile",
                kind=KIND_STEP,
                body=(
                    "Use the flag action on the thing itself — a trip, a stop, a "
                    "review, a note or a profile. Pick a reason and add anything "
                    "that helps.\n\n"
                    "Reporting from the item carries the context with it, which is "
                    "why it is better than emailing us a description. You do not "
                    "need an account to report from a public share page."
                ),
            ),
            Block(
                anchor="reasons",
                heading="Choosing a reason",
                body=(
                    "The reasons are: child sexual abuse material, sexual content, "
                    "violence or threats, hate speech, harassment, spam, and "
                    "other.\n\n"
                    "Pick the closest one — it decides how urgently the report is "
                    "handled. **Anything involving a child is treated as the "
                    "highest priority** and goes into a separate queue."
                ),
            ),
            Block(
                anchor="what-happens",
                heading="What happens after I report?",
                body=(
                    "It joins the moderation queue. Content reported by several "
                    "different people, or corroborated by the automated checks, can "
                    "be hidden immediately while a person reviews it.\n\n"
                    "The author is never told who reported them. You will not "
                    "usually get a reply — the outcome is the content staying or "
                    "going."
                ),
            ),
            Block(
                anchor="block",
                heading="Block someone",
                kind=KIND_STEP,
                body=(
                    "From their profile, or by holding your finger on something "
                    "they published.\n\n"
                    "Blocking cuts visibility **in both directions**: you stop "
                    "seeing them and they stop seeing you. Any follow between you "
                    "is removed. They are not told, and your profile becomes "
                    "indistinguishable to them from one that never existed."
                ),
            ),
            Block(
                anchor="unblock",
                heading="Unblock someone",
                kind=KIND_STEP,
                body=(
                    "**Settings ▸ Blocked accounts** lists everyone you have "
                    "blocked, with one tap to reverse it.\n\n"
                    "Unblocking does not restore the follow that blocking removed — "
                    "either of you can follow again if you want to."
                ),
            ),
            Block(
                anchor="urgent",
                heading="If someone is in danger",
                body=(
                    "Contact your local emergency services first. Ntripi cannot "
                    "reach anyone quickly enough to be the right first call.\n\n"
                    "Then write to **[abuse@ntripi.app](mailto:abuse@ntripi.app)**, "
                    "which is monitored for exactly this."
                ),
            ),
        ),
    ),
    Article(
        slug="hidden-content-and-appeals",
        title="Why your content was hidden, and how to appeal",
        summary=(
            "What it means when a trip or review is hidden, where to see the "
            "reason, and how to ask a person to look again."
        ),
        category="safety",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "hidden", "removed", "takedown", "moderation", "appeal", "banned",
            "suspended", "warning", "blocked content", "restored",
        ),
        related=("report-and-block", "sign-in-and-account-security", "contact"),
        intro=(
            "If something you published was hidden, you get a notification and a "
            "reason, and **Settings ▸ Account status** keeps the record. Most "
            "decisions can be appealed, and an appeal is read by a person."
        ),
        blocks=(
            Block(
                anchor="what-hidden-means",
                heading="What does hidden mean?",
                kind=KIND_FAQ,
                body=(
                    "Nobody else can open it. **You still can** — it stays in your "
                    "list with a banner explaining why, and nothing is deleted "
                    "while an appeal is possible.\n\n"
                    "Hiding is reversible in a way deleting is not, which is why it "
                    "is the first step rather than the last."
                ),
            ),
            Block(
                anchor="why",
                heading="Why was mine hidden?",
                kind=KIND_FAQ,
                body=(
                    "Either enough different people reported it, an automated check "
                    "flagged it, or a moderator decided it breaks the [community "
                    "guidelines](/guidelines).\n\n"
                    "The reason is on the banner and on **Settings ▸ Account "
                    "status**. Some hides are provisional — applied automatically "
                    "while a person gets to it — which is exactly why they are "
                    "appealable."
                ),
            ),
            Block(
                anchor="appealing",
                heading="How do I appeal?",
                kind=KIND_FAQ,
                body=(
                    "**Settings ▸ Account status** lists every decision with an "
                    "appeal button. Explain in your own words why you think it was "
                    "wrong.\n\n"
                    "One open appeal per decision, and one attempt per decision "
                    "within a month — the limit exists so the queue stays short "
                    "enough that appeals actually get read."
                ),
            ),
            Block(
                anchor="warnings",
                heading="I got a warning but nothing was hidden",
                kind=KIND_FAQ,
                body=(
                    "A warning is a note on your account with nothing taken down. "
                    "It is a signal, and it is also a record — a second warning is "
                    "recorded as a second warning, not folded into the first.\n\n"
                    "Warnings can be appealed like anything else."
                ),
            ),
            Block(
                anchor="suspended",
                heading="My whole account is suspended",
                kind=KIND_FAQ,
                body=(
                    "You cannot sign in, so the appeal cannot live inside the app. "
                    "The suspension email carries a link to a web form; if you no "
                    "longer have it, the form can send a fresh link to your "
                    "address.\n\n"
                    "Suspensions are reversible, and an appeal that succeeds "
                    "restores the account rather than rebuilding it."
                ),
            ),
            Block(
                anchor="after",
                heading="What happens after I appeal?",
                kind=KIND_FAQ,
                body=(
                    "A person reads it and either restores the content or leaves "
                    "the decision standing, and you are told which.\n\n"
                    "If a decision is overturned, the content comes back as it was "
                    "— nothing was deleted in the meantime."
                ),
            ),
        ),
    ),
    # ── Troubleshooting ─────────────────────────────────────────────────────
    Article(
        slug="troubleshooting",
        title="Ntripi isn't working: common problems and fixes",
        summary=(
            "The messages people hit most often, what each one actually means, and "
            "what to do next."
        ),
        category="troubleshooting",
        schema=SCHEMA_FAQ,
        updated="2026-09-01",
        keywords=(
            "error", "problem", "problems", "broken", "not working", "failed",
            "failing", "stuck", "cannot save", "can not save", "reload",
            "offline", "crash", "bug", "fix", "help",
        ),
        related=("contact", "getting-started"),
        intro=(
            "Most problems in Ntripi come from one of three things: two people "
            "editing the same trip, a lost connection, or an account step that has "
            "not been completed yet. Find the message you saw below."
        ),
        blocks=(
            Block(
                anchor="modified-please-reload",
                heading="\"This itinerary was modified, please reload\"",
                kind=KIND_FAQ,
                body=(
                    "The trip changed after your screen loaded it — usually because "
                    "you have it open on another device, or someone you invited to "
                    "edit saved something first.\n\n"
                    "Reload the trip and make your change again. Ntripi refuses the "
                    "save rather than silently overwriting whatever came in while "
                    "you were typing."
                ),
            ),
            Block(
                anchor="someone-else-is-editing",
                heading="\"Someone else is editing this trip\"",
                kind=KIND_FAQ,
                body=(
                    "Only one person can edit a trip at a time. Someone else — or "
                    "you, on another device — currently holds it.\n\n"
                    "Wait for them to finish, or take over if they have been idle "
                    "for a while. If you are the owner, you can always take it back. "
                    "Taking over ends the other person's session, so they will be "
                    "told rather than losing work silently."
                ),
            ),
            Block(
                anchor="lost-the-edit",
                heading="I was editing and it stopped letting me save",
                kind=KIND_FAQ,
                body=(
                    "Someone took over the trip while you had it open. **Your typing "
                    "is not lost** — the screen stays exactly as it was, with every "
                    "field still filled in.\n\n"
                    "You have two ways out, and both keep your work: take the trip "
                    "back and save, or copy your text out and paste it in once the "
                    "other person is done. Nothing is discarded until you leave the "
                    "screen yourself."
                ),
            ),
            Block(
                anchor="image-rejected",
                heading="My photo was rejected when I uploaded it",
                kind=KIND_FAQ,
                body=(
                    "Uploads are checked automatically before they are stored. An "
                    "image can be refused for being too small, for being an "
                    "unsupported format, or for content that does not meet the "
                    "[community guidelines](/guidelines).\n\n"
                    "Try a larger image, at least 600 pixels on its shortest side. "
                    "If you believe a rejection was wrong, [get in "
                    "touch](/help/contact)."
                ),
            ),
            Block(
                anchor="text-rejected",
                heading="My text was refused when I tried to save it",
                kind=KIND_FAQ,
                body=(
                    "Text you write is checked against the [community "
                    "guidelines](/guidelines) before it is stored.\n\n"
                    "You may also see a quiet advisory note under a field as you "
                    "type. That one is only a warning — it never blocks you and "
                    "never changes what you wrote. Place names in particular can "
                    "trip a warning without being a problem."
                ),
            ),
            Block(
                anchor="cannot-create",
                heading="I can't create a trip, rate one, or follow anyone",
                kind=KIND_FAQ,
                body=(
                    "These need a verified email address. Check your inbox for the "
                    "verification link, or use the banner on your profile to send "
                    "another.\n\n"
                    "Signing in with Google on the same email address also verifies "
                    "it."
                ),
            ),
            Block(
                anchor="offline",
                heading="There's a bar saying I'm offline",
                kind=KIND_FAQ,
                body=(
                    "Ntripi noticed the connection dropped. You can keep reading "
                    "anything already loaded; controls that would need the server "
                    "are dimmed until you are back.\n\n"
                    "The bar clears itself when the connection returns — there is "
                    "nothing to tap."
                ),
            ),
            Block(
                anchor="still-stuck",
                heading="None of this matches what I'm seeing",
                kind=KIND_FAQ,
                body=(
                    "Report it from inside the app: **shake your phone** and Ntripi "
                    "captures the screen so you can circle the problem before "
                    "sending. See [how to contact us](/help/contact)."
                ),
            ),
        ),
    ),
    Article(
        slug="report-a-bug",
        title="How to report a bug in Ntripi",
        summary=(
            "Shake your phone to capture the screen, circle what is wrong, and "
            "send it — or use the button on the web."
        ),
        category="troubleshooting",
        schema=SCHEMA_HOWTO,
        updated="2026-09-01",
        keywords=(
            "bug", "bugs", "report", "broken", "crash", "feedback", "shake",
            "screenshot", "problem", "glitch",
        ),
        related=("troubleshooting", "contact"),
        intro=(
            "**Shake your phone.** Ntripi captures the screen you were looking at, "
            "hands you a pen to circle the problem, and sends it with your note. "
            "It is far faster than describing a layout in words, and it attaches "
            "your device and version for you."
        ),
        blocks=(
            Block(
                anchor="shake",
                heading="Shake the phone",
                kind=KIND_STEP,
                body=(
                    "Anywhere in the app, at the moment something looks wrong. A "
                    "screenshot of that exact screen is captured.\n\n"
                    "It takes two distinct shakes, so a walk or a bus ride will not "
                    "trigger it. It is also ignored while the app is in the "
                    "background, and waits a few seconds before it can fire again."
                ),
            ),
            Block(
                anchor="draw",
                heading="Circle the problem",
                kind=KIND_STEP,
                body=(
                    "Draw straight onto the screenshot. One circle round the wrong "
                    "thing removes an entire paragraph of explanation.\n\n"
                    "You can navigate while the reporter is open if you need to "
                    "capture a different screen."
                ),
            ),
            Block(
                anchor="describe",
                heading="Pick a category and describe it",
                kind=KIND_STEP,
                body=(
                    "Choose one of: crash, visual, data, slow, or other. Then say "
                    "what you did, what you expected, and what happened.\n\n"
                    "Nothing is sent until you tap send."
                ),
            ),
            Block(
                anchor="what-is-sent",
                heading="What gets sent with it",
                body=(
                    "Your note, your category, the screenshot, and technical "
                    "details about the device and app version — the things that are "
                    "tedious to type and are always the first questions.\n\n"
                    "The screenshot has its metadata stripped like any other "
                    "upload. It is never shown to another user, and bug reports are "
                    "deleted once they are closed and stale, because a screenshot "
                    "can contain someone else's information."
                ),
            ),
            Block(
                anchor="web-and-off",
                heading="On the web, or with the gesture off",
                body=(
                    "Browsers have no shake, so on the web use **Settings ▸ Support "
                    "▸ Report a bug**, which opens the same reporter.\n\n"
                    "If you turned the gesture off on a phone, the same menu item "
                    "still works. To turn it back on: **Settings ▸ Support ▸ Shake "
                    "to report**."
                ),
            ),
        ),
    ),
    # ── About Ntripi ────────────────────────────────────────────────────────
    Article(
        slug="contact",
        title="How to contact Ntripi support",
        summary=(
            "Where to send a bug, a safety concern, a privacy request or a general "
            "question — and what to include."
        ),
        category="about",
        schema=SCHEMA_CONTACT,
        updated="2026-09-01",
        keywords=(
            "support", "email", "contact", "help", "feedback", "bug", "bugs",
            "report", "abuse", "privacy", "complaint",
        ),
        related=("troubleshooting",),
        intro=(
            "The fastest way to report a problem with the app is to **shake your "
            "phone** — Ntripi captures the screen and lets you draw on it before "
            "sending. For anything else, use the address below that matches what "
            "you need."
        ),
        blocks=(
            Block(
                anchor="report-a-bug",
                heading="Report a bug from inside the app",
                body=(
                    "**Shake your phone.** Ntripi takes a screenshot, hands you a "
                    "pen to circle what is wrong, and lets you add a note and a "
                    "category before sending.\n\n"
                    "The screenshot goes with the report, which saves you "
                    "describing a layout in words. Nothing is sent until you tap "
                    "send.\n\n"
                    "You can turn the gesture off in **Settings ▸ Support ▸ Shake "
                    "to report**. On the web there is no shake, so use **Settings ▸ "
                    "Support ▸ Report a bug** instead."
                ),
            ),
            Block(
                anchor="email-us",
                heading="Email us",
                body=(
                    "- **[support@ntripi.app](mailto:support@ntripi.app)** — the app "
                    "is broken, or you are stuck.\n"
                    "- **[abuse@ntripi.app](mailto:abuse@ntripi.app)** — content or "
                    "behaviour that breaks the [community "
                    "guidelines](/guidelines), and anything urgent about someone's "
                    "safety.\n"
                    "- **[privacy@ntripi.app](mailto:privacy@ntripi.app)** — data "
                    "protection requests, and anything covered by the [privacy "
                    "policy](/privacy).\n"
                    "- **[contact@ntripi.app](mailto:contact@ntripi.app)** — "
                    "everything else."
                ),
            ),
            Block(
                anchor="what-to-include",
                heading="What to include",
                body=(
                    "A report is much faster to act on with:\n\n"
                    "- **What you did**, in the order you did it.\n"
                    "- **What you expected**, and what happened instead.\n"
                    "- **A screenshot**, if the problem is visible.\n"
                    "- **Your device and app version** — the in-app reporter "
                    "attaches these automatically, which is one more reason to use "
                    "it where you can."
                ),
            ),
            Block(
                anchor="reporting-content",
                heading="Reporting content rather than a bug",
                body=(
                    "To report something another person published, use the flag "
                    "action on the trip, review or profile itself rather than "
                    "email. It reaches the moderation queue directly and carries "
                    "the context with it.\n\n"
                    "Reports are not shown to the person you reported."
                ),
            ),
        ),
    ),
    Article(
        slug="whats-new",
        title="What's new in Ntripi",
        summary=(
            "Recent releases: what was added, what changed and what was fixed."
        ),
        category="about",
        schema=SCHEMA_RELEASES,
        updated="2026-09-01",
        keywords=(
            "changelog", "release notes", "updates", "new", "version", "changes",
            "what changed", "history",
        ),
        related=("getting-started", "contact"),
        intro=(
            "Ntripi is in active development ahead of its public launch. Each "
            "release below names what changed and why it might matter to you."
        ),
        releases=RELEASES,
    ),
)

