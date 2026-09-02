"""
constants/help/de.py — the German help centre.

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
        title="Erste Schritte",
        blurb="Konto anlegen und die erste Reise planen.",
        icon="rocket",
    ),
    Category(
        id="building",
        title="Eine Reise aufbauen",
        blurb="Stopps, Orte, Transport und die Notizen dazu.",
        icon="article",
    ),
    Category(
        id="sharing",
        title="Teilen und Sichtbarkeit",
        blurb="Entscheiden, wer eine Reise sieht und wie Sie sie verschicken.",
        icon="lock",
    ),
    Category(
        id="community",
        title="Community",
        blurb="Folgen, Bewertungen, gespeicherte Reisen und der Feed.",
        icon="group",
    ),
    Category(
        id="account",
        title="Konto und Einstellungen",
        blurb="Anmeldung, Benachrichtigungen, Berechtigungen und Ihre Daten.",
        icon="person",
    ),
    Category(
        id="safety",
        title="Sicherheit und Moderation",
        blurb="Melden, Blockieren, ausgeblendete Inhalte und Einsprüche.",
        icon="flag",
    ),
    Category(
        id="troubleshooting",
        title="Fehlerbehebung",
        blurb="Wenn etwas nicht so funktioniert wie erwartet.",
        icon="warning",
    ),
    Category(
        id="about",
        title="Über Ntripi",
        blurb="Kontakt und was sich in der letzten Version geändert hat.",
        icon="info",
    ),
)

RELEASES: tuple[Release, ...] = (
    Release(
        version="0.3.0",
        date="2026-09-01",
        headline="Gemeinsames Bearbeiten, Push-Benachrichtigungen und ein Hilfebereich",
        entries=(
            "**Andere zum Bearbeiten einer Reise einladen.** Eigentümer können jetzt anderen Konten Bearbeitungsrechte geben — es bearbeitet immer nur eine Person, damit niemandes Arbeit überschrieben wird.",
            "**Push-Benachrichtigungen** auf iOS und Android, für Follows, Bewertungen, Speicherungen und Moderationshinweise.",
            "**Dieser Hilfebereich**, in dem all das aufgeschrieben ist.",
        ),
    ),
)

ARTICLES: tuple[Article, ...] = (
    Article(
        slug="getting-started",
        title="So planen Sie Ihre erste Reise in Ntripi",
        summary="Konto anlegen, die fünf Tabs kennenlernen und in wenigen Minuten die erste Reise aufbauen.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Ntripi ist eine Reise-App, mit der Sie Reisepläne aus echten Stopps bauen — mit dem, was jeder kostet, wie lange er dauert und wie Sie dazwischen unterwegs sind — und sie mit den Menschen teilen, die Sie auswählen. Legen Sie ein Konto an, öffnen Sie den Tab **Reiserouten** und fügen Sie Ihre erste Reise hinzu.",
        blocks=(
            Block(
                anchor="create-an-account",
                heading="Ein Konto anlegen",
                kind=KIND_STEP,
                body="""Es gibt drei Wege: mit E-Mail-Adresse und Passwort, mit **Mit Google anmelden** oder mit **Mit Apple anmelden**. Alle drei führen an dieselbe Stelle.

Sie werden nach einem Anzeigenamen, einem Benutzernamen und Ihrem Geburtsdatum gefragt. Ntripi hat ein Mindestalter von 16 Jahren. Ihr Geburtsdatum erscheint nie in Ihrem Profil, und kein anderer Nutzer kann es sehen.

Ihr Anzeigename kann beliebig sein, in jeder Sprache, bis zu 50 Zeichen. Ihr Benutzername ist der `@name`, über den andere Sie finden, und er wird angezeigt, wenn Sie nie einen Anzeigenamen festlegen.""",
            ),
            Block(
                anchor="verify-your-email",
                heading="E-Mail-Adresse bestätigen",
                kind=KIND_STEP,
                body="""Einige Aktionen bleiben gesperrt, bis Ihre E-Mail-Adresse bestätigt ist: eine Reise anlegen, eine bewerten und Personen folgen. Das hält Wegwerfkonten aus den Bewertungen heraus.

Suchen Sie den Bestätigungslink in Ihrem Posteingang. Wenn Sie sich mit derselben Adresse über Google registriert haben, bestätigt die Anmeldung mit Google sie für Sie — ein Hinweis in Ihrem Profil bietet das an.""",
            ),
            Block(
                anchor="the-five-tabs",
                heading="Zurechtfinden: die fünf Tabs",
                kind=KIND_STEP,
                body="""Die Leiste unten hat fünf Tabs. Von links nach rechts:

- **Suche** — findet *Personen*, keine Reisen. Suchen Sie nach Benutzernamen.
- **Profil** — Ihr eigenes Profil und das Zahnrad, das alle Einstellungen öffnet.
- **Reiserouten** — Ihre eigenen Reisen sowie die, zu deren Bearbeitung Sie eingeladen wurden.
- **Gespeichert** — Reisen, die Sie mit einem Lesezeichen versehen haben.
- **Feed** — öffentliche Reisen von allen, in der Reihenfolge **Top** und **Neueste**.

Die Glocke neben dem Zahnrad in Ihrem Profil öffnet Ihre Benachrichtigungen.""",
            ),
            Block(
                anchor="build-your-first-trip",
                heading="Die erste Reise aufbauen",
                kind=KIND_STEP,
                body="""Öffnen Sie **Reiserouten** und tippen Sie auf **+**. Geben Sie der Reise einen Titel und wählen Sie die Währung, in der Sie Kosten notieren, und beginnen Sie dann, Stopps hinzuzufügen.

Neue Reisen sind **nur für Sie** sichtbar, bis Sie das ändern — Ausprobieren ist also risikolos. Siehe [wie Sie eine Reiseroute planen](/help/plan-a-trip-itinerary) für den vollständigen Ablauf.""",
            ),
            Block(
                anchor="where-to-get-help",
                heading="Hilfe direkt in der App",
                body="""Die meisten Formularfelder haben ein kleines **?**-Symbol neben der Beschriftung. Ein Tippen erklärt, wofür das Feld da ist, ohne den Bildschirm zu verlassen — der schnellste Weg, ein unbekanntes Feld zu verstehen.

**Einstellungen ▸ Hilfebereich** enthält die häufigen Fragen und die Wege, uns zu erreichen. Wenn etwas kaputt ist, siehe [wie Sie einen Fehler melden](/help/contact).""",
            ),
        ),
        keywords=(
            "registrieren",
            "anmelden",
            "konto erstellen",
            "neues konto",
            "zum ersten mal",
            "anfänger",
            "einführung",
            "grundlagen",
            "loslegen",
            "starten",
        ),
        related=("plan-a-trip-itinerary", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="Lust, etwas zu planen? Legen Sie Ihre erste Reise an.",
    ),
    Article(
        slug="plan-a-trip-itinerary",
        title="So planen Sie eine Reiseroute, Schritt für Schritt",
        summary="Eine Reiseroute mit echten Stopps, Kosten, Zeit und Transport bauen — von der leeren Reise bis zur teilbaren.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Eine Reise in Ntripi ist eine geordnete Liste von Stopps. Jeder Stopp ist ein echter Ort mit Position, ungefähren Kosten und der Zeit, die Sie dort einplanen. Zwischen den Stopps notieren Sie, wie Sie unterwegs sind. Bauen Sie sie in vier Durchgängen: Reise anlegen, Stopps hinzufügen, verbinden, dann festlegen, wer sie sehen darf.",
        blocks=(
            Block(
                anchor="create-the-trip",
                heading="Die Reise anlegen",
                kind=KIND_STEP,
                body="""Tippen Sie im Tab **Reiserouten** auf **+**. Zum Start brauchen Sie einen Titel; alles andere kann warten.

- **Titel** — worum es geht. „Vier Tage in Marrakesch“ ist besser als „Marokko“.
- **Währung** — jede Kostenangabe verwendet sie, damit die Summe stimmt. Wählen Sie die, die Sie tatsächlich ausgeben.
- **Titelbild** — optional, und später nachtragbar. Es ist das, was andere im Feed und in einem geteilten Link sehen.
- **Beste Reisezeit** — die Monate, in denen diese Reise funktioniert. Nützlich bei allem Saisonalen.""",
            ),
            Block(
                anchor="add-stops",
                heading="Stopps hinzufügen",
                kind=KIND_STEP,
                body="""Tippen Sie in der Reise auf **+**, um einen Stopp anzulegen. Ein Stopp enthält:

- **Name und Adresse** — wie der Ort heißt.
- **Position** — einen Punkt auf der Karte wählen oder einen Google-Maps-Link einfügen und Ntripi die Koordinaten daraus lesen lassen.
- **Ortstyp** — Essen und Trinken, Schlafen, Sehenswürdigkeiten, Natur, Einkaufen und so weiter. Das zeichnet das richtige Symbol auf der Karte und in der Liste.
- **Kosten** — ungefähr, was es pro Person kostet. Leer lassen oder als kostenlos markieren.
- **Aufenthaltsdauer** — wie viel Zeit einzuplanen ist. Das macht einen Plan realistisch statt optimistisch.
- **Notizen** — alles, woran Sie sich erinnern wollen.

Fügen Sie Stopps in der Reihenfolge des Besuchs hinzu. Verschieben können Sie sie später jederzeit.""",
            ),
            Block(
                anchor="connect-the-stops",
                heading="Festhalten, wie Sie zwischen Stopps unterwegs sind",
                kind=KIND_STEP,
                body="""Zwischen zwei Stopps können Sie einen **Transportabschnitt** ergänzen: wie Sie reisen, wie lange es dauert und was es kostet.

Ein Abschnitt kann mehrere Teilstrecken haben — ein Bus zum Bahnhof, dann ein Zug — und jede Teilstrecke kann Liniennummer und Fahrtrichtung tragen, also genau das Detail, an das man sich am Tag selbst nicht erinnert.""",
            ),
            Block(
                anchor="add-warnings-and-tips",
                heading="Warnungen und Tipps ergänzen",
                kind=KIND_STEP,
                body="""Jeder Stopp und die Reise als Ganzes können kurze Notizen in vier Ausprägungen tragen: **Tipp**, **Vorsicht**, **Vermeiden** und **Info**. Sie erscheinen als farbige Chips und sind damit schwer zu übersehen.

Dorthin gehören „Tickets vorher kaufen“ und „der Nordeingang ist geschlossen“ — die Dinge, die eine reine Route nie verrät.""",
            ),
            Block(
                anchor="choose-who-sees-it",
                heading="Festlegen, wer sie sehen darf",
                kind=KIND_STEP,
                body="""Neue Reisen starten bei **Nur ich**. Wenn Sie so weit sind, öffnen Sie die Einstellungen der Reise und wählen eine von vier Stufen — öffentlich, Follower, bestimmte Personen oder nur Sie.

Siehe [wie Sie eine Reise teilen, ohne sie zu veröffentlichen](/help/share-an-itinerary-privately), was jede Stufe in der Praxis bedeutet.""",
            ),
        ),
        keywords=(
            "reiseplaner",
            "reiseroute",
            "reiserouten",
            "tag für tag",
            "urlaub planen",
            "reise organisieren",
            "route",
            "zeitplan",
            "stopps",
            "budget",
            "kosten",
            "planung",
        ),
        related=("plan-alternative-options", "share-an-itinerary-privately", "getting-started"),
        updated="2026-09-01",
        cta="Planen Sie Ihre eigene Reiseroute — etwa zehn Minuten.",
    ),
    Article(
        slug="app-map",
        title="Die Bildschirme und Symbole von Ntripi, erklärt",
        summary="Eine Führung durch die fünf Tabs, den Reiseroutenbildschirm und die Symbole, die Ihnen unterwegs begegnen.",
        category="getting-started",
        intro="Ntripi hat fünf Tabs unten und sehr wenig darüber. Fast alles, was sich ändern lässt, liegt entweder hinter dem Zahnrad in Ihrem Profil oder hinter einem langen Druck auf das Element selbst. Diese Seite benennt jedes davon.",
        blocks=(
            Block(
                anchor="bottom-nav",
                heading="Die fünf Tabs",
                kind=KIND_DIAGRAM,
                body="""1. **Suche** — findet **Personen**, keine Reisen. Suchen Sie nach Benutzernamen. Öffentliche Reisen entdeckt man stattdessen über den Feed.
2. **Profil** — Ihr eigenes Profil. Das Zahnrad öffnet alle Einstellungen, die Glocke daneben Ihre Benachrichtigungen.
3. **Reiserouten** — Ihre eigenen Reisen und eine zweite Ansicht für die, zu deren Bearbeitung andere Sie eingeladen haben.
4. **Gespeichert** — Ihre Lesezeichen, mit einem Filterfeld.
5. **Feed** — öffentliche Reisen von allen, in der Reihenfolge **Top** und **Neueste**.

Ein Tippen auf den Tab, in dem Sie schon sind, bringt Sie an dessen Anfang zurück — der schnellste Weg aus einem tief verschachtelten Bildschirm.""",
            ),
            Block(
                anchor="itinerary-screen",
                heading="Eine Reiseroute lesen",
                kind=KIND_DIAGRAM,
                body="""1. **Die Sichtbarkeitsmarke** unter dem Titel — wer diese Reise öffnen darf. Als Eigentümer tippen Sie darauf, um sie zu ändern.
2. **Eine zweite Spalte** bedeutet, dass diese beiden Stopps Alternativen zueinander sind, keine Abfolge. Siehe [wie Sie zwei Optionen für denselben Tag planen](/help/plan-alternative-options).
3. **Eine Transportzeile** zwischen zwei Stopps — wie Sie von einem zum nächsten kommen und wie lange das dauert.
4. **Ein farbiger Chip** an einem Stopp ist eine Notiz: Tipp, Vorsicht, Vermeiden oder Info.
5. **Die Bewertungszeile** — der Durchschnitt und wie viele Personen bewertet haben. Durchschnitte erscheinen ab drei.""",
            ),
            Block(
                anchor="icons",
                heading="Symbole, die Ihnen begegnen",
                body="""| Symbol | Was es tut |
|---|---|
| **?** | Erklärt das Feld daneben, ohne den Bildschirm zu verlassen |
| Lesezeichen | Speichert die Reise in Ihrem Tab „Gespeichert“ |
| Stift | Bearbeiten — nur sichtbar, wenn Sie das dürfen |
| Fahne | Uns melden |
| Zahnrad | Einstellungen, in Ihrem eigenen Profil |
| Glocke | Benachrichtigungen, mit Punkt bei Neuem |

Das **?** lohnt sich zu kennen: fast jedes Feld in jedem Formular hat eines, und es ist schneller, als hierherzukommen.""",
            ),
            Block(
                anchor="long-press",
                heading="Abkürzungen per langem Druck",
                body="""Den Finger auf einem Teil einer eigenen Reise zu halten, führt direkt zum Bearbeiten genau dieses Teils — Titel, Titelbild, ein Stopp, eine Notiz. Das spart den Umweg über den Bearbeitungsbildschirm.

Bei der Reise einer anderen Person bietet dieselbe Geste Melden oder Blockieren an. Beides überschneidet sich nie, Sie können also weder Ihre eigene Reise versehentlich melden noch die eines anderen bearbeiten.""",
            ),
        ),
        keywords=(
            "symbole",
            "schaltflächen",
            "menü",
            "navigation",
            "tabs",
            "wo finde ich",
            "was macht dieser knopf",
            "oberfläche",
            "aufbau",
            "bildschirme",
        ),
        related=("getting-started", "app-settings"),
        updated="2026-09-01",
        cta="Sehen Sie selbst — öffnen Sie Ntripi.",
    ),
    Article(
        slug="plan-alternative-options",
        title="So planen Sie zwei Optionen für denselben Tag",
        summary="Alternative Orte nebeneinander in einer Reise, damit ein Regentag oder ein anderes Budget keinen zweiten Plan braucht.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Die meisten Reiseplaner erzwingen einen Ort pro Zeitfenster. Ntripi lässt Sie **Alternativen nebeneinanderstellen**: zwei oder drei Orte, die denselben Punkt der Reise belegen, sodass die reisende Person am Tag selbst entscheidet. Intern heißen diese Spalten **Spalten**.",
        blocks=(
            Block(
                anchor="what-a-track-is",
                heading="Was eine Spalte ist",
                body="""Eine **Spalte** ist eine senkrechte Reihe von Stopps, die Alternativen zueinander sind. Eine Reise mit einer Spalte ist eine gewöhnliche geradlinige Route. Fügen Sie an derselben Stelle eine zweite Spalte hinzu, und Sie haben zwei Möglichkeiten für diesen Teil der Reise.

Spalten helfen immer dann, wenn die Antwort „kommt darauf an“ lautet:

- **Wetter** — eine Option draußen und eine drinnen.
- **Budget** — das teure Restaurant und das gute günstige.
- **Kraft** — die lange Wanderung und der kurze Spaziergang.
- **Geschmack** — das Museum für die eine Hälfte der Gruppe, der Markt für die andere.""",
            ),
            Block(
                anchor="add-an-alternative",
                heading="Eine Alternative hinzufügen",
                kind=KIND_STEP,
                body="""Öffnen Sie die Reise und suchen Sie den Stopp, zu dem Sie eine Alternative möchten. Nutzen Sie das Hinzufügen-Element daneben und wählen Sie, den neuen Stopp in einer **neuen Spalte** abzulegen statt hinter dem bestehenden.

Die beiden Stopps stehen nun nebeneinander. Keiner ist der „echte“ — sie sind gleichrangig, und wer die Reise liest, sieht beide.""",
            ),
            Block(
                anchor="move-a-stop",
                heading="Einen Stopp zwischen Spalten verschieben",
                kind=KIND_STEP,
                body="""Ein Stopp lässt sich nachträglich in eine andere Spalte verschieben, Sie sind also nicht an die Reihenfolge gebunden, in der Sie die Dinge zufällig angelegt haben. Öffnen Sie den Stopp und wählen Sie über die Verschiebe-Aktion seine Spalte.

Eine Spalte existiert nur, solange mindestens ein Stopp darin ist. Verschieben oder löschen Sie den letzten Stopp, verschwindet die leere Spalte von selbst — es bleibt nichts aufzuräumen.""",
            ),
            Block(
                anchor="reorder",
                heading="Spalten und Stopps neu anordnen",
                kind=KIND_STEP,
                body="Ziehen Sie, um Stopps innerhalb einer Spalte und um die Spalten selbst neu anzuordnen. Die erste Spalte einer Reise gilt als Ausgangspunkt und die letzte als Ziel — das ist es, was die Karte verbindet.",
            ),
            Block(
                anchor="transport-warning",
                heading="Warum das Einfügen einer Spalte manchmal warnt",
                body="""Transport wird zwischen zwei *benachbarten* Spalten notiert. Fügen Sie eine neue Spalte zwischen zwei ein, die bereits durch Transport verbunden sind, hat diese Verbindung keinen Platz mehr — die beiden Spalten sind keine Nachbarn mehr.

Ntripi fragt vorher, statt den eingetragenen Transport stillschweigend zu verwerfen. Bestätigen Sie, wird die betroffene Verbindung entfernt; brechen Sie ab, ändert sich nichts.""",
            ),
        ),
        keywords=(
            "parallel",
            "spalte",
            "spalten",
            "alternative",
            "alternativen",
            "optionen",
            "optional",
            "plan b",
            "ausweichplan",
            "verzweigung",
            "entweder oder",
            "regentag",
            "wetter",
            "auswahl",
        ),
        related=("plan-a-trip-itinerary", "getting-started"),
        updated="2026-09-01",
        cta="Planen Sie eine Reise mit echten Alternativen statt einer einzigen fragilen Linie.",
    ),
    Article(
        slug="add-places-to-an-itinerary",
        title="So ergänzen Sie Orte, Kosten und Zeit in einem Reiseplan",
        summary="Alles, was ein Stopp enthalten kann — was er ist, wo er liegt, was er kostet und wie viel Zeit einzuplanen ist.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Ein Stopp ist ein Ort, an dem Sie tatsächlich sein werden. Neben dem Namen sind es zwei Felder, die einen Plan brauchbar machen: **Kosten** und **Aufenthaltsdauer**. Sie machen aus einer Liste von Orten etwas, das sich budgetieren und in einen Tag einpassen lässt.",
        blocks=(
            Block(
                anchor="add-a-stop",
                heading="Einen Stopp hinzufügen",
                kind=KIND_STEP,
                body="""Öffnen Sie die Reise und tippen Sie auf **+**. Geben Sie dem Ort einen Namen — den, den Sie laut sagen würden, nicht die offizielle Bezeichnung — und eine Adresse, falls vorhanden.

Stopps werden in Besuchsreihenfolge angelegt. Sie können sie danach jederzeit in eine andere Reihenfolge ziehen.""",
            ),
            Block(
                anchor="place-type",
                heading="Einen Ortstyp wählen",
                kind=KIND_STEP,
                body="""Der Ortstyp zeichnet das passende Symbol auf der Karte und in der Liste, sodass sich ein Tag auf einen Blick lesen lässt. Es gibt elf:

- **Essen & Trinken** · **Schlafen** · **Einkaufen**
- **Lernen & Sehen** · **Sehenswürdigkeit** · **Unterhaltung**
- **Spielen & Zuschauen** · **Natur** · **Heilen & Baden**
- **Beten** · **Reisen**

Das ist optional. Ein Stopp ohne Typ funktioniert genauso; er sieht nur aus wie alle anderen ohne Typ.""",
            ),
            Block(
                anchor="cost",
                heading="Festhalten, was es kostet",
                kind=KIND_STEP,
                body="""Tragen Sie die ungefähren Kosten **pro Person** in der Währung der Reise ein. Ein Näherungswert genügt — es geht um die Summe am Ende, nicht um eine Rechnung.

Ist ein Ort kostenlos, markieren Sie ihn als kostenlos, statt das Feld leer zu lassen. Leer heißt „habe ich nicht nachgesehen“, und der Unterschied zählt für alle, die Ihren Plan lesen.""",
            ),
            Block(
                anchor="time-to-spend",
                heading="Festhalten, wie viel Zeit einzuplanen ist",
                kind=KIND_STEP,
                body="""Dieses Feld verhindert, dass ein Plan zur Fantasie wird. Vier Sehenswürdigkeiten an einem Nachmittag wirken als Liste vernünftig und werden unmöglich, sobald jede neunzig Minuten trägt.

Planen Sie die Zeit ein, die Sie dort wirklich verbringen wollen, nicht das Minimum, in dem es machbar wäre.""",
            ),
            Block(
                anchor="notes",
                heading="Eigene Notizen ergänzen",
                body="""Das Notizfeld ist freier Text — Buchungsnummern, was zu bestellen ist, welchen Eingang man nimmt, warum Sie diesen Ort dem nebenan vorgezogen haben.

Für eine Warnung, die schwer zu übersehen sein soll statt nebenbei gelesen zu werden, nehmen Sie stattdessen [eine Tipp- oder Vorsicht-Notiz](/help/travel-notes-and-warnings): die erscheinen als farbige Chips.""",
            ),
        ),
        keywords=(
            "stopp",
            "stopps",
            "ort",
            "orte",
            "hinzufügen",
            "budget",
            "preis",
            "dauer",
            "wie lange",
            "kategorie",
            "restaurant",
            "hotel",
            "museum",
        ),
        related=("plan-a-trip-itinerary", "add-locations-from-google-maps", "travel-notes-and-warnings"),
        updated="2026-09-01",
        cta="Legen Sie eine Reise an und fügen Sie den ersten Stopp hinzu.",
    ),
    Article(
        slug="add-locations-from-google-maps",
        title="So fügen Sie einen Ort aus einem Google-Maps-Link hinzu",
        summary="Maps-Link einfügen und Ntripi liest die Koordinaten heraus — oder setzen Sie den Punkt selbst auf der Karte.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Ein Stopp kann seine Position auf zwei Wegen bekommen: den Punkt auf Ntripis eigener Karte wählen, oder einen Google-Maps-Link einfügen und Ntripi die Koordinaten daraus lesen lassen. Das zweite ist meist schneller, weil Sie den Ort dort vermutlich schon gefunden haben.",
        blocks=(
            Block(
                anchor="paste-a-link",
                heading="Einen Google-Maps-Link einfügen",
                kind=KIND_STEP,
                body="""Wechseln Sie im Positionsfeld des Stopps auf die Link-Option und fügen Sie die URL ein. Ntripi liest die Koordinaten heraus und behält den Link, sodass der Stopp eine kleine Kartenvorschau zeigt und Sie den Ort später in Maps öffnen können.

Sowohl die lange Desktop-URL als auch der kurze Teilen-Link funktionieren. Nur Google-Maps-Adressen werden akzeptiert — ein Link auf etwas anderes wird abgelehnt, statt gespeichert und stillschweigend ignoriert zu werden.""",
            ),
            Block(
                anchor="pick-on-the-map",
                heading="Oder setzen Sie den Punkt selbst",
                kind=KIND_STEP,
                body="""Wechseln Sie auf Koordinaten und öffnen Sie die Kartenauswahl. Verschieben und zoomen Sie zur Stelle: Der Punkt in der Mitte wird gespeichert.

Das ist die bessere Wahl für einen Ort ohne Maps-Eintrag — ein Aussichtspunkt, ein Wanderweg-Einstieg, ein Strand ohne Namen.""",
            ),
            Block(
                anchor="locate-me",
                heading="Die Karte auf Ihren Standort zentrieren",
                kind=KIND_STEP,
                body="""Die Standort-Schaltfläche zentriert die Karte auf Ihre aktuelle Position und erspart es, quer über einen Kontinent zu scrollen, um die Stadt zu finden, in der Sie gerade stehen.

Beim ersten Mal wird die Standortberechtigung angefragt. **Ablehnen blockiert nichts** — die Karte öffnet sich einfach woanders und Sie verschieben sie selbst. Siehe [welche Berechtigungen Ntripi anfragt](/help/permissions).""",
            ),
            Block(
                anchor="opening-in-maps",
                heading="Einen Stopp in Ihrer Karten-App öffnen",
                body="""Ein Stopp mit Position bietet an, sich in der installierten Karten-App zu öffnen, damit Sie am Tag selbst die Route bekommen, ohne etwas abzutippen.

Die Karte von Ntripi dient zum Lesen des Plans; Ihre Karten-App dient dazu, ihn abzulaufen.""",
            ),
        ),
        keywords=(
            "google maps",
            "link",
            "einfügen",
            "koordinaten",
            "gps",
            "stecknadel",
            "position",
            "kartenauswahl",
            "breitengrad",
            "längengrad",
            "wo",
        ),
        related=("add-places-to-an-itinerary", "permissions"),
        updated="2026-09-01",
        cta="Setzen Sie Ihren ersten Stopp auf die Karte.",
    ),
    Article(
        slug="plan-transport-between-stops",
        title="So planen Sie den Transport zwischen Stopps",
        summary="Halten Sie fest, wie Sie von Ort zu Ort kommen — Verkehrsmittel, Dauer, Kosten und die Liniennummer.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Zwischen zwei beliebigen Stopps können Sie einen **Transportabschnitt** festhalten: wie Sie reisen, wie lange es dauert und was es kostet. Ein Abschnitt kann mehrere Teilstrecken haben, sodass eine Fahrt mit Bus und dann Zug eine Verbindung bleibt statt zweier unerklärter Lücken.",
        blocks=(
            Block(
                anchor="add-a-segment",
                heading="Eine Verbindung hinzufügen",
                kind=KIND_STEP,
                body="""Nutzen Sie zwischen zwei Stopps das Element zum Hinzufügen von Transport. Wählen Sie das Verkehrsmittel — zu Fuß, Fahrrad, Bus, Zug, U-Bahn, Taxi, Auto, Fähre, Flug — und geben Sie eine Dauer an.

Die Kosten gelten pro Person, in der Währung der Reise, und fließen neben den Stopps in die Gesamtsumme ein.""",
            ),
            Block(
                anchor="multiple-legs",
                heading="Mehr als eine Teilstrecke ergänzen",
                kind=KIND_STEP,
                body="""Eine Fahrt nutzt selten nur ein Fahrzeug. Legen Sie für jeden Abschnitt eine Teilstrecke an — der Weg zur Haltestelle, der Bus, der Umstieg, der Zug — und jede behält ihr eigenes Verkehrsmittel und ihre Dauer.

Die Verbindung zeigt dann die echte Tür-zu-Tür-Zeit, also die Zahl, die entscheidet, ob der Nachmittag aufgeht.""",
            ),
            Block(
                anchor="line-and-direction",
                heading="Linie und Fahrtrichtung festhalten",
                kind=KIND_STEP,
                body="""Jede Teilstrecke kann eine Linie tragen — `M4`, `Bus 12`, `RER B` — und eine Fahrtrichtung, also die Endstation, die vorn am Fahrzeug steht.

Die Richtung ist das Detail, auf das es am Tag selbst ankommt. Zu wissen, dass man die M4 will, hilft auf einem Bahnsteig nicht weiter, an dem Züge in beide Richtungen fahren.""",
            ),
            Block(
                anchor="orphaned-connections",
                heading="Warum das Einfügen eines Stopps warnen kann",
                body="""Eine Verbindung lebt *zwischen zwei Nachbarn*. Fügen Sie eine neue Spalte zwischen zwei ein, die bereits eine haben, hat diese Verbindung keinen Platz mehr.

Ntripi fragt vorher, statt Ihre Eingabe stillschweigend zu verwerfen. Bestätigen Sie, wird die betroffene Verbindung entfernt; brechen Sie ab, ändert sich nichts.""",
            ),
        ),
        keywords=(
            "transport",
            "verkehr",
            "bus",
            "zug",
            "u-bahn",
            "taxi",
            "zu fuß",
            "auto",
            "flug",
            "verbindung",
            "teilstrecke",
            "abschnitt",
            "wie komme ich hin",
        ),
        related=("add-places-to-an-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Zeichnen Sie eine Fahrt nach, samt Umstiegen.",
    ),
    Article(
        slug="travel-notes-and-warnings",
        title="So ergänzen Sie Reisewarnungen und Tipps",
        summary="Vier Notizarten — Tipp, Vorsicht, Vermeiden und Info — als farbige Chips, an denen niemand vorbeiscrollt.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Was auf einer Reise schiefgeht, steht selten im Reiseführer. Ntripi hat vier Notizarten — **Tipp**, **Vorsicht**, **Vermeiden** und **Info** — die an einem einzelnen Stopp oder an der ganzen Reise hängen und als farbige Chips erscheinen, sodass man ihnen begegnet, statt sie suchen zu müssen.",
        blocks=(
            Block(
                anchor="the-four-types",
                heading="Wofür jede Art da ist",
                body="""- **Tipp** — machen Sie das, dann läuft es besser. „Ticket online kaufen, die Schlange dauert eine Stunde.“
- **Vorsicht** — geht schon, aber passen Sie auf. „Abends viel los; Tasche nach vorn nehmen.“
- **Vermeiden** — lieber nicht. „Der Taxistand davor nimmt zu viel; zwei Straßen weitergehen und eines heranwinken.“
- **Info** — gut zu wissen, nichts zu tun. „Dienstags geschlossen.“

Die Art ändert nur Farbe und Beschriftung — wählen Sie also die, die eine fremde Person so liest, wie Sie es gemeint haben.""",
            ),
            Block(
                anchor="add-to-a-stop",
                heading="Eine Notiz an einen Stopp hängen",
                kind=KIND_STEP,
                body="""Öffnen Sie den Stopp und ergänzen Sie dort eine Notiz. Sie gehört zu diesem Ort und wandert mit, wenn Sie die Reise umsortieren.

Dorthin gehört alles zu einem bestimmten Eingang, einer Schlange, einer Öffnungszeit oder einer örtlichen Gefahr.""",
            ),
            Block(
                anchor="add-to-the-trip",
                heading="Eine Notiz an die ganze Reise hängen",
                kind=KIND_STEP,
                body="""Von der Route selbst aus gilt eine Notiz für die Reise als Ganzes — Visabestimmungen, die Jahreszeit, welche SIM-Karte funktioniert, was einzupacken ist.

Notizen auf Reiseebene stehen oben, vor den Stopps, weil man sie meist lesen muss, bevor man einen Tag plant.""",
            ),
            Block(
                anchor="notes-vs-notes",
                heading="Farbige Notizen und das Notizfeld",
                body="""Jeder Stopp hat außerdem ein einfaches **Notizfeld**. Nutzen Sie es für eigene Merkzettel — eine Buchungsnummer, was zu bestellen ist.

Nehmen Sie eine farbige Notiz für alles, worauf ein Leser *reagieren* muss. Der Unterschied liegt darin, ob es leicht zu übergehen sein soll.""",
            ),
        ),
        keywords=(
            "notiz",
            "notizen",
            "warnung",
            "warnungen",
            "tipp",
            "tipps",
            "hinweis",
            "vorsicht",
            "vermeiden",
            "info",
            "anmerkung",
            "sicherheit",
            "betrug",
        ),
        related=("add-places-to-an-itinerary", "plan-a-trip-itinerary"),
        updated="2026-09-01",
        cta="Schreiben Sie auf, was Ihnen jemand hätte sagen sollen.",
    ),
    Article(
        slug="trip-cover-photos",
        title="So fügen Sie Ihrer Reise ein Titelbild hinzu",
        summary="Ein Titelbild wählen, zuschneiden — und vorher wissen, was beim Hochladen abgelehnt wird.",
        category="building",
        intro="Das Titelbild ist das, was andere im Feed und in einem geteilten Link sehen — es leistet damit mehr als jedes andere einzelne Feld. Nur der **Eigentümer** der Reise kann es setzen: Wer zum Bearbeiten eingeladen wurde, darf den Inhalt ändern, nicht aber das öffentliche Gesicht der Reise.",
        blocks=(
            Block(
                anchor="add-a-cover",
                heading="Titelbild hinzufügen oder ändern",
                body="""Öffnen Sie den Bearbeitungsbildschirm der Reise und tippen Sie auf den Titelbildbereich. Ihre Fotomediathek öffnet sich; wählen Sie ein Bild und schneiden Sie es auf den Rahmen zu.

Der Zuschnitt ist breit, denn das ist das Format einer Linkvorschau. Ein hochformatiges Foto verliert oben und unten — wählen Sie also eines, dessen Motiv in der Mitte sitzt.""",
            ),
            Block(
                anchor="what-gets-refused",
                heading="Was abgelehnt wird, und warum",
                body="""Ein Bild kann aus drei Gründen abgelehnt werden:

- **Zu klein.** Unter 600 Pixeln an der kürzeren Seite wirkt es auf einem modernen Display unscharf.
- **Ein nicht unterstütztes Format.** JPEG, PNG und die üblichen Fotoformate sind in Ordnung.
- **Der Inhalt.** Uploads werden vor dem Speichern automatisch gegen die [Community-Richtlinien](/guidelines) geprüft.

Wenn Sie eine Ablehnung für falsch halten, [sagen Sie es uns](/help/contact).""",
            ),
            Block(
                anchor="what-we-strip",
                heading="Was Ntripi aus Ihrem Foto entfernt",
                body="""Bei jedem hochgeladenen Bild werden vor dem Speichern die **EXIF-Metadaten entfernt**. Das ist der Block verborgener Daten, den eine Kamera anhängt — vor allem die **GPS-Koordinaten des Aufnahmeortes**, dazu Gerätemodell und Zeitstempel.

Das geschieht unabhängig davon, ob die Reise öffentlich ist, und lässt sich nicht abschalten. Ein Foto Ihrer Straße sollte nicht Ihre Straße veröffentlichen.""",
            ),
            Block(
                anchor="no-cover",
                heading="Wenn Sie keines hinzufügen",
                body="""Eine Reise ohne Titelbild bekommt einen aus ihrer Route erzeugten Platzhalter und wirkt deshalb nie kaputt.

Vor dem öffentlichen Teilen lohnt sich trotzdem ein echtes: In einem Feed voller Fotografien ist der Platzhalter das, woran man vorbeiscrollt.""",
            ),
        ),
        keywords=(
            "titelbild",
            "foto",
            "bild",
            "hochladen",
            "zuschneiden",
            "banner",
            "vorschaubild",
            "abgelehnt",
            "zu klein",
        ),
        related=("plan-a-trip-itinerary", "share-a-trip-link"),
        updated="2026-09-01",
        cta="Geben Sie Ihrer Reise ein Gesicht.",
    ),
    Article(
        slug="plan-a-trip-with-friends",
        title="So planen Sie eine Reise gemeinsam mit anderen",
        summary="Andere zum Bearbeiten einladen — und verstehen, warum immer nur eine Person gleichzeitig schreiben kann.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Eine Reise hat einen Eigentümer und beliebig viele **Bearbeiter**. Ein Bearbeiter darf den Inhalt ändern — Stopps, Transport, Notizen, den Titel — aber nicht, wer sie sehen darf, nicht das Titelbild und nicht die Bearbeiterliste. Es bearbeitet immer nur eine Person, damit niemandes Arbeit überschrieben wird.",
        blocks=(
            Block(
                anchor="invite-an-editor",
                heading="Jemanden zum Bearbeiten einladen",
                kind=KIND_STEP,
                body="""Öffnen Sie den Bearbeitungsbildschirm der Reise und suchen Sie die Bearbeiterliste. Fügen Sie die Person über ihren Benutzernamen hinzu. Sie erhält eine Benachrichtigung, die die Reise benennt — und genau das lässt sie diese finden: Eine private Reise steht in keinem Feed und in keiner Suche.

Nur der **Eigentümer** kann Bearbeiter hinzufügen oder entfernen. Ein Bearbeiter kann keine weiteren gewinnen: Die Einladung ist Ihre Vertrauensentscheidung und bringt nicht das Recht mit, sie weiterzugeben.""",
            ),
            Block(
                anchor="cannot-see-it",
                heading="Wenn sie die Reise noch nicht sehen können",
                kind=KIND_STEP,
                body="""Bearbeiten setzt voraus, sie überhaupt sehen zu können. Laden Sie jemanden ein, der das nicht kann, fragt Ntripi, ob Sie ihm auch Zugriff geben wollen, statt einfach zu scheitern.

Ein Ja fügt die Person der Zugriffsliste dieser Reise hinzu, mehr nicht. Es erweitert nie die Sichtbarkeit der Reise: „Follower“ in „bestimmte Personen“ zu verwandeln, würde alle anderen stillschweigend ausschließen — das bleibt eine Entscheidung, die Sie bewusst treffen.""",
            ),
            Block(
                anchor="one-at-a-time",
                heading="Warum immer nur eine Person bearbeiten kann",
                body="""Wenn Sie eine Reise zum Bearbeiten öffnen, halten Sie sie. Alle anderen sehen **„jemand anderes bearbeitet gerade“** und können lesen, aber nicht speichern.

Die Alternative wäre, dass zwei Personen in denselben Stopp tippen und eine davon alles verliert, ohne es zu erfahren. Das Halten ist kurz: Es endet, wenn Sie gehen, und läuft von selbst ab, wenn Sie abgelenkt werden.""",
            ),
            Block(
                anchor="taking-over",
                heading="Von jemandem übernehmen",
                kind=KIND_STEP,
                body="""War die Reise eine Weile untätig, darf sie jeder übernehmen, der bearbeiten kann. Als Eigentümer können Sie sie immer zurückholen — auch von Ihrem eigenen zweiten Gerät, was der übliche Grund dafür ist, dass sie feststeckt.

Übernehmen ist immer ein bewusster zweiter Schritt, nie automatisch.""",
            ),
            Block(
                anchor="losing-the-lock",
                heading="Wenn jemand übernimmt, während Sie tippen",
                body="""Ein Hinweis erscheint und Speichern funktioniert nicht mehr. **Nichts von dem, was Sie getippt haben, geht verloren** — jedes Feld bleibt genau so, wie Sie es verlassen haben, und Sie können weiterhin daraus markieren und kopieren.

Holen Sie die Reise zurück und speichern Sie, oder kopieren Sie Ihren Text heraus und fügen Sie ihn ein, wenn die andere Person fertig ist. Ntripi schließt Ihnen weder den Bildschirm noch leert es ein Feld, denn in diesem Moment ist Ihr ungespeicherter Text die einzige Fassung davon.""",
            ),
            Block(
                anchor="finding-shared-trips",
                heading="Eine mit Ihnen geteilte Reise wiederfinden",
                body="Der Tab **Reiserouten** hat eine zweite Ansicht für Reisen, zu deren Bearbeitung Sie eingeladen wurden. Das ist der dauerhafte Weg zurück — die Benachrichtigung, die sie angekündigt hat, wird irgendwann entfernt, und eine private Reise erscheint in keinem Feed und in keiner Suche.",
            ),
        ),
        keywords=(
            "zusammenarbeiten",
            "gemeinsam",
            "zusammen",
            "geteilt",
            "bearbeiter",
            "einladen",
            "gruppe",
            "freunde",
            "familie",
            "mitbearbeiten",
            "jemand anderes bearbeitet",
            "sperre",
        ),
        related=("share-an-itinerary-privately", "plan-alternative-options", "troubleshooting"),
        updated="2026-09-01",
        cta="Planen Sie Ihre nächste Reise mit denen, die mitfahren.",
    ),
    Article(
        slug="share-an-itinerary-privately",
        title="So teilen Sie eine Reiseroute, ohne sie zu veröffentlichen",
        summary="Vier Sichtbarkeitsstufen entscheiden, wer eine Reise öffnen darf — vom ganzen Internet bis zu wenigen benannten Personen.",
        category="sharing",
        schema=SCHEMA_FAQ,
        intro="Jede Reise hat eine von vier Sichtbarkeitsstufen, und Sie können sie jederzeit ändern. Neue Reisen starten bei **Nur ich**. Um mit einer bestimmten Gruppe zu teilen, ohne zu veröffentlichen, nehmen Sie **bestimmte Personen** und fügen sie über den Benutzernamen hinzu.",
        blocks=(
            Block(
                anchor="the-four-levels",
                heading="Was sind die vier Sichtbarkeitsstufen?",
                kind=KIND_FAQ,
                body="""- **Öffentlich** — jeder kann sie öffnen, auch ohne Anmeldung. Sie kann im Feed erscheinen und über ihren Teilen-Link von Suchmaschinen gefunden werden.
- **Follower** — alle, die Ihnen folgen. Ist Ihr Konto privat, heißt das: nur die Follower, die Sie bestätigt haben.
- **Bestimmte Personen** — nur die Benutzernamen, die Sie hinzufügen. Niemand sonst, egal wie er an den Link gekommen ist.
- **Nur ich** — niemand außer Ihnen und denen, die Sie zu Bearbeitern gemacht haben.""",
            ),
            Block(
                anchor="share-with-a-few-people",
                heading="Wie teile ich nur mit wenigen Personen?",
                kind=KIND_FAQ,
                body="""Stellen Sie die Reise auf **bestimmte Personen** und fügen Sie sie über den Benutzernamen hinzu. Schicken Sie ihnen dann den Teilen-Link der Reise.

Der Link ist kein geheimes Passwort — er ist die Adresse der Reise. Der Zugriff wird bei jedem Öffnen gegen Ihre Liste geprüft, das Weiterleiten des Links an jemanden außerhalb der Liste bringt also nichts.""",
            ),
            Block(
                anchor="what-others-see",
                heading="Was sieht jemand ohne Zugriff?",
                kind=KIND_FAQ,
                body="""Eine Seite mit dem Hinweis, dass die Reise nicht verfügbar ist. Sie verrät nicht, dass die Reise existiert, wem sie gehört oder wie sie heißt — eine Reise, die Sie nicht sehen können, ist von einer nie erstellten nicht zu unterscheiden.

Dasselbe gilt für ein Profil, von dem Sie blockiert wurden.""",
            ),
            Block(
                anchor="change-later",
                heading="Kann ich die Sichtbarkeit später ändern?",
                kind=KIND_FAQ,
                body="""Ja, jederzeit und in beide Richtungen. Der Wechsel auf eine engere Stufe wirkt sofort — wer die Voraussetzungen nicht mehr erfüllt, kann sie nicht mehr öffnen.

Nur der Eigentümer der Reise kann die Sichtbarkeit ändern. Wen Sie zum Bearbeiten eingeladen haben, darf den Inhalt ändern, nicht aber, wer ihn sieht.""",
            ),
            Block(
                anchor="link-previews",
                heading="Was erscheint, wenn ich den Link irgendwo einfüge?",
                kind=KIND_FAQ,
                body="""Eine öffentliche Reise erzeugt eine Vorschaukarte mit Titelbild, Titel, Dauer, Kosten und Bewertung.

Eine nicht öffentliche Reise erzeugt keine Vorschau — die Vorschau würde den Titel an alle im Chat verraten, auch an die, die sie nicht öffnen können.""",
            ),
        ),
        keywords=(
            "privat",
            "nicht öffentlich",
            "sichtbarkeit",
            "wer kann sehen",
            "öffentlich",
            "follower",
            "eingeschränkt",
            "nur ich",
            "verbergen",
            "versteckt",
            "geheim",
            "link teilen",
            "berechtigungen",
            "nur freunde",
            "einladen",
        ),
        related=("plan-a-trip-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Planen Sie eine Reise und teilen Sie sie genau mit den Richtigen.",
    ),
    Article(
        slug="share-a-trip-link",
        title="So teilen Sie Ihre Reise als Link",
        summary="Eine Reise per Link an alle verschicken — und vorher wissen, was die Vorschaukarte zeigen wird.",
        category="sharing",
        intro="Jede Reise hat eine Webadresse. Teilen heißt einfach, sie zu verschicken — der Link ist der Ort der Reise, kein Passwort, und der Zugriff wird bei jedem Öffnen erneut gegen Ihre [Sichtbarkeitseinstellung](/help/share-an-itinerary-privately) geprüft.",
        blocks=(
            Block(
                anchor="get-the-link",
                heading="Den Link holen",
                body="""Öffnen Sie die Reise und nutzen Sie die Teilen-Aktion. Das übliche Teilen-Menü Ihres Geräts erscheint, der Link kann also in jede App gehen — Nachrichten, E-Mail, Notizen.

Die Seite öffnet sich im Browser, die Person, der Sie ihn schicken, braucht die App also nicht, um sie zu lesen.""",
            ),
            Block(
                anchor="what-the-preview-shows",
                heading="Was die Vorschaukarte zeigt",
                body="""Eine **öffentliche** Reise erzeugt in den meisten Messengern eine Vorschaukarte: Titelbild, Titel, Gesamtdauer und -kosten, die Zahl der Stopps und, falls vorhanden, die Bewertung.

Eine **nicht** öffentliche Reise erzeugt keine Vorschau. Das ist Absicht — eine Vorschau würde den Titel allen im Gruppenchat zeigen, auch denen, die sie nicht öffnen können.""",
            ),
            Block(
                anchor="what-they-see",
                heading="Was die lesende Person bekommt",
                body="""Die ganze Reise: die Stopps der Reihe nach, die parallelen Optionen, den Transport dazwischen, die Kosten, Ihre Notizen und Warnungen und die Bewertungen.

Alles davon ist ohne Konto lesbar. Speichern, bewerten oder Stopps daraus kopieren braucht eines.""",
            ),
            Block(
                anchor="unsharing",
                heading="Es zurücknehmen",
                body="""Ändern Sie die Sichtbarkeit der Reise, und der Link funktioniert sofort nicht mehr für alle, die die Voraussetzungen nicht mehr erfüllen. Sie müssen der verschickten Nachricht nicht hinterherlaufen.

Was Sie nicht rückgängig machen können, ist ein Screenshot — behandeln Sie Veröffentlichen also als Veröffentlichen.""",
            ),
        ),
        keywords=(
            "teilen",
            "link",
            "url",
            "senden",
            "whatsapp",
            "vorschau",
            "kopieren",
            "veröffentlichen",
            "öffentlich",
        ),
        related=("share-an-itinerary-privately", "trip-cover-photos"),
        updated="2026-09-01",
        cta="Bauen Sie etwas, das sich zu verschicken lohnt.",
    ),
    Article(
        slug="follow-and-private-accounts",
        title="Follower, Follow-Anfragen und private Konten",
        summary="Wie Folgen funktioniert, was ein privates Konto verbirgt und wie Sie eine Anfrage annehmen oder ablehnen.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Jemandem zu folgen bringt dessen öffentliche Reisen vor Ihre Augen und erlaubt es der Person, Reisen mit ihren Followern zu teilen. Ist Ihr Konto **privat**, wird ein Follow zu einer **Anfrage**, die Sie annehmen oder ablehnen.",
        blocks=(
            Block(
                anchor="how-to-follow",
                heading="Wie folge ich jemandem?",
                kind=KIND_FAQ,
                body="""Suchen Sie die Person im Tab **Suche** — dort wird nach Benutzernamen gesucht — und nutzen Sie Folgen in ihrem Profil.

Ist das Konto öffentlich, folgen Sie sofort. Ist es privat, wird die Schaltfläche zu **Angefragt**, bis die Person entscheidet.""",
            ),
            Block(
                anchor="what-private-hides",
                heading="Was verbirgt ein privates Konto?",
                kind=KIND_FAQ,
                body="""Reisen auf der Stufe **Follower** werden nur noch für die Follower sichtbar, die Sie tatsächlich bestätigt haben, statt für jeden, der auf Folgen getippt hat.

Reisen, die Sie auf **öffentlich** stellen, bleiben öffentlich — privat regelt, wer als Follower zählt, es ist kein Generalschloss. Wollen Sie alles verbergen, stellen Sie die Reisen selbst auf [Nur ich oder bestimmte Personen](/help/share-an-itinerary-privately).""",
            ),
            Block(
                anchor="handling-requests",
                heading="Wo nehme ich Anfragen an?",
                kind=KIND_FAQ,
                body="""Ein Hinweis in Ihrem Profil zeigt die Anzahl, und **Einstellungen ▸ Follow-Anfragen** listet sie auf. Nehmen Sie jede an oder lehnen Sie sie ab.

Eine Ablehnung wird nicht mitgeteilt. Die Anfrage ist einfach nicht mehr offen, und die Person kann erneut fragen.""",
            ),
            Block(
                anchor="going-public",
                heading="Was passiert, wenn ich von privat auf öffentlich wechsle?",
                kind=KIND_FAQ,
                body="""Jede offene Anfrage wird automatisch angenommen. Leute in einer Warteschlange hinter einem Tor stehen zu lassen, das Sie gerade entfernt haben, wäre eine Schlange, die nie wieder jemand angesehen hätte.

In die andere Richtung, von öffentlich auf privat, werden Ihre bestehenden Follower nicht entfernt.""",
            ),
            Block(
                anchor="unfollow-vs-block",
                heading="Was ist der Unterschied zwischen Entfolgen und Blockieren?",
                kind=KIND_FAQ,
                body="""**Entfolgen** sorgt nur dafür, dass die Reisen der Person nicht mehr in Ihrem Feed landen. Sie sieht weiterhin alles, was sie vorher sehen konnte.

**Blockieren** kappt die Sichtbarkeit in beide Richtungen, und die blockierte Person erfährt es nicht. Siehe [Melden und Blockieren](/help/report-and-block).""",
            ),
        ),
        keywords=(
            "folgen",
            "follower",
            "abonnenten",
            "anfrage",
            "privat",
            "öffentliches konto",
            "annehmen",
            "bestätigen",
            "entfolgen",
            "blockieren",
        ),
        related=("share-an-itinerary-privately", "report-and-block"),
        updated="2026-09-01",
        cta="Finden Sie die Leute, deren Reisen Sie klauen wollen.",
    ),
    Article(
        slug="rate-a-trip",
        title="Wie Bewertungen funktionieren: Sicherheit, Barrierefreiheit, Andrang und mehr",
        summary="Eine Gesamtnote plus fünf optionale Dimensionen — und warum Durchschnitte erst ab drei Bewertungen erscheinen.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Eine Bewertung besteht aus einer verpflichtenden **Gesamtnote** von fünf und bis zu fünf optionalen Dimensionen: Sicherheit, Erlebnis, Barrierefreiheit, Familienfreundlichkeit und Andrang. Dazu können Sie einen geschriebenen Kommentar hinterlassen.",
        blocks=(
            Block(
                anchor="the-dimensions",
                heading="Was bedeuten die fünf Dimensionen?",
                kind=KIND_FAQ,
                body="""- **Sicherheit** — wie sicher es sich angefühlt hat.
- **Erlebnis** — wie gut es tatsächlich war.
- **Barrierefreiheit** — wie gut es mit eingeschränkter Mobilität, Kinderwagen oder schwerem Gepäck funktioniert.
- **Familienfreundlich** — wie gut es mit Kindern funktioniert.
- **Andrang** — wie angenehm wenig los war.

Bei allen Dimensionen gilt **höher ist besser**, auch beim Andrang: Fünf heißt angenehm ruhig, eins heißt überlaufen. Alle sind optional — bewerten Sie nur, wozu Sie etwas sagen können.""",
            ),
            Block(
                anchor="three-ratings",
                heading="Warum sehe ich keinen Durchschnitt?",
                kind=KIND_FAQ,
                body="""Eine Dimension zeigt ihren Durchschnitt erst, wenn **drei** Personen sie bewertet haben.

Die Meinung einer einzelnen Person als Durchschnitt dargestellt liest sich wie eine Tatsache über den Ort statt wie eine Ansicht dazu, und bei zwei ist es kaum besser. Unter drei sehen Sie stattdessen die einzelnen Bewertungen.""",
            ),
            Block(
                anchor="who-can-rate",
                heading="Wer darf eine Reise bewerten?",
                kind=KIND_FAQ,
                body="""Jeder, der sie sehen kann und eine bestätigte E-Mail-Adresse hat, außer dem Eigentümer. Ihre eigene Bewertung können Sie jederzeit ändern — erneut bewerten ersetzt sie, statt eine zweite anzulegen.

Die E-Mail-Pflicht hält Wegwerfkonten aus den Noten heraus.""",
            ),
            Block(
                anchor="written-notes",
                heading="Kann ich eine Rezension schreiben, nicht nur eine Note?",
                kind=KIND_FAQ,
                body="""Ja — im Bewertungsdialog gibt es ein Kommentarfeld, und das ist der Teil, den andere Reisende wirklich lesen. Die Note sagt, wie es lief; der Kommentar sagt, warum.

Kommentare unterliegen wie alles Veröffentlichte den [Community-Richtlinien](/guidelines).""",
            ),
            Block(
                anchor="disagreeing",
                heading="Jemand hat meine Reise unfair bewertet",
                kind=KIND_FAQ,
                body="""Sie können eine Bewertung Ihrer eigenen Reise nicht entfernen, und genau das ist der Punkt: Eine Note, die der Autor löschen kann, ist für die nächste lesende Person nichts wert.

Verstößt eine Bewertung gegen die Richtlinien, statt Ihnen nur zu missfallen, [melden Sie sie](/help/report-and-block) — dann sieht sich das ein Mensch an.""",
            ),
        ),
        keywords=(
            "bewertung",
            "bewertungen",
            "bewerten",
            "rezension",
            "sterne",
            "note",
            "sicherheit",
            "barrierefreiheit",
            "familienfreundlich",
            "überfüllt",
            "andrang",
        ),
        related=("save-trips-and-find-new-ones", "report-and-block"),
        updated="2026-09-01",
        cta="Bewerten Sie eine Reise, die Sie wirklich gemacht haben.",
    ),
    Article(
        slug="save-trips-and-find-new-ones",
        title="So speichern Sie Reisen und entdecken neue",
        summary="Alles Bewahrenswerte mit einem Lesezeichen versehen — und den Unterschied zwischen Top und Neueste verstehen.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Der Tab **Feed** zeigt öffentliche Reisen von allen. Alles Bewahrenswerte wandert per Lesezeichen in den Tab **Gespeichert**, der nur Ihnen gehört — niemand erfährt, dass Sie seine Reise gespeichert haben.",
        blocks=(
            Block(
                anchor="saving",
                heading="Wie speichere ich eine Reise?",
                kind=KIND_FAQ,
                body="""Tippen Sie bei jeder sichtbaren Reise auf das Lesezeichen. Sie erscheint in Ihrem Tab **Gespeichert**, der ein eigenes Filterfeld bekommt, sobald die Liste wächst.

Bei Ihren eigenen Reisen wird das Lesezeichen nicht angezeigt — etwas zu speichern, das Sie selbst geschrieben haben, brächte nichts.""",
            ),
            Block(
                anchor="saved-changes",
                heading="Was, wenn eine gespeicherte Reise sich ändert oder verschwindet?",
                kind=KIND_FAQ,
                body="""Sie sehen immer die aktuelle Fassung, nicht die, die Sie gespeichert haben.

Schränkt der Autor die Sichtbarkeit ein oder löscht die Reise, verschwindet sie aus Ihrem Tab „Gespeichert“. Ein Lesezeichen ist ein Verweis, keine Kopie — der Autor behält die Kontrolle über seine eigene Arbeit.""",
            ),
            Block(
                anchor="top-vs-recent",
                heading="Was ist der Unterschied zwischen Top und Neueste?",
                kind=KIND_FAQ,
                body="""**Neueste** ist alles Öffentliche, das Neueste zuerst. **Top** ist nach Bewertung sortiert, und eine Reise braucht einige Bewertungen, bevor sie dort überhaupt erscheinen kann.

In Neueste finden Sie neue Arbeit; in Top finden Sie Arbeit, für die andere sich verbürgt haben.""",
            ),
            Block(
                anchor="not-in-top",
                heading="Warum ist meine Reise nicht in Top?",
                kind=KIND_FAQ,
                body="""Sie muss öffentlich sein und braucht genügend Bewertungen. Eine Reise mit einer einzigen Bestnote belegt nichts, deshalb wartet der Top-Feed auf einige mehr.

Teilen Sie sie per [Link](/help/share-a-trip-link) mit denen, die dort waren — so kommen die ersten Bewertungen herein.""",
            ),
            Block(
                anchor="finding-people",
                heading="Wie finde ich eine bestimmte Person?",
                kind=KIND_FAQ,
                body="""Der Tab **Suche** durchsucht Benutzernamen, keine Reisen. Reisen findet man über den Feed, über einen zugeschickten Link oder über ein Profil, sobald Sie die Person gefunden haben.

Eine private Reise steht bewusst in keinem Feed und in keiner Suche; der einzige Weg dorthin ist eine Einladung oder ein Link von jemandem, der sie sehen kann.""",
            ),
        ),
        keywords=(
            "speichern",
            "gespeichert",
            "lesezeichen",
            "favorit",
            "favoriten",
            "feed",
            "entdecken",
            "erkunden",
            "top",
            "neueste",
            "trend",
            "stöbern",
        ),
        related=("rate-a-trip", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="Finden Sie eine Reise, die es zu klauen lohnt.",
    ),
    Article(
        slug="notifications",
        title="So steuern Sie, welche Benachrichtigungen Ntripi sendet",
        summary="Die acht Dinge, über die Ntripi informiert, welche drei abschaltbar sind und warum der Rest aktiv bleibt.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Die Glocke neben dem Zahnrad in Ihrem Profil ist die ganze Liste. Drei Arten von Benachrichtigungen lassen sich unter **Einstellungen ▸ Benachrichtigungen** abschalten; der Rest bleibt an, weil man auf Ungesehenes nicht rechtzeitig reagieren kann.",
        blocks=(
            Block(
                anchor="what-you-get",
                heading="Worüber informiert mich Ntripi?",
                kind=KIND_FAQ,
                body="""- Jemand hat angefragt, Ihnen zu folgen, oder folgt Ihnen jetzt
- Jemand hat Ihre Follow-Anfrage angenommen *(optional)*
- Jemand hat eine Ihrer Reisen bewertet *(optional)*
- Jemand hat eine Ihrer Reisen gespeichert *(optional)*
- Sie wurden zum Bearbeiten einer Reise eingeladen
- Ihnen wurde Zugriff auf eine Reise gegeben
- Eine Moderationsentscheidung betrifft Ihren Inhalt oder Ihr Konto

Sonst nichts. Kein Marketing, keine Rückhol-Erinnerungen, keine Zusammenfassungen.""",
            ),
            Block(
                anchor="switching-off",
                heading="Wie schalte ich einige ab?",
                kind=KIND_FAQ,
                body="""**Einstellungen ▸ Benachrichtigungen** hat drei Schalter: Bewertungen, Speicherungen und angenommene Follow-Anfragen. Einen davon abzuschalten verhindert, dass die Benachrichtigung überhaupt entsteht — sie wird nicht bloß versteckt.

Um alles stummzuschalten, deaktivieren Sie Ntripis Benachrichtigungen in den Einstellungen Ihres Telefons — siehe [Berechtigungen](/help/permissions).""",
            ),
            Block(
                anchor="always-on",
                heading="Warum kann ich die anderen nicht abschalten?",
                kind=KIND_FAQ,
                body="""Follow-Anfragen, Zugriffsfreigaben und Moderationsentscheidungen brauchen alle innerhalb eines sinnvollen Zeitfensters eine Antwort von Ihnen.

Eine Follow-Anfrage, die niemand sieht, wird nie beantwortet. Eine mit Ihnen geteilte Reise steht in keinem Feed und in keiner Suche — ein Hinweis, den Sie nicht bekommen haben, ist also ein Zugriff, von dem Sie nie erfahren haben. Und eine Moderationsentscheidung hat eine Einspruchsfrist: Schweigen dort würde Sie den Einspruch kosten.""",
            ),
            Block(
                anchor="arrival",
                heading="Warum kommen manche verspätet an?",
                kind=KIND_FAQ,
                body="""Push-Zustellung ist überall nur ein Bestversuch: Akkuverwaltungen stoppen Hintergrundprozesse, Telefone drosseln, Verbindungen brechen ab.

Deshalb prüft Ntripi im geöffneten Zustand auch selbst etwa einmal pro Minute, damit die Glocke stimmt, auch wenn nie ein Push ankam. Ist Push aus oder abgelehnt, ist diese Prüfung der einzige Kanal — und sie funktioniert weiterhin.""",
            ),
            Block(
                anchor="clearing",
                heading="Kann ich Benachrichtigungen löschen?",
                kind=KIND_FAQ,
                body="""Ja, einzeln oder alle auf einmal, mit ein paar Sekunden zum Rückgängigmachen, bevor es endgültig ist.

Einen Moderationshinweis zu löschen löscht nicht die Entscheidung — die bleibt unter **Einstellungen ▸ Kontostatus**, samt Einspruchsschaltfläche. Gelesene Benachrichtigungen werden nach neunzig Tagen entfernt; ungelesene bleiben länger, weil sie Ihr einziger Beleg dafür sind, dass etwas geschehen ist.""",
            ),
        ),
        keywords=(
            "benachrichtigung",
            "benachrichtigungen",
            "push",
            "hinweise",
            "glocke",
            "zähler",
            "stummschalten",
            "abschalten",
            "e-mail",
            "ruhe",
        ),
        related=("permissions", "follow-and-private-accounts"),
        updated="2026-09-01",
        cta="Bleiben Sie bei Ihren Reisen, ohne den Lärm.",
    ),
    Article(
        slug="app-settings",
        title="Sprache, dunkler Modus, Töne und Vibration",
        summary="Jeder Schalter hinter dem Zahnrad in Ihrem Profil und was er verändert.",
        category="account",
        intro="Das Zahnrad in Ihrem eigenen Profil öffnet alles. Einstellungen liegen auf Ihrem Gerät, gelten also pro Installation: Das Design auf Ihrem Telefon zu ändern, ändert es nicht auf Ihrem Tablet.",
        blocks=(
            Block(
                anchor="language",
                heading="Sprache",
                body="""Ntripi gibt es auf Englisch, Französisch, Arabisch, Deutsch, Spanisch und Chinesisch. Die App folgt der Sprache Ihres Geräts, wenn es eine der sechs ist, und hier können Sie das überstimmen.

Arabisch stellt die gesamte Oberfläche auf rechts-nach-links um. Die Wahl gilt auch für die Rechtsdokumente und für diesen Hilfebereich, wenn Sie ihn aus der App heraus öffnen.""",
            ),
            Block(
                anchor="theme",
                heading="Design",
                body="""System, Hell oder Dunkel. **System** folgt Ihrem Telefon, einschließlich seines automatischen Tag-Nacht-Wechsels, und ist die Voreinstellung.

Der dunkle Modus ist ein echtes Schwarz, kein Grau — gut zu wissen, wenn Sie Pläne im Bett lesen.""",
            ),
            Block(
                anchor="sounds-and-haptics",
                heading="Toneffekte und Vibration",
                body="""Zwei unabhängige Schalter. **Toneffekte** sind die kleinen Signale — eine eintreffende Benachrichtigung, eine abgegebene Bewertung. **Vibration** sind die spürbaren Impulse, darunter ein kurzes Brummen pro Stern beim Bewerten.

Jeder bestätigt sich selbst mit der gerade gewählten Einstellung, damit Sie hören oder spüren, was Sie einschalten.""",
            ),
            Block(
                anchor="shake-to-report",
                heading="Schütteln zum Melden",
                body="""Auf Telefonen standardmäßig an: Schütteln nimmt den Bildschirm auf und öffnet eine Fehlermeldung. Wenn Sie beim Lesen viel gestikulieren, schalten Sie es hier ab — **Einstellungen ▸ Support ▸ Schütteln zum Melden**.

Es ist bewusst schwer versehentlich auszulösen: Es verlangt zwei deutliche Schüttelbewegungen, ignoriert Sie, solange die App nicht im Vordergrund ist, und wartet einige Sekunden bis zur nächsten Auslösung.""",
            ),
            Block(
                anchor="account-rows",
                heading="Der Rest des Menüs",
                body="""- **Kontostatus** — Moderationsentscheidungen und Einsprüche
- **Blockierte Konten** — alle, die Sie blockiert haben, mit einem Tipp zum Aufheben
- **Follow-Anfragen** — nur sichtbar, wenn Ihr Konto privat ist
- **Hilfebereich** und **Über** — einschließlich dieser Website

Passwort ändern oder Konto löschen finden Sie im Bearbeitungsbildschirm Ihres Profils unter Sicherheit.""",
            ),
        ),
        keywords=(
            "einstellungen",
            "sprache",
            "übersetzen",
            "dunkler modus",
            "heller modus",
            "design",
            "ton",
            "töne",
            "vibration",
            "haptik",
            "voreinstellungen",
        ),
        related=("app-map", "notifications", "permissions"),
        updated="2026-09-01",
        cta="Machen Sie die App zu Ihrer.",
    ),
    Article(
        slug="permissions",
        title="Welche Berechtigungen Ntripi anfragt, und warum",
        summary="Standort, Benachrichtigungen, Fotos und Bewegung — wofür jede da ist, wann gefragt wird und wie Sie es später ändern.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi fragt vier Dinge an, jedes in dem Moment, in dem es zum ersten Mal nützlich ist, und nicht beim Start. **Kamera, Kontakte, Mikrofon und Standort im Hintergrund werden nie angefragt.** Jede Ablehnung lässt die App funktionsfähig.",
        blocks=(
            Block(
                anchor="location",
                heading="Standort — wofür?",
                kind=KIND_FAQ,
                body="""Um die Karte beim Anlegen eines Stopps auf Ihren Standort zu zentrieren, damit Sie nicht quer über einen Kontinent scrollen, um die Stadt zu finden, in der Sie stehen.

Gefragt wird beim ersten Nutzen der Standort-Schaltfläche der Karte, und **nur während Sie die App benutzen** — es gibt keinen Hintergrundstandort und kein Tracking. Ablehnen blockiert nichts: Die Karte öffnet sich woanders und Sie verschieben sie selbst.""",
            ),
            Block(
                anchor="notifications",
                heading="Benachrichtigungen — warum, und warum nur einmal?",
                kind=KIND_FAQ,
                body="""Um Sie über Follow-Anfragen, Bewertungen, Speicherungen und Moderationsentscheidungen zu informieren.

Gefragt wird beim ersten Öffnen des **Benachrichtigungsbildschirms** — also genau dann, wenn Sie gerade gezeigt haben, dass Sie sie wollen. iOS erlaubt einer App genau eine Abfrage pro Installation; beim Start zu fragen, vor einer App, die Sie noch nicht gesehen haben, würde diese eine Chance an eine fremde Anwendung verschenken.""",
            ),
            Block(
                anchor="photos",
                heading="Fotos — was sieht Ntripi?",
                kind=KIND_FAQ,
                body="""Nur das Bild, das Sie auswählen. Ntripi öffnet die Fotoauswahl Ihres Systems, die genau eine Datei zurückgibt und sonst nichts — die App hat keinen Blick auf Ihre Mediathek.

Bei jedem Upload werden die **EXIF-Metadaten entfernt**, einschließlich der GPS-Koordinaten des Aufnahmeortes. Siehe [Titelbilder](/help/trip-cover-photos).""",
            ),
            Block(
                anchor="motion",
                heading="Bewegung und Vibration — wofür?",
                kind=KIND_FAQ,
                body="""Das Schütteln des Telefons legt eine Fehlermeldung an, und das Telefon brummt kurz, um Dinge wie eine abgegebene Bewertung zu bestätigen.

Beides lässt sich in den **Einstellungen** abschalten: **Schütteln zum Melden** und **Vibration**. Nichts über Ihre Bewegung verlässt das Gerät.""",
            ),
            Block(
                anchor="never-asked",
                heading="Was Ntripi nie anfragt",
                kind=KIND_FAQ,
                body="""Die **Kamera**, Ihre **Kontakte**, Ihr **Mikrofon** und den **Standort im Hintergrund**. Nichts davon kommt in der App vor, und nichts davon ist in den ausgelieferten Builds deklariert.

Sollte irgendetwas behaupten, Ntripi frage eines davon an, sind wir das nicht — [sagen Sie es uns](/help/contact).""",
            ),
            Block(
                anchor="changing-your-mind",
                heading="Wie ändere ich eine Berechtigung später?",
                kind=KIND_FAQ,
                body="""Berechtigungen gehören Ihrem Betriebssystem, nicht Ntripi, also werden sie dort geändert:

- **iPhone oder iPad** — Einstellungen ▸ zu Ntripi scrollen ▸ Standort oder Mitteilungen umschalten.
- **Android** — Einstellungen ▸ Apps ▸ Ntripi ▸ Berechtigungen.

Am wichtigsten ist das bei Benachrichtigungen, für die iOS nicht erneut fragt: einmal abgelehnt, führt nur die Einstellungen-App zurück.""",
            ),
        ),
        keywords=(
            "berechtigung",
            "berechtigungen",
            "zugriff",
            "datenschutz",
            "standort",
            "gps",
            "kamera",
            "fotos",
            "benachrichtigungen",
            "mikrofon",
            "kontakte",
            "tracking",
            "erlauben",
            "ablehnen",
        ),
        related=("your-data-and-privacy", "notifications", "add-locations-from-google-maps"),
        updated="2026-09-01",
        cta="Sehen Sie genau, was die App anfragt — und was nicht.",
    ),
    Article(
        slug="your-data-and-privacy",
        title="Welche Daten Ntripi speichert, und wie Sie sie löschen",
        summary="In klarer Sprache: was gespeichert wird, wer es sehen kann und wie Sie Ihr Konto endgültig entfernen.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi speichert, was Sie schreiben und hochladen, sowie das, was zur Anmeldung nötig ist. Es gibt keine Werbung, kein Werbe-Tracking durch Dritte, und nichts wird verkauft. Maßgeblich ist die [Datenschutzerklärung](/privacy); dies ist die Kurzfassung.",
        blocks=(
            Block(
                anchor="what-is-stored",
                heading="Was speichert Ntripi über mich?",
                kind=KIND_FAQ,
                body="""- **Ihr Konto** — Anzeigename, Benutzername, E-Mail-Adresse und Geburtsdatum (wird niemandem gezeigt).
- **Was Sie erstellen** — Reisen, Stopps, Notizen, Bewertungen und alle hochgeladenen Bilder.
- **Ihre Verbindungen** — wem Sie folgen, wer Ihnen folgt, wen Sie blockiert haben.
- **Sitzungsdaten** — genug, um Sie angemeldet zu halten, und ein Gerätetoken, falls Sie Push aktiviert haben.

Bei hochgeladenen Bildern werden die EXIF-Metadaten entfernt, einschließlich der GPS-Koordinaten des Aufnahmeortes.""",
            ),
            Block(
                anchor="who-sees-it",
                heading="Wer kann sehen, was ich schreibe?",
                kind=KIND_FAQ,
                body="""Wer auch immer Ihre [Sichtbarkeitseinstellung](/help/share-an-itinerary-privately) benennt, und sonst niemand. Eine Reise auf **Nur ich** sehen Sie und alle, die Sie zum Bearbeiten eingeladen haben.

Ihr Geburtsdatum ist für andere Nutzer nie sichtbar, bei keiner Einstellung. Ihre E-Mail-Adresse erscheint nicht in Ihrem Profil.""",
            ),
            Block(
                anchor="moderation",
                heading="Liest jemand bei Ntripi meine Reisen?",
                kind=KIND_FAQ,
                body="""Nicht routinemäßig. Texte und Bilder werden beim Veröffentlichen automatisch geprüft, und ein Mensch sieht sich nur etwas an, wenn es gemeldet oder von diesen Prüfungen markiert wurde.

Automatische Prüfungen senden den Inhalt und sonst nichts — keine Nutzerkennung, keine E-Mail-Adresse, keinen Namen.""",
            ),
            Block(
                anchor="deleting",
                heading="Wie lösche ich mein Konto?",
                kind=KIND_FAQ,
                body="""Im Bearbeitungsbildschirm Ihres Profils unter Sicherheit ▸ **Konto löschen**. Sie bestätigen mit Ihrem Passwort oder mit Google, falls Sie sich so anmelden.

Die Löschung ist endgültig und nimmt Ihre Reisen mit. Von anderen gespeicherte Reisen funktionieren dann nicht mehr, denn ein Lesezeichen ist ein Verweis und keine Kopie.""",
            ),
            Block(
                anchor="requests",
                heading="Wie fordere ich eine Kopie meiner Daten an?",
                kind=KIND_FAQ,
                body="""Schreiben Sie an **[privacy@ntripi.app](mailto:privacy@ntripi.app)**. Diese Adresse ist der in der [Datenschutzerklärung](/privacy) genannte Datenschutzkontakt und erreicht die Personen, die einen Antrag tatsächlich bearbeiten können.

Dieselbe Adresse deckt Anträge auf Berichtigung, Einschränkung und Widerspruch ab.""",
            ),
        ),
        keywords=(
            "datenschutz",
            "daten",
            "dsgvo",
            "konto löschen",
            "entfernen",
            "exportieren",
            "personenbezogene daten",
            "tracking",
            "werbung",
            "anzeigen",
            "wer kann sehen",
        ),
        related=("permissions", "sign-in-and-account-security", "share-an-itinerary-privately"),
        updated="2026-09-01",
    ),
    Article(
        slug="sign-in-and-account-security",
        title="Anmelden, Passwörter und Konto löschen",
        summary="Anmeldung per E-Mail, Google oder Apple, Passwort zurücksetzen, wozu eine bestätigte Adresse nötig ist und wie Sie gehen.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Sie können sich mit E-Mail-Adresse und Passwort, mit Google oder mit Apple anmelden. Alle drei führen zum selben Konto, und einem mit Google erstellten Konto können Sie später ein Passwort hinzufügen.",
        blocks=(
            Block(
                anchor="forgot-password",
                heading="Ich habe mein Passwort vergessen",
                kind=KIND_FAQ,
                body="""Nutzen Sie **Passwort vergessen** im Anmeldebildschirm. Ein Link zum Zurücksetzen kommt per E-Mail und gilt für kurze Zeit.

Kommt nichts an, prüfen Sie den Spam-Ordner und ob Sie die Adresse verwenden, mit der Sie sich registriert haben. Haben Sie sich mit Google registriert, haben Sie womöglich gar kein Passwort — melden Sie sich dann mit Google an.""",
            ),
            Block(
                anchor="verify-email",
                heading="Warum kann ich keine Reise anlegen, bewerten oder folgen?",
                kind=KIND_FAQ,
                body="""Diese drei brauchen eine bestätigte E-Mail-Adresse. Suchen Sie den Bestätigungslink in Ihrem Posteingang, oder senden Sie über den Hinweis in Ihrem Profil einen neuen.

Die Anmeldung mit Google unter derselben Adresse bestätigt sie ebenfalls. Diese Anforderung hält Wegwerfkonten aus den Bewertungen und aus den Followerlisten heraus.""",
            ),
            Block(
                anchor="changing-password",
                heading="Wie ändere ich mein Passwort?",
                kind=KIND_FAQ,
                body="""Profil ▸ bearbeiten ▸ **Sicherheit ▸ Passwort ändern**. Sie bestätigen mit dem aktuellen.

Die Änderung meldet alle **anderen** Sitzungen ab und behält die, die Sie gerade nutzen — wenn Sie es also ändern, weil Sie einen Fremdzugriff vermuten, entfernt schon das allein den Zugriff.""",
            ),
            Block(
                anchor="age",
                heading="Warum fragt Ntripi nach meinem Geburtsdatum?",
                kind=KIND_FAQ,
                body="""Ntripi hat ein Mindestalter von **16 Jahren**, und die [Nutzungsbedingungen](/terms) sagen das — also muss danach gefragt und darf es nicht angenommen werden.

Es erscheint nie in Ihrem Profil und ist für andere Nutzer nie sichtbar. Es wird einmal gefragt und danach nicht wieder.""",
            ),
            Block(
                anchor="suspended",
                heading="Mein Konto ist gesperrt",
                kind=KIND_FAQ,
                body="""Sie haben eine E-Mail mit der Begründung und einem Link zum Einspruch erhalten. Einsprüche werden von einem Menschen gelesen.

Haben Sie die E-Mail nicht mehr, kann das Einspruchsformular Ihnen einen neuen Link schicken. Siehe [ausgeblendete Inhalte und Einsprüche](/help/hidden-content-and-appeals).""",
            ),
            Block(
                anchor="deleting",
                heading="Wie lösche ich mein Konto?",
                kind=KIND_FAQ,
                body="""Profil ▸ bearbeiten ▸ **Sicherheit ▸ Konto löschen**, bestätigt mit Ihrem Passwort oder mit Google.

Es ist endgültig und nimmt Ihre Reisen mit. Wollen Sie nur aus der Sichtbarkeit verschwinden, ist es umkehrbar, Ihre Reisen auf [Nur ich](/help/share-an-itinerary-privately) zu stellen und Ihr Konto privat zu machen — eine Löschung ist es nicht.""",
            ),
        ),
        keywords=(
            "anmeldung",
            "einloggen",
            "passwort",
            "passwort vergessen",
            "zurücksetzen",
            "google",
            "apple",
            "bestätigen",
            "verifizierung",
            "e-mail",
            "ausgesperrt",
            "konto löschen",
            "alter",
            "16",
        ),
        related=("your-data-and-privacy", "troubleshooting"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-and-block",
        title="So melden Sie Inhalte oder blockieren jemanden",
        summary="Eine Reise, Rezension oder ein Profil melden, das gegen die Regeln verstößt — und jemanden abschneiden, mit dem Sie nichts zu tun haben wollen.",
        category="safety",
        schema=SCHEMA_HOWTO,
        intro="Melden schickt etwas an die Moderation; Blockieren entfernt eine Person aus Ihrer Nutzung. Das sind zwei verschiedene Werkzeuge, und Sie können beide nutzen. Keines davon verrät der anderen Person, was Sie getan haben.",
        blocks=(
            Block(
                anchor="report",
                heading="Eine Reise, Rezension oder ein Profil melden",
                kind=KIND_STEP,
                body="""Nutzen Sie die Fahnen-Aktion am Element selbst — an einer Reise, einem Stopp, einer Rezension, einer Notiz oder einem Profil. Wählen Sie einen Grund und ergänzen Sie, was hilft.

Eine Meldung vom Element aus trägt den Kontext mit sich, deshalb ist sie besser, als uns eine Beschreibung zu mailen. Zum Melden von einer öffentlichen Teilen-Seite brauchen Sie kein Konto.""",
            ),
            Block(
                anchor="reasons",
                heading="Einen Grund wählen",
                body="""Die Gründe sind: Darstellungen sexuellen Kindesmissbrauchs, sexuelle Inhalte, Gewalt oder Drohungen, Hassrede, Belästigung, Spam und Sonstiges.

Wählen Sie den nächstliegenden — er entscheidet, wie dringend die Meldung behandelt wird. **Alles, was ein Kind betrifft, hat höchste Priorität** und geht in eine eigene Warteschlange.""",
            ),
            Block(
                anchor="what-happens",
                heading="Was passiert nach einer Meldung?",
                body="""Sie kommt in die Moderationswarteschlange. Von mehreren verschiedenen Personen gemeldete oder durch die automatischen Prüfungen bestätigte Inhalte können sofort ausgeblendet werden, während ein Mensch sie prüft.

Dem Autor wird nie gesagt, wer ihn gemeldet hat. Eine Antwort erhalten Sie in der Regel nicht — das Ergebnis ist, dass der Inhalt bleibt oder geht.""",
            ),
            Block(
                anchor="block",
                heading="Jemanden blockieren",
                kind=KIND_STEP,
                body="""Über das Profil der Person oder durch langes Drücken auf etwas, das sie veröffentlicht hat.

Blockieren kappt die Sichtbarkeit **in beide Richtungen**: Sie sehen die Person nicht mehr und sie Sie nicht. Ein bestehendes Follow zwischen Ihnen wird entfernt. Die Person erfährt es nicht, und Ihr Profil ist für sie von einem nie existierenden nicht zu unterscheiden.""",
            ),
            Block(
                anchor="unblock",
                heading="Jemanden entblocken",
                kind=KIND_STEP,
                body="""**Einstellungen ▸ Blockierte Konten** listet alle, die Sie blockiert haben, mit einem Tipp zum Rückgängigmachen.

Das Entblocken stellt das durch die Blockierung entfernte Follow nicht wieder her — beide Seiten können bei Bedarf erneut folgen.""",
            ),
            Block(
                anchor="urgent",
                heading="Wenn jemand in Gefahr ist",
                body="""Wenden Sie sich zuerst an Ihren örtlichen Notruf. Ntripi kann niemanden schnell genug erreichen, um der richtige erste Anruf zu sein.

Schreiben Sie danach an **[abuse@ntripi.app](mailto:abuse@ntripi.app)**, das genau dafür überwacht wird.""",
            ),
        ),
        keywords=(
            "melden",
            "meldung",
            "markieren",
            "blockieren",
            "missbrauch",
            "belästigung",
            "spam",
            "unsicher",
            "unangemessen",
            "entblocken",
            "sicherheit",
        ),
        related=("hidden-content-and-appeals", "follow-and-private-accounts", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="hidden-content-and-appeals",
        title="Warum Ihr Inhalt ausgeblendet wurde, und wie Sie Einspruch erheben",
        summary="Was es heißt, wenn eine Reise oder Rezension ausgeblendet ist, wo der Grund steht und wie ein Mensch noch einmal draufschaut.",
        category="safety",
        schema=SCHEMA_FAQ,
        intro="Wurde etwas von Ihnen Veröffentlichtes ausgeblendet, bekommen Sie eine Benachrichtigung samt Grund, und **Einstellungen ▸ Kontostatus** führt das Protokoll. Gegen die meisten Entscheidungen ist ein Einspruch möglich, und ein Einspruch wird von einem Menschen gelesen.",
        blocks=(
            Block(
                anchor="what-hidden-means",
                heading="Was heißt ausgeblendet?",
                kind=KIND_FAQ,
                body="""Niemand sonst kann es öffnen. **Sie schon** — es bleibt in Ihrer Liste, mit einem Hinweis auf den Grund, und nichts wird gelöscht, solange ein Einspruch möglich ist.

Ausblenden ist umkehrbar, wie es Löschen nicht ist — deshalb ist es der erste Schritt und nicht der letzte.""",
            ),
            Block(
                anchor="why",
                heading="Warum wurde meiner ausgeblendet?",
                kind=KIND_FAQ,
                body="""Entweder haben ihn genügend verschiedene Personen gemeldet, oder eine automatische Prüfung hat ihn markiert, oder ein Moderator hat entschieden, dass er gegen die [Community-Richtlinien](/guidelines) verstößt.

Der Grund steht im Hinweis und unter **Einstellungen ▸ Kontostatus**. Manche Ausblendungen sind vorläufig — automatisch verhängt, bis ein Mensch dazu kommt — und genau deshalb sind sie anfechtbar.""",
            ),
            Block(
                anchor="appealing",
                heading="Wie erhebe ich Einspruch?",
                kind=KIND_FAQ,
                body="""**Einstellungen ▸ Kontostatus** listet jede Entscheidung mit einer Einspruchsschaltfläche. Erklären Sie mit eigenen Worten, warum Sie sie für falsch halten.

Ein offener Einspruch je Entscheidung, und ein Versuch je Entscheidung innerhalb eines Monats — die Grenze sorgt dafür, dass die Warteschlange kurz genug bleibt, damit Einsprüche wirklich gelesen werden.""",
            ),
            Block(
                anchor="warnings",
                heading="Ich habe eine Verwarnung bekommen, aber nichts wurde ausgeblendet",
                kind=KIND_FAQ,
                body="""Eine Verwarnung ist ein Vermerk an Ihrem Konto, ohne dass etwas entfernt wird. Sie ist ein Signal und zugleich ein Protokolleintrag: Eine zweite Verwarnung wird als zweite erfasst und nicht mit der ersten verschmolzen.

Gegen Verwarnungen kann wie gegen alles andere Einspruch erhoben werden.""",
            ),
            Block(
                anchor="suspended",
                heading="Mein ganzes Konto ist gesperrt",
                kind=KIND_FAQ,
                body="""Sie können sich nicht anmelden, der Einspruch kann also nicht in der App liegen. Die Sperr-E-Mail enthält einen Link zu einem Webformular; haben Sie sie nicht mehr, kann das Formular einen neuen Link an Ihre Adresse schicken.

Sperren sind umkehrbar, und ein erfolgreicher Einspruch stellt das Konto wieder her, statt es neu aufzubauen.""",
            ),
            Block(
                anchor="after",
                heading="Was passiert nach meinem Einspruch?",
                kind=KIND_FAQ,
                body="""Ein Mensch liest ihn und stellt entweder den Inhalt wieder her oder lässt die Entscheidung bestehen, und Sie erfahren, welches von beidem.

Wird eine Entscheidung aufgehoben, kommt der Inhalt so zurück, wie er war — in der Zwischenzeit wurde nichts gelöscht.""",
            ),
        ),
        keywords=(
            "ausgeblendet",
            "versteckt",
            "entfernt",
            "löschung",
            "moderation",
            "einspruch",
            "widerspruch",
            "gesperrt",
            "verwarnung",
            "blockierter inhalt",
            "wiederhergestellt",
        ),
        related=("report-and-block", "sign-in-and-account-security", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="troubleshooting",
        title="Ntripi funktioniert nicht: häufige Probleme und Lösungen",
        summary="Die Meldungen, die am häufigsten auftauchen, was jede wirklich bedeutet und was als Nächstes zu tun ist.",
        category="troubleshooting",
        schema=SCHEMA_FAQ,
        intro="Die meisten Probleme in Ntripi kommen von dreierlei: zwei Personen bearbeiten dieselbe Reise, die Verbindung ist weg, oder ein Schritt beim Konto ist noch offen. Suchen Sie unten die Meldung, die Sie gesehen haben.",
        blocks=(
            Block(
                anchor="modified-please-reload",
                heading="„Diese Reiseroute wurde geändert, bitte neu laden“",
                kind=KIND_FAQ,
                body="""Die Reise hat sich geändert, nachdem Ihr Bildschirm sie geladen hatte — meist, weil Sie sie auf einem anderen Gerät offen haben oder weil jemand, den Sie zum Bearbeiten eingeladen haben, zuerst gespeichert hat.

Laden Sie die Reise neu und nehmen Sie Ihre Änderung erneut vor. Ntripi verweigert das Speichern, statt stillschweigend zu überschreiben, was während Ihres Tippens hereinkam.""",
            ),
            Block(
                anchor="someone-else-is-editing",
                heading="„Jemand anderes bearbeitet diese Reise“",
                kind=KIND_FAQ,
                body="""Es kann immer nur eine Person eine Reise bearbeiten. Jemand anderes — oder Sie selbst auf einem anderen Gerät — hält sie gerade.

Warten Sie, bis die Person fertig ist, oder übernehmen Sie, wenn sie eine Weile untätig war. Als Eigentümer können Sie sie immer zurückholen. Beim Übernehmen endet die Sitzung der anderen Person, sie wird also informiert, statt still ihre Arbeit zu verlieren.""",
            ),
            Block(
                anchor="lost-the-edit",
                heading="Ich war beim Bearbeiten und kann nicht mehr speichern",
                kind=KIND_FAQ,
                body="""Jemand hat die Reise übernommen, während Sie sie offen hatten. **Ihr Getipptes geht nicht verloren** — der Bildschirm bleibt genau so, mit allen Feldern gefüllt.

Es gibt zwei Auswege, und beide erhalten Ihre Arbeit: die Reise zurückholen und speichern, oder Ihren Text herauskopieren und einfügen, sobald die andere Person fertig ist. Nichts wird verworfen, bevor Sie den Bildschirm selbst verlassen.""",
            ),
            Block(
                anchor="image-rejected",
                heading="Mein Foto wurde beim Hochladen abgelehnt",
                kind=KIND_FAQ,
                body="""Uploads werden vor dem Speichern automatisch geprüft. Ein Bild kann abgelehnt werden, weil es zu klein ist, weil das Format nicht unterstützt wird, oder wegen Inhalten, die den [Community-Richtlinien](/guidelines) nicht entsprechen.

Versuchen Sie ein größeres Bild, mindestens 600 Pixel an der kürzeren Seite. Halten Sie eine Ablehnung für falsch, [melden Sie sich](/help/contact).""",
            ),
            Block(
                anchor="text-rejected",
                heading="Mein Text wurde beim Speichern abgelehnt",
                kind=KIND_FAQ,
                body="""Was Sie schreiben, wird vor dem Speichern gegen die [Community-Richtlinien](/guidelines) geprüft.

Möglicherweise sehen Sie beim Tippen auch einen dezenten Hinweis unter einem Feld. Der ist nur eine Warnung — er blockiert Sie nie und ändert nie, was Sie geschrieben haben. Besonders Ortsnamen können eine Warnung auslösen, ohne ein Problem zu sein.""",
            ),
            Block(
                anchor="cannot-create",
                heading="Ich kann keine Reise anlegen, bewerten oder jemandem folgen",
                kind=KIND_FAQ,
                body="""Dafür ist eine bestätigte E-Mail-Adresse nötig. Suchen Sie den Bestätigungslink in Ihrem Posteingang, oder senden Sie über den Hinweis in Ihrem Profil einen neuen.

Die Anmeldung mit Google unter derselben Adresse bestätigt sie ebenfalls.""",
            ),
            Block(
                anchor="offline",
                heading="Ein Balken sagt, ich sei offline",
                kind=KIND_FAQ,
                body="""Ntripi hat bemerkt, dass die Verbindung weg ist. Bereits Geladenes können Sie weiterlesen; Bedienelemente, die den Server bräuchten, sind ausgegraut, bis Sie zurück sind.

Der Balken verschwindet von selbst, sobald die Verbindung zurück ist — es gibt nichts anzutippen.""",
            ),
            Block(
                anchor="still-stuck",
                heading="Nichts davon passt zu dem, was ich sehe",
                kind=KIND_FAQ,
                body="Melden Sie es aus der App heraus: **schütteln Sie Ihr Telefon**, und Ntripi nimmt den Bildschirm auf, damit Sie das Problem einkreisen können, bevor Sie senden. Siehe [wie Sie uns erreichen](/help/contact).",
            ),
        ),
        keywords=(
            "fehler",
            "problem",
            "probleme",
            "kaputt",
            "funktioniert nicht",
            "fehlgeschlagen",
            "hängt",
            "kann nicht speichern",
            "neu laden",
            "offline",
            "absturz",
            "bug",
            "beheben",
            "hilfe",
        ),
        related=("contact", "getting-started"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-a-bug",
        title="So melden Sie einen Fehler in Ntripi",
        summary="Telefon schütteln, um den Bildschirm aufzunehmen, das Falsche einkreisen und senden — oder im Web die Schaltfläche nutzen.",
        category="troubleshooting",
        schema=SCHEMA_HOWTO,
        intro="**Schütteln Sie Ihr Telefon.** Ntripi nimmt den Bildschirm auf, den Sie gerade ansehen, gibt Ihnen einen Stift zum Einkreisen des Problems und sendet ihn mit Ihrer Notiz. Das ist viel schneller, als ein Layout in Worten zu beschreiben, und Gerät und Version werden für Sie angehängt.",
        blocks=(
            Block(
                anchor="shake",
                heading="Das Telefon schütteln",
                kind=KIND_STEP,
                body="""Überall in der App, in dem Moment, in dem etwas falsch aussieht. Ein Bildschirmfoto genau dieses Bildschirms wird aufgenommen.

Es braucht zwei deutliche Schüttelbewegungen, ein Spaziergang oder eine Busfahrt lösen es also nicht aus. Im Hintergrund wird es ignoriert, und es wartet einige Sekunden bis zur nächsten Auslösung.""",
            ),
            Block(
                anchor="draw",
                heading="Das Problem einkreisen",
                kind=KIND_STEP,
                body="""Zeichnen Sie direkt auf das Bildschirmfoto. Ein Kreis um das Falsche ersetzt einen ganzen Absatz Erklärung.

Sie können bei geöffnetem Melde-Werkzeug navigieren, wenn Sie einen anderen Bildschirm aufnehmen müssen.""",
            ),
            Block(
                anchor="describe",
                heading="Eine Kategorie wählen und beschreiben",
                kind=KIND_STEP,
                body="""Wählen Sie eine von: Absturz, Darstellung, Daten, langsam oder Sonstiges. Beschreiben Sie dann, was Sie getan haben, was Sie erwartet haben und was passiert ist.

Es wird nichts gesendet, bevor Sie auf Senden tippen.""",
            ),
            Block(
                anchor="what-is-sent",
                heading="Was mitgesendet wird",
                body="""Ihre Notiz, Ihre Kategorie, das Bildschirmfoto und technische Angaben zu Gerät und App-Version — die Dinge, die mühsam zu tippen sind und immer als Erstes gefragt werden.

Beim Bildschirmfoto werden die Metadaten entfernt wie bei jedem Upload. Es wird nie einem anderen Nutzer gezeigt, und Fehlermeldungen werden gelöscht, sobald sie geschlossen und alt sind, denn ein Bildschirmfoto kann Informationen anderer Personen enthalten.""",
            ),
            Block(
                anchor="web-and-off",
                heading="Im Web oder mit abgeschalteter Geste",
                body="""Browser kennen kein Schütteln, nutzen Sie im Web daher **Einstellungen ▸ Support ▸ Fehler melden**, was dasselbe Werkzeug öffnet.

Haben Sie die Geste auf dem Telefon abgeschaltet, funktioniert derselbe Menüpunkt weiterhin. Zum Wiedereinschalten: **Einstellungen ▸ Support ▸ Schütteln zum Melden**.""",
            ),
        ),
        keywords=(
            "fehler",
            "bug",
            "melden",
            "kaputt",
            "absturz",
            "rückmeldung",
            "schütteln",
            "screenshot",
            "problem",
            "störung",
        ),
        related=("troubleshooting", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="contact",
        title="So erreichen Sie den Ntripi-Support",
        summary="Wohin mit einem Fehler, einem Sicherheitshinweis, einer Datenschutzanfrage oder einer allgemeinen Frage — und was hineingehört.",
        category="about",
        schema=SCHEMA_CONTACT,
        intro="Der schnellste Weg, ein Problem mit der App zu melden, ist **Ihr Telefon zu schütteln** — Ntripi nimmt den Bildschirm auf und lässt Sie vor dem Senden darauf zeichnen. Für alles andere nutzen Sie unten die Adresse, die zu Ihrem Anliegen passt.",
        blocks=(
            Block(
                anchor="report-a-bug",
                heading="Einen Fehler aus der App heraus melden",
                body="""**Schütteln Sie Ihr Telefon.** Ntripi macht ein Bildschirmfoto, gibt Ihnen einen Stift zum Einkreisen des Fehlers und lässt Sie vor dem Senden eine Notiz und eine Kategorie ergänzen.

Das Bildschirmfoto geht mit, was Ihnen erspart, ein Layout in Worten zu beschreiben. Es wird nichts gesendet, bevor Sie auf Senden tippen.

Die Geste können Sie unter **Einstellungen ▸ Support ▸ Schütteln zum Melden** abschalten. Im Web gibt es kein Schütteln, nutzen Sie daher **Einstellungen ▸ Support ▸ Fehler melden**.""",
            ),
            Block(
                anchor="email-us",
                heading="Schreiben Sie uns",
                body="""- **[support@ntripi.app](mailto:support@ntripi.app)** — die App ist kaputt, oder Sie kommen nicht weiter.
- **[abuse@ntripi.app](mailto:abuse@ntripi.app)** — Inhalte oder Verhalten, die gegen die [Community-Richtlinien](/guidelines) verstoßen, und alles Dringende zur Sicherheit einer Person.
- **[privacy@ntripi.app](mailto:privacy@ntripi.app)** — Datenschutzanfragen und alles, was die [Datenschutzerklärung](/privacy) abdeckt.
- **[contact@ntripi.app](mailto:contact@ntripi.app)** — alles Übrige.""",
            ),
            Block(
                anchor="what-to-include",
                heading="Was hineingehört",
                body="""Eine Meldung lässt sich viel schneller bearbeiten mit:

- **Was Sie getan haben**, in der Reihenfolge, in der Sie es getan haben.
- **Was Sie erwartet haben** und was stattdessen passiert ist.
- **Ein Bildschirmfoto**, wenn das Problem sichtbar ist.
- **Gerät und App-Version** — das eingebaute Melde-Werkzeug hängt beides automatisch an, ein Grund mehr, es zu nutzen, wo es geht.""",
            ),
            Block(
                anchor="reporting-content",
                heading="Inhalte melden statt eines Fehlers",
                body="""Um etwas zu melden, das eine andere Person veröffentlicht hat, nutzen Sie die Fahnen-Aktion an der Reise, der Rezension oder dem Profil selbst statt einer E-Mail. Sie erreicht die Moderationswarteschlange direkt und trägt den Kontext mit sich.

Meldungen werden der gemeldeten Person nicht gezeigt.""",
            ),
        ),
        keywords=(
            "support",
            "hilfe",
            "e-mail",
            "kontakt",
            "rückmeldung",
            "fehler",
            "bug",
            "melden",
            "missbrauch",
            "datenschutz",
            "beschwerde",
        ),
        related=("troubleshooting",),
        updated="2026-09-01",
    ),
    Article(
        slug="whats-new",
        title="Neu in Ntripi",
        summary="Aktuelle Versionen: was hinzugekommen ist, was sich geändert hat und was behoben wurde.",
        category="about",
        schema=SCHEMA_RELEASES,
        intro="Ntripi wird vor dem öffentlichen Start aktiv weiterentwickelt. Jede Version unten benennt, was sich geändert hat und warum es für Sie wichtig sein könnte.",
        releases=RELEASES,
        keywords=(
            "änderungsprotokoll",
            "versionshinweise",
            "aktualisierungen",
            "neuerungen",
            "version",
            "änderungen",
            "was ist neu",
            "verlauf",
        ),
        related=("getting-started", "contact"),
        updated="2026-09-01",
    ),
)
