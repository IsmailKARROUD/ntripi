"""
constants/help/es.py — the Spanish help centre.

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
        title="Primeros pasos",
        blurb="Crea una cuenta y planifica tu primer viaje.",
        icon="rocket",
    ),
    Category(
        id="building",
        title="Construir un viaje",
        blurb="Paradas, lugares, transporte y las notas que los acompañan.",
        icon="article",
    ),
    Category(
        id="sharing",
        title="Compartir y visibilidad",
        blurb="Decide quién ve un viaje y cómo se lo envías.",
        icon="lock",
    ),
    Category(
        id="community",
        title="Comunidad",
        blurb="Seguimientos, valoraciones, viajes guardados y el feed.",
        icon="group",
    ),
    Category(
        id="account",
        title="Cuenta y ajustes",
        blurb="Inicio de sesión, notificaciones, permisos y tus datos.",
        icon="person",
    ),
    Category(
        id="safety",
        title="Seguridad y moderación",
        blurb="Denuncias, bloqueos, contenido oculto y recursos.",
        icon="flag",
    ),
    Category(
        id="troubleshooting",
        title="Solución de problemas",
        blurb="Cuando algo no funciona como esperabas.",
        icon="warning",
    ),
    Category(
        id="about",
        title="Sobre Ntripi",
        blurb="Cómo contactarnos y qué ha cambiado en la última versión.",
        icon="info",
    ),
)

RELEASES: tuple[Release, ...] = (
    Release(
        version="0.3.0",
        date="2026-09-01",
        headline="Edición colaborativa, notificaciones push y un centro de ayuda",
        entries=(
            "**Invita a otras personas a editar un viaje.** El propietario ya puede conceder acceso de edición a otras cuentas, editando una persona cada vez para que no se sobrescriba el trabajo de nadie.",
            "**Notificaciones push** en iOS y Android, para seguimientos, valoraciones, guardados y avisos de moderación.",
            "**Este centro de ayuda**, con todo lo anterior puesto por escrito.",
        ),
    ),
)

ARTICLES: tuple[Article, ...] = (
    Article(
        slug="getting-started",
        title="Cómo empezar a planificar un viaje en Ntripi",
        summary="Crea una cuenta, conoce las cinco pestañas y construye tu primer viaje en unos minutos.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Ntripi es una aplicación de viajes para construir planes a partir de paradas reales — con lo que cuesta cada una, cuánto tiempo lleva y cómo se pasa de una a otra — y compartirlos con quien tú elijas. Crea una cuenta, abre la pestaña **Itinerarios** y añade tu primer viaje.",
        blocks=(
            Block(
                anchor="create-an-account",
                heading="Crear una cuenta",
                kind=KIND_STEP,
                body="""Puedes registrarte de tres formas: con un correo electrónico y una contraseña, con **Iniciar sesión con Google** o con **Iniciar sesión con Apple**. Las tres llegan al mismo sitio.

Se te pedirá un nombre visible, un nombre de usuario y tu fecha de nacimiento. Ntripi tiene una edad mínima de 16 años. Tu fecha de nacimiento nunca aparece en tu perfil y ningún otro usuario puede verla.

Tu nombre visible puede ser cualquier cosa, en cualquier idioma, hasta 50 caracteres. Tu nombre de usuario es el `@nombre` con el que los demás te encuentran, y es lo que se muestra si nunca defines un nombre visible.""",
            ),
            Block(
                anchor="verify-your-email",
                heading="Verificar tu correo electrónico",
                kind=KIND_STEP,
                body="""Algunas acciones quedan retenidas hasta que verificas tu correo: crear un viaje, valorar uno y seguir a personas. Así las cuentas desechables se mantienen fuera de las valoraciones.

Busca el enlace de verificación en tu bandeja de entrada. Si te registraste con Google usando la misma dirección, iniciar sesión con Google la verifica por ti — un aviso en tu perfil te lo ofrece.""",
            ),
            Block(
                anchor="the-five-tabs",
                heading="Orientarse: las cinco pestañas",
                kind=KIND_STEP,
                body="""La barra inferior tiene cinco pestañas. De izquierda a derecha:

- **Buscar** — encuentra *personas*, no viajes. Busca por nombre de usuario.
- **Perfil** — tu propio perfil, y el engranaje que abre todos los ajustes.
- **Itinerarios** — los viajes que son tuyos, más aquellos a los que te han invitado a editar.
- **Guardados** — los viajes que has marcado.
- **Feed** — viajes públicos de todo el mundo, en orden **Top** y **Recientes**.

La campana junto al engranaje, en tu perfil, abre tus notificaciones.""",
            ),
            Block(
                anchor="build-your-first-trip",
                heading="Construir tu primer viaje",
                kind=KIND_STEP,
                body="""Abre **Itinerarios** y toca **+**. Ponle un título al viaje y elige la moneda en la que anotarás los costes; después empieza a añadir paradas.

Los viajes nuevos son visibles **solo para ti** hasta que lo cambies, así que experimentar no tiene ningún riesgo. Consulta [cómo planificar un itinerario de viaje](/help/plan-a-trip-itinerary) para el recorrido completo.""",
            ),
            Block(
                anchor="where-to-get-help",
                heading="Obtener ayuda dentro de la aplicación",
                body="""La mayoría de los campos de formulario tienen un pequeño icono **?** junto a su etiqueta. Al tocarlo se explica para qué sirve ese campo, sin salir de la pantalla: es la forma más rápida de entender un campo que no has usado antes.

**Ajustes ▸ Centro de ayuda** reúne las preguntas habituales y las formas de contactarnos. Si algo está roto, consulta [cómo informar de un fallo](/help/contact).""",
            ),
        ),
        keywords=(
            "registro",
            "registrarse",
            "crear una cuenta",
            "cuenta nueva",
            "primera vez",
            "principiante",
            "introducción",
            "básicos",
            "empezar",
            "comenzar",
        ),
        related=("plan-a-trip-itinerary", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="¿Listo para planificar algo? Empieza tu primer viaje.",
    ),
    Article(
        slug="plan-a-trip-itinerary",
        title="Cómo planificar un itinerario de viaje, paso a paso",
        summary="Construye un itinerario con paradas reales, costes, tiempo y transporte: de un viaje vacío a uno que puedes compartir.",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="Un viaje en Ntripi es una lista ordenada de paradas. Cada parada es un lugar real con una ubicación, un coste aproximado y el tiempo que esperas pasar allí. Entre paradas anotas cómo te desplazas. Constrúyelo en cuatro pasadas: crear el viaje, añadir paradas, conectarlas y elegir quién puede verlo.",
        blocks=(
            Block(
                anchor="create-the-trip",
                heading="Crear el viaje",
                kind=KIND_STEP,
                body="""En la pestaña **Itinerarios**, toca **+**. Necesitas un título para empezar; todo lo demás puede esperar.

- **Título** — qué es el viaje. «Cuatro días en Marrakech» es mejor que «Marruecos».
- **Moneda** — cada coste que anotes la usa, para que el total tenga sentido. Elige la que vayas a gastar de verdad.
- **Imagen de portada** — opcional, y puedes añadirla más tarde. Es lo que la gente ve en el feed y en un enlace compartido.
- **Mejor época** — los meses en que este viaje funciona. Útil para todo lo estacional.""",
            ),
            Block(
                anchor="add-stops",
                heading="Añadir tus paradas",
                kind=KIND_STEP,
                body="""Toca **+** dentro del viaje para añadir una parada. Una parada contiene:

- **Nombre y dirección** — cómo se llama el lugar.
- **Ubicación** — elige un punto en el mapa, o pega un enlace de Google Maps y deja que Ntripi extraiga las coordenadas.
- **Tipo de lugar** — comer y beber, dormir, monumentos, naturaleza, compras, etc. Es lo que dibuja el icono correcto en el mapa y en la lista.
- **Coste** — aproximadamente lo que cuesta por persona. Déjalo vacío o márcalo como gratis.
- **Tiempo previsto** — cuánto tiempo reservar. Es lo que hace que un plan sea realista en vez de optimista.
- **Notas** — cualquier cosa que quieras recordar.

Añade las paradas en el orden en que las visitarás. Podrás arrastrarlas después.""",
            ),
            Block(
                anchor="connect-the-stops",
                heading="Anotar cómo pasas de una parada a otra",
                kind=KIND_STEP,
                body="""Entre dos paradas puedes añadir un **transporte**: cómo viajas, cuánto tarda y cuánto cuesta.

Un transporte puede tener más de un tramo — un autobús hasta la estación y luego un tren — y cada tramo puede llevar el número de línea y la dirección, que es justo el detalle que no se recuerda el día en cuestión.""",
            ),
            Block(
                anchor="add-warnings-and-tips",
                heading="Añadir avisos y consejos",
                kind=KIND_STEP,
                body="""Cualquier parada, y el viaje en conjunto, puede llevar notas breves de cuatro tipos: **consejo**, **precaución**, **evitar** e **información**. Se muestran como etiquetas de colores, así que cuesta pasarlas por alto.

Ahí es donde encajan «compra las entradas antes de ir» y «la entrada norte está cerrada»: las cosas que un itinerario a secas nunca cuenta.""",
            ),
            Block(
                anchor="choose-who-sees-it",
                heading="Elegir quién puede verlo",
                kind=KIND_STEP,
                body="""Los viajes nuevos empiezan en **solo yo**. Cuando estés listo, abre los ajustes del viaje y elige uno de los cuatro niveles: público, seguidores, personas concretas o solo tú.

Consulta [cómo compartir un viaje sin hacerlo público](/help/share-an-itinerary-privately) para saber qué significa cada nivel en la práctica.""",
            ),
        ),
        keywords=(
            "planificador de viajes",
            "itinerario de viaje",
            "itinerarios",
            "día a día",
            "planificar vacaciones",
            "organizar un viaje",
            "ruta",
            "programa",
            "paradas",
            "presupuesto",
            "coste",
            "planificación",
        ),
        related=("plan-alternative-options", "share-an-itinerary-privately", "getting-started"),
        updated="2026-09-01",
        cta="Planifica tu propio itinerario: son unos diez minutos.",
    ),
    Article(
        slug="app-map",
        title="Las pantallas y los iconos de Ntripi, explicados",
        summary="Un recorrido guiado por las cinco pestañas, la pantalla de itinerario y los iconos que irás encontrando.",
        category="getting-started",
        intro="Ntripi tiene cinco pestañas abajo y muy poco adorno encima. Casi todo lo que puedes cambiar vive detrás del engranaje de tu perfil o detrás de una pulsación larga sobre el propio elemento. Esta página le pone nombre a cada cosa.",
        blocks=(
            Block(
                anchor="bottom-nav",
                heading="Las cinco pestañas",
                kind=KIND_DIAGRAM,
                body="""1. **Buscar** — encuentra **personas**, no viajes. Busca por nombre de usuario. Los viajes públicos se descubren en el Feed.
2. **Perfil** — tu propio perfil. El engranaje abre todos los ajustes; la campana de al lado abre tus notificaciones.
3. **Itinerarios** — los viajes que son tuyos, y una segunda vista para los que otras personas te han invitado a editar.
4. **Guardados** — los viajes que has marcado, con un campo de filtro.
5. **Feed** — viajes públicos de todo el mundo, en orden **Top** y **Recientes**.

Tocar la pestaña en la que ya estás te devuelve arriba del todo, que es la salida más rápida de una pantalla profunda.""",
            ),
            Block(
                anchor="itinerary-screen",
                heading="Leer un itinerario",
                kind=KIND_DIAGRAM,
                body="""1. **La etiqueta de visibilidad** bajo el título — quién puede abrir este viaje. Tócala (como propietario) para cambiarla.
2. **Una segunda columna** significa que esas dos paradas son alternativas entre sí, no una secuencia. Consulta [cómo planificar dos opciones para el mismo día](/help/plan-alternative-options).
3. **Una fila de transporte** entre dos paradas — cómo se va de una a otra y cuánto se tarda.
4. **Una etiqueta de color** sobre una parada es una nota: consejo, precaución, evitar o información.
5. **La fila de valoración** — la media y cuántas personas han valorado. Las medias aparecen a partir de tres.""",
            ),
            Block(
                anchor="icons",
                heading="Los iconos que encontrarás",
                body="""| Icono | Qué hace |
|---|---|
| **?** | Explica el campo de al lado, sin salir de la pantalla |
| Marcador | Guarda el viaje en tu pestaña Guardados |
| Lápiz | Editar — solo aparece si puedes editarlo |
| Bandera | Denunciarlo |
| Engranaje | Ajustes, en tu propio perfil |
| Campana | Notificaciones, con un punto cuando hay algo nuevo |

Merece la pena conocer el **?**: casi todos los campos de todos los formularios tienen uno, y es más rápido que venir aquí.""",
            ),
            Block(
                anchor="long-press",
                heading="Atajos con pulsación larga",
                body="""Mantener el dedo sobre una parte de un viaje que es tuyo lleva directamente a editar esa parte: el título, la portada, una parada, una nota. Ahorra volver a pasar por la pantalla de edición.

En el viaje de otra persona el mismo gesto ofrece denunciar o bloquear. Los dos nunca se solapan, así que no puedes denunciar tu propio viaje por accidente ni editar el de otro.""",
            ),
        ),
        keywords=(
            "iconos",
            "botones",
            "menú",
            "navegación",
            "pestañas",
            "dónde está",
            "para qué sirve este botón",
            "interfaz",
            "disposición",
            "pantallas",
        ),
        related=("getting-started", "app-settings"),
        updated="2026-09-01",
        cta="Compruébalo tú mismo: abre Ntripi.",
    ),
    Article(
        slug="plan-alternative-options",
        title="Cómo planificar dos opciones para el mismo día",
        summary="Coloca lugares alternativos en paralelo dentro de un mismo viaje, para que un día de lluvia u otro presupuesto no exija un segundo plan.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="La mayoría de los planificadores obligan a un lugar por hueco. Ntripi te deja apilar **alternativas en paralelo**: dos o tres lugares que ocupan el mismo punto del viaje, para que quien viaje elija sobre la marcha. Internamente, estas columnas se llaman **columnas paralelas**.",
        blocks=(
            Block(
                anchor="what-a-track-is",
                heading="Qué es una columna",
                body="""Una **columna** es una fila vertical de paradas que son alternativas entre sí. Un viaje con una sola columna es un itinerario lineal normal. Añade una segunda columna en el mismo punto y tendrás dos maneras de pasar esa parte del viaje.

Las columnas sirven siempre que la respuesta sea «depende»:

- **Tiempo** — una opción al aire libre y otra a cubierto.
- **Presupuesto** — el restaurante caro y el bueno y barato.
- **Energía** — la caminata larga y el paseo corto.
- **Gustos** — el museo para media cuadrilla y el mercado para la otra.""",
            ),
            Block(
                anchor="add-an-alternative",
                heading="Añadir una alternativa",
                kind=KIND_STEP,
                body="""Abre el viaje y busca la parada a la que quieres una alternativa. Usa el control de añadir que tiene al lado y elige colocar la nueva parada en una **columna nueva** en vez de después de la existente.

Ahora las dos paradas están una al lado de la otra. Ninguna es la «de verdad»: son iguales, y quien lea el viaje ve las dos.""",
            ),
            Block(
                anchor="move-a-stop",
                heading="Mover una parada de una columna a otra",
                kind=KIND_STEP,
                body="""Una parada se puede mover a otra columna después, así que no quedas atado al orden en que fuiste añadiendo cosas. Abre la parada y usa la acción de mover para elegir su columna.

Una columna existe solo mientras tenga al menos una parada. Mueve o borra la última parada y la columna vacía desaparece sola: no hay nada que recoger.""",
            ),
            Block(
                anchor="reorder",
                heading="Reordenar columnas y paradas",
                kind=KIND_STEP,
                body="Arrastra para reordenar las paradas dentro de una columna, y para reordenar las columnas entre sí. La primera columna de un viaje se trata como el punto de partida y la última como el destino, que es lo que el mapa une.",
            ),
            Block(
                anchor="transport-warning",
                heading="Por qué insertar una columna a veces te avisa",
                body="""El transporte se anota entre dos columnas *vecinas*. Si insertas una columna nueva entre dos que ya están unidas por un transporte, esa conexión se queda sin sitio: las dos columnas ya no son vecinas.

Ntripi pregunta antes de hacerlo en vez de descartar en silencio el transporte que introdujiste. Confirma y la conexión afectada se elimina; cancela y no cambia nada.""",
            ),
        ),
        keywords=(
            "paralelo",
            "columna",
            "columnas",
            "alternativa",
            "alternativas",
            "opciones",
            "opcional",
            "plan b",
            "respaldo",
            "rama",
            "o uno u otro",
            "día de lluvia",
            "tiempo",
            "elección",
        ),
        related=("plan-a-trip-itinerary", "getting-started"),
        updated="2026-09-01",
        cta="Planifica un viaje con alternativas reales, no una única línea frágil.",
    ),
    Article(
        slug="add-places-to-an-itinerary",
        title="Cómo añadir lugares, costes y tiempo a un plan de viaje",
        summary="Todo lo que puede contener una parada: qué es, dónde está, cuánto cuesta y cuánto tiempo reservar.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Una parada es un lugar en el que vas a estar de verdad. Más allá de su nombre, los dos campos que hacen que un plan sea utilizable son el **coste** y el **tiempo previsto**: son los que convierten una lista de lugares en algo que se puede presupuestar y encajar en un día.",
        blocks=(
            Block(
                anchor="add-a-stop",
                heading="Añadir una parada",
                kind=KIND_STEP,
                body="""Abre el viaje y toca **+**. Dale al lugar un nombre — el que dirías en voz alta, no su denominación oficial — y una dirección si la tienes.

Las paradas se añaden en orden de visita. Puedes arrastrarlas a otro orden en cualquier momento después.""",
            ),
            Block(
                anchor="place-type",
                heading="Elegir un tipo de lugar",
                kind=KIND_STEP,
                body="""El tipo de lugar dibuja el icono correcto en el mapa y en la lista, para que un día se lea de un vistazo. Hay once:

- **Comer y beber** · **Dormir** · **Comprar**
- **Aprender y ver** · **Monumento** · **Ocio**
- **Jugar y ver** · **Naturaleza** · **Salud y baños**
- **Rezar** · **Viajar**

Es opcional. Una parada sin tipo funciona igual; simplemente se ve como todas las demás sin tipo.""",
            ),
            Block(
                anchor="cost",
                heading="Anotar cuánto cuesta",
                kind=KIND_STEP,
                body="""Introduce el coste aproximado **por persona**, en la moneda del viaje. Con una aproximación basta: lo que importa es el total al final, no una factura.

Si un lugar es gratis, márcalo como gratis en vez de dejar el campo vacío. Vacío significa «no lo he mirado», y la diferencia importa a quien lea tu plan.""",
            ),
            Block(
                anchor="time-to-spend",
                heading="Anotar cuánto tiempo reservar",
                kind=KIND_STEP,
                body="""Este es el campo que impide que un plan sea una fantasía. Cuatro monumentos en una tarde parece razonable en una lista y resulta imposible cuando cada uno lleva noventa minutos.

Reserva el tiempo que realmente querrías estar allí, no el mínimo en el que se puede hacer.""",
            ),
            Block(
                anchor="notes",
                heading="Añadir tus propias notas",
                body="""El campo de notas es texto libre: referencias de reserva, qué pedir, por qué entrada entrar, por qué elegiste este sitio y no el de al lado.

Para un aviso que deba costar pasar por alto en vez de leerse de refilón, usa mejor [una nota de consejo o precaución](/help/travel-notes-and-warnings): esas se muestran como etiquetas de color.""",
            ),
        ),
        keywords=(
            "parada",
            "paradas",
            "lugar",
            "lugares",
            "añadir",
            "presupuesto",
            "precio",
            "duración",
            "cuánto tiempo",
            "categoría",
            "restaurante",
            "hotel",
            "museo",
        ),
        related=("plan-a-trip-itinerary", "add-locations-from-google-maps", "travel-notes-and-warnings"),
        updated="2026-09-01",
        cta="Empieza un viaje y añade tu primera parada.",
    ),
    Article(
        slug="add-locations-from-google-maps",
        title="Cómo añadir un lugar desde un enlace de Google Maps",
        summary="Pega un enlace de Maps y Ntripi extrae las coordenadas, o coloca tú mismo el punto en el mapa.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Una parada puede obtener su ubicación de dos maneras: eligiendo el punto en el propio mapa de Ntripi, o pegando un enlace de Google Maps y dejando que Ntripi extraiga las coordenadas. Lo segundo suele ser más rápido, porque probablemente ya has encontrado el lugar allí.",
        blocks=(
            Block(
                anchor="paste-a-link",
                heading="Pegar un enlace de Google Maps",
                kind=KIND_STEP,
                body="""En el campo de ubicación de la parada, cambia a la opción de enlace y pega la URL. Ntripi extrae las coordenadas y conserva el enlace, así que la parada muestra una pequeña vista previa del mapa y podrás abrir el lugar en Maps más adelante.

Funcionan tanto la URL larga de escritorio como el enlace corto para compartir. Solo se aceptan direcciones de Google Maps: un enlace a cualquier otro sitio se rechaza en vez de guardarse e ignorarse en silencio.""",
            ),
            Block(
                anchor="pick-on-the-map",
                heading="O coloca tú mismo el punto",
                kind=KIND_STEP,
                body="""Cambia a coordenadas y abre el selector de mapa. Desplaza y amplía hasta el sitio: el punto del centro es lo que se guarda.

Es la mejor opción para un lugar que no está en Maps: un mirador, el inicio de un sendero, una playa sin nombre.""",
            ),
            Block(
                anchor="locate-me",
                heading="Centrar el mapa en donde estás",
                kind=KIND_STEP,
                body="""El botón de localización centra el mapa en tu posición actual, lo que evita cruzar un continente para encontrar el pueblo en el que estás.

Pide permiso de ubicación la primera vez. **Rechazarlo no bloquea nada**: el mapa simplemente se abre en otro sitio y tú te desplazas a donde quieras. Consulta [qué permisos pide Ntripi](/help/permissions).""",
            ),
            Block(
                anchor="opening-in-maps",
                heading="Abrir una parada en tu aplicación de mapas",
                body="""Una parada con ubicación ofrece abrirse en la aplicación de mapas que tengas instalada, para obtener indicaciones sobre la marcha sin volver a escribir nada.

El mapa de Ntripi sirve para leer el plan; tu aplicación de mapas sirve para recorrerlo.""",
            ),
        ),
        keywords=(
            "google maps",
            "enlace",
            "pegar",
            "coordenadas",
            "gps",
            "punto",
            "ubicación",
            "selector de mapa",
            "latitud",
            "longitud",
            "dónde",
        ),
        related=("add-places-to-an-itinerary", "permissions"),
        updated="2026-09-01",
        cta="Coloca tu primera parada en el mapa.",
    ),
    Article(
        slug="plan-transport-between-stops",
        title="Cómo planificar el transporte entre paradas",
        summary="Anota cómo pasas de un lugar al siguiente: el modo, el tiempo, el coste y el número de línea que no vas a recordar.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Entre dos paradas cualesquiera puedes anotar un **transporte**: cómo viajas, cuánto tarda y cuánto cuesta. Un transporte puede tener varios tramos, así que un trayecto de autobús y luego tren sigue siendo una sola conexión en vez de dos huecos sin explicar.",
        blocks=(
            Block(
                anchor="add-a-segment",
                heading="Añadir una conexión",
                kind=KIND_STEP,
                body="""Entre dos paradas, usa el control de añadir transporte. Elige el modo — a pie, en bici, autobús, tren, metro, taxi, coche, ferri, avión — y dale una duración.

El coste es por persona, en la moneda del viaje, y se suma al total junto con las paradas.""",
            ),
            Block(
                anchor="multiple-legs",
                heading="Añadir más de un tramo",
                kind=KIND_STEP,
                body="""Un desplazamiento rara vez usa un solo vehículo. Añade un tramo por cada parte — el paseo hasta la parada, el autobús, el transbordo, el tren — y cada uno conserva su modo y su duración.

La conexión muestra entonces el tiempo real de puerta a puerta, que es el número que decide si la tarde encaja.""",
            ),
            Block(
                anchor="line-and-direction",
                heading="Anotar la línea y la dirección",
                kind=KIND_STEP,
                body="""Cada tramo puede llevar una línea — `M4`, `Bus 12`, `RER B` — y una dirección, que es el destino final que se ve en la parte delantera del vehículo.

La dirección es el detalle que importa el día en cuestión. Saber que quieres el M4 no sirve de nada en un andén donde los trenes van en los dos sentidos.""",
            ),
            Block(
                anchor="orphaned-connections",
                heading="Por qué insertar una parada puede avisarte",
                body="""Una conexión vive *entre dos vecinas*. Si insertas una columna nueva entre dos que ya tienen una, esa conexión se queda sin sitio.

Ntripi pregunta antes de hacerlo en vez de descartar en silencio lo que introdujiste. Confirma y la conexión afectada se elimina; cancela y no cambia nada.""",
            ),
        ),
        keywords=(
            "transporte",
            "tránsito",
            "autobús",
            "tren",
            "metro",
            "taxi",
            "andar",
            "coche",
            "vuelo",
            "conexión",
            "tramo",
            "trayecto",
            "cómo llegar",
        ),
        related=("add-places-to-an-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Traza un desplazamiento, con transbordos incluidos.",
    ),
    Article(
        slug="travel-notes-and-warnings",
        title="Cómo añadir avisos y consejos de viaje a un viaje",
        summary="Cuatro tipos de nota — consejo, precaución, evitar e información — que se muestran como etiquetas de color para que nadie pase de largo.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Lo que sale mal en un viaje casi nunca está en la guía. Ntripi tiene cuatro tipos de nota — **consejo**, **precaución**, **evitar** e **información** — que se enganchan a una parada concreta o al viaje entero y se dibujan como etiquetas de color, de modo que el lector se las encuentra en vez de tener que buscarlas.",
        blocks=(
            Block(
                anchor="the-four-types",
                heading="Para qué sirve cada tipo",
                body="""- **Consejo** — haz esto y saldrá mejor. «Compra la entrada por internet, la cola es de una hora.»
- **Precaución** — no pasa nada, pero ten cuidado. «Muy concurrido de noche; lleva el bolso delante.»
- **Evitar** — no lo hagas. «La parada de taxis de la puerta cobra de más; camina dos calles y para uno.»
- **Información** — conviene saberlo, no hay que hacer nada. «Cierra los martes.»

El tipo solo cambia el color y la etiqueta, así que elige el que un desconocido leería como tú querías.""",
            ),
            Block(
                anchor="add-to-a-stop",
                heading="Añadir una nota a una parada",
                kind=KIND_STEP,
                body="""Abre la parada y añade ahí la nota. Pertenece a ese lugar y viaja con él si reordenas el viaje.

Ahí encaja todo lo relativo a una entrada concreta, una cola, un horario de apertura o un riesgo local.""",
            ),
            Block(
                anchor="add-to-the-trip",
                heading="Añadir una nota al viaje entero",
                kind=KIND_STEP,
                body="""Desde el propio itinerario, una nota se aplica al viaje en conjunto: requisitos de visado, la temporada, qué tarjeta SIM funciona, qué llevar.

Las notas del viaje se muestran arriba, antes de las paradas, porque normalmente hay que leerlas antes de planificar un día.""",
            ),
            Block(
                anchor="notes-vs-notes",
                heading="Notas de color frente al campo de notas",
                body="""Cada parada tiene además un campo de **notas** normal. Úsalo para tus propios recordatorios: una referencia de reserva, qué pedir.

Usa una nota de color para todo aquello sobre lo que un lector deba *actuar*. La diferencia está en si debe ser fácil o no pasarlo por alto.""",
            ),
        ),
        keywords=(
            "nota",
            "notas",
            "aviso",
            "avisos",
            "consejo",
            "consejos",
            "truco",
            "precaución",
            "evitar",
            "información",
            "anotación",
            "seguridad",
            "estafa",
        ),
        related=("add-places-to-an-itinerary", "plan-a-trip-itinerary"),
        updated="2026-09-01",
        cta="Escribe lo que te habría gustado que te contaran.",
    ),
    Article(
        slug="trip-cover-photos",
        title="Cómo añadir una foto de portada a tu viaje",
        summary="Elige una imagen de portada, recórtala y ten claro qué se rechaza antes de subirla.",
        category="building",
        intro="La portada es lo que la gente ve en el feed y en un enlace compartido, así que trabaja más que cualquier otro campo. Solo el **propietario** del viaje puede ponerla: alguien invitado a editar puede cambiar el contenido, pero no la cara pública del viaje.",
        blocks=(
            Block(
                anchor="add-a-cover",
                heading="Añadir o cambiar la portada",
                body="""Abre la pantalla de edición del viaje y toca la zona de portada. Se abre tu galería; elige una imagen y recórtala al marco.

El recorte es apaisado, porque esa es la forma que usa una vista previa de enlace. Una foto vertical perderá la parte de arriba y la de abajo, así que elige una cuyo motivo esté en el centro.""",
            ),
            Block(
                anchor="what-gets-refused",
                heading="Qué se rechaza, y por qué",
                body="""Una imagen puede rechazarse por tres motivos:

- **Demasiado pequeña.** Por debajo de 600 píxeles en su lado más corto se verá borrosa en una pantalla moderna.
- **Un formato no admitido.** JPEG, PNG y los formatos de foto habituales van bien.
- **El contenido.** Las subidas se comprueban automáticamente frente a las [normas de la comunidad](/guidelines) antes de guardarse.

Si crees que un rechazo fue un error, [cuéntanoslo](/help/contact).""",
            ),
            Block(
                anchor="what-we-strip",
                heading="Qué elimina Ntripi de tu foto",
                body="""A toda imagen subida se le **eliminan los metadatos EXIF** antes de guardarla. Es el bloque de datos ocultos que adjunta una cámara: sobre todo las **coordenadas GPS del lugar donde se tomó la foto**, junto con el modelo del dispositivo y la fecha.

Ocurre sea el viaje público o no, y no se puede desactivar. Una foto de tu calle no debería publicar tu calle.""",
            ),
            Block(
                anchor="no-cover",
                heading="Si no añades ninguna",
                body="""Un viaje sin portada recibe un marcador de posición generado a partir de su ruta, así que nunca se ve roto.

Aun así conviene poner una de verdad antes de compartirlo públicamente: en un feed de fotografías, el marcador de posición es lo que la gente pasa de largo.""",
            ),
        ),
        keywords=(
            "portada",
            "foto",
            "imagen",
            "subir",
            "recortar",
            "banner",
            "miniatura",
            "rechazada",
            "demasiado pequeña",
        ),
        related=("plan-a-trip-itinerary", "share-a-trip-link"),
        updated="2026-09-01",
        cta="Dale una cara a tu viaje.",
    ),
    Article(
        slug="plan-a-trip-with-friends",
        title="Cómo planificar un viaje junto a otras personas",
        summary="Invita a otras personas a editar un viaje y entiende por qué solo una puede estar escribiendo a la vez.",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="Un viaje tiene un propietario y cualquier número de **editores**. Un editor puede cambiar el contenido — paradas, transporte, notas, el título — pero no quién puede verlo, ni la portada, ni la lista de editores. Solo una persona edita a la vez, para que no se sobrescriba el trabajo de nadie.",
        blocks=(
            Block(
                anchor="invite-an-editor",
                heading="Invitar a alguien a editar",
                kind=KIND_STEP,
                body="""Abre la pantalla de edición del viaje y busca la lista de editores. Añade a la persona por su nombre de usuario. Recibirá una notificación que nombra el viaje, que es justo lo que le permite encontrarlo: un viaje privado no está en ningún feed ni en ninguna búsqueda.

Solo el **propietario** puede añadir o quitar editores. Un editor no puede reclutar a más: la invitación es tu decisión de confianza y no lleva consigo el poder de transmitirla.""",
            ),
            Block(
                anchor="cannot-see-it",
                heading="Si todavía no pueden ver el viaje",
                kind=KIND_STEP,
                body="""Editar exige poder ver primero. Si invitas a alguien que no puede, Ntripi pregunta si además quieres darle acceso, en vez de fallar.

Decir que sí lo añade a la lista de permitidos de ese viaje y nada más. Nunca amplía la visibilidad del viaje: convertir «seguidores» en «personas concretas» dejaría fuera en silencio a todos los demás, así que eso sigue siendo una decisión que tomas de forma deliberada.""",
            ),
            Block(
                anchor="one-at-a-time",
                heading="Por qué solo una persona puede editar a la vez",
                body="""Cuando abres un viaje para editarlo, lo retienes. Cualquier otra persona ve **«alguien más está editando»** y puede leer pero no guardar.

La alternativa es que dos personas escriban en la misma parada y una de ellas lo pierda todo sin que se lo digan. La retención es breve: se suelta cuando sales y caduca por sí sola si te distraes.""",
            ),
            Block(
                anchor="taking-over",
                heading="Tomar el relevo de alguien",
                kind=KIND_STEP,
                body="""Si el viaje lleva un rato inactivo, cualquiera que pueda editarlo puede tomarlo. Como propietario siempre puedes recuperarlo, incluso de tu propio segundo dispositivo, que es el motivo habitual de que se quede atascado.

Tomar el relevo es siempre un segundo paso deliberado, nunca automático.""",
            ),
            Block(
                anchor="losing-the-lock",
                heading="Si alguien lo toma mientras escribes",
                body="""Aparece un aviso y Guardar deja de funcionar. **No se pierde nada de lo que hayas escrito**: cada campo queda exactamente como lo dejaste, y aún puedes seleccionar y copiar de ellos.

Recupera el viaje y guarda, o copia tu texto y pégalo cuando la otra persona haya terminado. Ntripi no va a cerrar la pantalla ni a vaciar un campo por ti, porque en ese momento tu texto sin guardar es la única copia que existe.""",
            ),
            Block(
                anchor="finding-shared-trips",
                heading="Encontrar un viaje que alguien compartió contigo",
                body="La pestaña **Itinerarios** tiene una segunda vista para los viajes a los que te han invitado a editar. Ese es el camino duradero de vuelta: la notificación que lo anunció acaba desapareciendo, y un viaje privado no aparece en ningún feed ni en ninguna búsqueda.",
            ),
        ),
        keywords=(
            "colaborar",
            "colaboración",
            "juntos",
            "compartido",
            "editor",
            "editores",
            "invitar",
            "grupo",
            "amigos",
            "familia",
            "coeditar",
            "alguien más está editando",
            "bloqueo",
        ),
        related=("share-an-itinerary-privately", "plan-alternative-options", "troubleshooting"),
        updated="2026-09-01",
        cta="Planifica tu próximo viaje con quienes van a hacerlo.",
    ),
    Article(
        slug="share-an-itinerary-privately",
        title="Cómo compartir un itinerario de viaje sin hacerlo público",
        summary="Cuatro niveles de visibilidad deciden quién puede abrir un viaje: desde todo internet hasta un puñado de personas concretas.",
        category="sharing",
        schema=SCHEMA_FAQ,
        intro="Cada viaje tiene uno de cuatro niveles de visibilidad, y puedes cambiarlo cuando quieras. Los viajes nuevos empiezan en **solo yo**. Para compartir con un grupo concreto sin publicar, usa **personas concretas** y añádelas por nombre de usuario.",
        blocks=(
            Block(
                anchor="the-four-levels",
                heading="¿Cuáles son los cuatro niveles de visibilidad?",
                kind=KIND_FAQ,
                body="""- **Público** — cualquiera puede abrirlo, incluso sin haber iniciado sesión. Puede aparecer en el feed y ser encontrado por los buscadores a través de su enlace.
- **Seguidores** — todas las personas que te siguen. Si tu cuenta es privada, eso significa solo los seguidores que hayas aceptado.
- **Personas concretas** — solo los nombres de usuario que añadas. Nadie más, sea como sea que haya conseguido el enlace.
- **Solo yo** — nadie salvo tú y quien hayas hecho editor.""",
            ),
            Block(
                anchor="share-with-a-few-people",
                heading="¿Cómo comparto solo con unas pocas personas?",
                kind=KIND_FAQ,
                body="""Pon el viaje en **personas concretas** y añádelas por nombre de usuario. Después envíales el enlace del viaje.

El enlace no es una contraseña secreta: es la dirección del viaje. El acceso se comprueba contra tu lista cada vez que alguien lo abre, así que reenviar el enlace a alguien que no está en la lista no le sirve de nada.""",
            ),
            Block(
                anchor="what-others-see",
                heading="¿Qué ve alguien sin acceso?",
                kind=KIND_FAQ,
                body="""Una página que dice que el viaje no está disponible. No dice que el viaje exista, ni de quién es, ni cómo se llama: un viaje que no puedes ver es indistinguible de uno que nunca se creó.

Lo mismo ocurre con un perfil que te ha bloqueado.""",
            ),
            Block(
                anchor="change-later",
                heading="¿Puedo cambiar la visibilidad después?",
                kind=KIND_FAQ,
                body="""Sí, cuando quieras y en los dos sentidos. Pasar a un nivel más estrecho tiene efecto de inmediato: quien deja de cumplir los requisitos deja de poder abrirlo.

Solo el propietario del viaje puede cambiar la visibilidad. Alguien a quien hayas invitado a editar puede cambiar el contenido, pero no quién lo ve.""",
            ),
            Block(
                anchor="link-previews",
                heading="¿Qué aparece cuando pego el enlace en algún sitio?",
                kind=KIND_FAQ,
                body="""Un viaje público genera una tarjeta de vista previa con su imagen de portada, su título, su duración, su coste y su valoración.

Un viaje que no es público no genera ninguna vista previa: la vista previa filtraría el título a todo el mundo en la conversación, incluidos quienes no pueden abrirlo.""",
            ),
        ),
        keywords=(
            "privado",
            "en privado",
            "visibilidad",
            "quién puede ver",
            "público",
            "seguidores",
            "restringido",
            "solo yo",
            "ocultar",
            "oculto",
            "secreto",
            "enlace para compartir",
            "permisos",
            "solo amigos",
            "invitar",
        ),
        related=("plan-a-trip-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="Planifica un viaje y compártelo exactamente con quien quieres.",
    ),
    Article(
        slug="share-a-trip-link",
        title="Cómo compartir tu viaje como un enlace",
        summary="Envía un viaje a cualquiera con un enlace, sabiendo qué mostrará la tarjeta de vista previa antes de pegarlo.",
        category="sharing",
        intro="Cada viaje tiene una dirección web. Compartir es simplemente enviarla: el enlace es la ubicación del viaje, no una contraseña, y el acceso se vuelve a comprobar contra tu [ajuste de visibilidad](/help/share-an-itinerary-privately) cada vez que alguien lo abre.",
        blocks=(
            Block(
                anchor="get-the-link",
                heading="Conseguir el enlace",
                body="""Abre el viaje y usa la acción de compartir. Aparece el menú de compartir habitual de tu dispositivo, así que el enlace puede ir a cualquier aplicación: mensajes, correo, notas.

La página se abre en un navegador, así que la persona a la que se lo envías no necesita la aplicación para leerlo.""",
            ),
            Block(
                anchor="what-the-preview-shows",
                heading="Qué muestra la tarjeta de vista previa",
                body="""Un viaje **público** genera una tarjeta de vista previa en la mayoría de las aplicaciones de mensajería: la imagen de portada, el título, la duración y el coste totales, el número de paradas y la valoración si la tiene.

Un viaje que **no** es público no genera ninguna vista previa. Es deliberado: una vista previa mostraría el título a todo el mundo en el grupo, incluidos quienes no pueden abrirlo.""",
            ),
            Block(
                anchor="what-they-see",
                heading="Qué recibe quien lo lee",
                body="""El viaje entero: las paradas en orden, las opciones paralelas, el transporte entre ellas, los costes, tus notas y avisos, y las valoraciones.

Puede leerlo todo sin cuenta. Guardarlo, valorarlo o copiar paradas de él sí requiere una.""",
            ),
            Block(
                anchor="unsharing",
                heading="Dar marcha atrás",
                body="""Cambia la visibilidad del viaje y el enlace deja de funcionar de inmediato para quien ya no cumpla los requisitos. No hace falta perseguir el mensaje que enviaste.

Lo que no puedes deshacer es una captura de pantalla, así que trata publicar como publicar.""",
            ),
        ),
        keywords=(
            "compartir",
            "enlace",
            "url",
            "enviar",
            "whatsapp",
            "vista previa",
            "copiar",
            "publicar",
            "público",
        ),
        related=("share-an-itinerary-privately", "trip-cover-photos"),
        updated="2026-09-01",
        cta="Construye algo que merezca la pena enviar.",
    ),
    Article(
        slug="follow-and-private-accounts",
        title="Seguidores, solicitudes de seguimiento y cuentas privadas",
        summary="Cómo funciona seguir a alguien, qué oculta una cuenta privada y cómo aprobar o rechazar una solicitud.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Seguir a alguien pone sus viajes públicos delante de ti y le permite compartir viajes con sus seguidores. Si tu cuenta es **privada**, un seguimiento se convierte en una **solicitud** que apruebas o rechazas.",
        blocks=(
            Block(
                anchor="how-to-follow",
                heading="¿Cómo sigo a alguien?",
                kind=KIND_FAQ,
                body="""Búscalo en la pestaña **Buscar** — busca por nombre de usuario — y usa Seguir en su perfil.

Si su cuenta es pública, ya lo estás siguiendo. Si es privada, el botón pasa a **Solicitado** hasta que decida.""",
            ),
            Block(
                anchor="what-private-hides",
                heading="¿Qué oculta una cuenta privada?",
                kind=KIND_FAQ,
                body="""Los viajes puestos en **seguidores** pasan a ser visibles solo para los seguidores que hayas aceptado de verdad, y no para cualquiera que haya tocado Seguir.

Los viajes que pongas en **público** siguen siendo públicos: privada se refiere a quién cuenta como seguidor, no es un candado general. Si quieres ocultarlo todo, pon los propios viajes en [solo yo o personas concretas](/help/share-an-itinerary-privately).""",
            ),
            Block(
                anchor="handling-requests",
                heading="¿Dónde apruebo las solicitudes?",
                kind=KIND_FAQ,
                body="""Un aviso en tu perfil muestra el número, y **Ajustes ▸ Solicitudes de seguimiento** las lista. Acepta o rechaza cada una.

Rechazar no se le comunica a nadie. Simplemente dejan de estar pendientes y la persona puede volver a pedirlo.""",
            ),
            Block(
                anchor="going-public",
                heading="¿Qué pasa si paso de privada a pública?",
                kind=KIND_FAQ,
                body="""Toda solicitud pendiente se acepta automáticamente. Dejar a gente en una cola detrás de una puerta que acabas de quitar sería una cola que nadie iba a volver a mirar.

En el otro sentido, de pública a privada, tus seguidores actuales no se eliminan.""",
            ),
            Block(
                anchor="unfollow-vs-block",
                heading="¿Qué diferencia hay entre dejar de seguir y bloquear?",
                kind=KIND_FAQ,
                body="""**Dejar de seguir** solo impide que sus viajes lleguen a tu feed. Esa persona sigue viendo lo que veía antes.

**Bloquear** corta la visibilidad en ambos sentidos, y a la persona bloqueada no se le dice. Consulta [denunciar y bloquear](/help/report-and-block).""",
            ),
        ),
        keywords=(
            "seguir",
            "seguidor",
            "seguidores",
            "siguiendo",
            "solicitud",
            "privada",
            "cuenta pública",
            "aprobar",
            "aceptar",
            "dejar de seguir",
            "bloquear",
        ),
        related=("share-an-itinerary-privately", "report-and-block"),
        updated="2026-09-01",
        cta="Encuentra a la gente cuyos viajes quieres copiar.",
    ),
    Article(
        slug="rate-a-trip",
        title="Cómo funcionan las valoraciones: seguridad, accesibilidad, aglomeraciones y más",
        summary="Una puntuación general más cinco dimensiones opcionales, y por qué las medias solo aparecen cuando han valorado tres personas.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="Una valoración es una puntuación **general** obligatoria sobre cinco, y hasta cinco dimensiones opcionales: seguridad, experiencia, accesibilidad, apto para familias y aglomeración. Puedes dejar un comentario escrito al lado.",
        blocks=(
            Block(
                anchor="the-dimensions",
                heading="¿Qué significan las cinco dimensiones?",
                kind=KIND_FAQ,
                body="""- **Seguridad** — lo seguro que se sintió.
- **Experiencia** — lo bueno que fue realmente.
- **Accesibilidad** — lo bien que funciona con movilidad reducida, un carrito o equipaje pesado.
- **Apto para familias** — lo bien que funciona con niños.
- **Aglomeración** — lo agradablemente tranquilo que estaba.

En todas las dimensiones **más alto es mejor**, aglomeración incluida: cinco significa agradablemente tranquilo, uno significa desbordado. Todas son opcionales: valora solo aquello de lo que puedas hablar.""",
            ),
            Block(
                anchor="three-ratings",
                heading="¿Por qué no veo una media?",
                kind=KIND_FAQ,
                body="""Una dimensión muestra su media solo cuando la han valorado **tres** personas.

La opinión de una sola persona presentada como media se lee como un hecho sobre el lugar y no como un punto de vista, y con dos no mejora mucho. Por debajo de tres ves las valoraciones individuales.""",
            ),
            Block(
                anchor="who-can-rate",
                heading="¿Quién puede valorar un viaje?",
                kind=KIND_FAQ,
                body="""Cualquiera que pueda verlo y tenga el correo verificado, salvo su propietario. Puedes actualizar tu propia valoración cuando quieras: volver a valorar la sustituye en vez de añadir una segunda.

El requisito del correo es lo que mantiene las cuentas desechables fuera de las puntuaciones.""",
            ),
            Block(
                anchor="written-notes",
                heading="¿Puedo escribir una reseña, no solo una puntuación?",
                kind=KIND_FAQ,
                body="""Sí: el cuadro de valoración tiene un campo de comentario, y es la parte que otros viajeros leen de verdad. La puntuación dice cómo fue; el comentario dice por qué.

Los comentarios están sujetos a las [normas de la comunidad](/guidelines) como todo lo que se publica.""",
            ),
            Block(
                anchor="disagreeing",
                heading="Alguien ha valorado mi viaje injustamente",
                kind=KIND_FAQ,
                body="""No puedes eliminar una valoración de tu propio viaje, y esa es la idea: una puntuación que el autor puede borrar no vale nada para el siguiente lector.

Si una valoración incumple las normas en vez de limitarse a no gustarte, [denúnciala](/help/report-and-block) y una persona la revisará.""",
            ),
        ),
        keywords=(
            "valoración",
            "valoraciones",
            "valorar",
            "reseña",
            "reseñas",
            "estrellas",
            "puntuación",
            "seguridad",
            "accesibilidad",
            "familias",
            "aglomeración",
            "masificación",
        ),
        related=("save-trips-and-find-new-ones", "report-and-block"),
        updated="2026-09-01",
        cta="Valora un viaje que hayas hecho de verdad.",
    ),
    Article(
        slug="save-trips-and-find-new-ones",
        title="Cómo guardar viajes y descubrir otros nuevos",
        summary="Marca todo lo que merezca la pena conservar, y entiende la diferencia entre los feeds Top y Recientes.",
        category="community",
        schema=SCHEMA_FAQ,
        intro="La pestaña **Feed** muestra viajes públicos de todo el mundo. Todo lo que merezca la pena conservar se marca en la pestaña **Guardados**, que es solo tuya: a nadie se le dice que has guardado su viaje.",
        blocks=(
            Block(
                anchor="saving",
                heading="¿Cómo guardo un viaje?",
                kind=KIND_FAQ,
                body="""Toca el marcador en cualquier viaje que puedas ver. Aparece en tu pestaña **Guardados**, que tiene su propio campo de filtro cuando la lista crece.

El marcador no se muestra en tus propios viajes: guardar algo que escribiste tú no serviría de nada.""",
            ),
            Block(
                anchor="saved-changes",
                heading="¿Y si un viaje guardado cambia o desaparece?",
                kind=KIND_FAQ,
                body="""Siempre ves la versión actual, no la que guardaste.

Si el autor estrecha su visibilidad o lo borra, sale de tu pestaña Guardados. Un marcador es un puntero, no una copia: el autor mantiene el control de su propio trabajo.""",
            ),
            Block(
                anchor="top-vs-recent",
                heading="¿Qué diferencia hay entre Top y Recientes?",
                kind=KIND_FAQ,
                body="""**Recientes** es todo lo público, de más nuevo a más antiguo. **Top** se ordena por valoración, y un viaje necesita unas cuantas valoraciones antes de poder aparecer siquiera.

En Recientes se encuentra trabajo nuevo; en Top, trabajo que otros han avalado.""",
            ),
            Block(
                anchor="not-in-top",
                heading="¿Por qué mi viaje no está en Top?",
                kind=KIND_FAQ,
                body="""Tiene que ser público y necesita valoraciones suficientes. Un viaje con una sola puntuación entusiasta no demuestra nada, así que el feed Top espera a que haya unas cuantas.

Compártelo por [enlace](/help/share-a-trip-link) con quienes hayan estado allí: eso es lo que hace entrar las primeras valoraciones.""",
            ),
            Block(
                anchor="finding-people",
                heading="¿Cómo encuentro a una persona concreta?",
                kind=KIND_FAQ,
                body="""La pestaña **Buscar** busca nombres de usuario, no viajes. Los viajes se encuentran por el feed, por un enlace que alguien te ha enviado, o por un perfil una vez que has encontrado a la persona.

Un viaje privado no está en ningún feed ni en ninguna búsqueda, por diseño; el único camino hacia él es una invitación o un enlace de alguien que puede verlo.""",
            ),
        ),
        keywords=(
            "guardar",
            "guardados",
            "marcador",
            "favorito",
            "favoritos",
            "feed",
            "descubrir",
            "explorar",
            "top",
            "recientes",
            "tendencias",
            "navegar",
        ),
        related=("rate-a-trip", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="Encuentra un viaje que merezca la pena copiar.",
    ),
    Article(
        slug="notifications",
        title="Cómo controlar qué notificaciones envía Ntripi",
        summary="Las ocho cosas de las que Ntripi te avisará, cuáles tres puedes desactivar y por qué las demás siguen activas.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="La campana junto al engranaje de tu perfil es la lista completa. Tres tipos de notificación se pueden desactivar en **Ajustes ▸ Notificaciones**; el resto siguen activas porque sobre lo que no se ve no se puede actuar a tiempo.",
        blocks=(
            Block(
                anchor="what-you-get",
                heading="¿De qué me avisará Ntripi?",
                kind=KIND_FAQ,
                body="""- Alguien ha pedido seguirte, o ha empezado a seguirte
- Alguien ha aceptado tu solicitud de seguimiento *(opcional)*
- Alguien ha valorado uno de tus viajes *(opcional)*
- Alguien ha guardado uno de tus viajes *(opcional)*
- Te han invitado a editar un viaje
- Te han dado acceso a un viaje
- Una decisión de moderación ha afectado a tu contenido o a tu cuenta

Nada más. No hay marketing, ni recordatorios para que vuelvas, ni resúmenes periódicos.""",
            ),
            Block(
                anchor="switching-off",
                heading="¿Cómo desactivo algunas?",
                kind=KIND_FAQ,
                body="""**Ajustes ▸ Notificaciones** tiene tres interruptores: valoraciones, guardados y solicitud aceptada. Desactivar uno impide que la notificación se cree siquiera, no solo que se muestre.

Para silenciarlo todo, desactiva las notificaciones de Ntripi en los ajustes de tu propio teléfono: consulta [los permisos](/help/permissions).""",
            ),
            Block(
                anchor="always-on",
                heading="¿Por qué no puedo desactivar las demás?",
                kind=KIND_FAQ,
                body="""Las solicitudes de seguimiento, las concesiones de acceso y las decisiones de moderación necesitan una respuesta tuya dentro de un plazo útil.

Una solicitud de seguimiento que nadie ve nunca se responde. Un viaje que alguien compartió contigo no está en ningún feed ni en ninguna búsqueda, así que un aviso que no recibiste es un acceso que nunca supiste que tenías. Y una decisión de moderación tiene un plazo de recurso: el silencio ahí te costaría el recurso.""",
            ),
            Block(
                anchor="arrival",
                heading="¿Por qué algunas llegan tarde?",
                kind=KIND_FAQ,
                body="""La entrega push es de mejor esfuerzo en todas partes: los gestores de batería detienen procesos en segundo plano, los teléfonos limitan, las conexiones se caen.

Por eso Ntripi también comprueba por su cuenta más o menos una vez por minuto mientras está abierta, para que la campana sea correcta aunque nunca llegara un push. Si el push está desactivado o rechazado, esa comprobación es el único canal, y sigue funcionando.""",
            ),
            Block(
                anchor="clearing",
                heading="¿Puedo borrar notificaciones?",
                kind=KIND_FAQ,
                body="""Sí, una a una o todas de golpe, con unos segundos para deshacerlo antes de que sea definitivo.

Borrar un aviso de moderación no borra la decisión: esa se queda en **Ajustes ▸ Estado de la cuenta**, junto con el botón de recurso. Las notificaciones leídas se eliminan a los noventa días; las no leídas duran más, porque son tu único registro de que pasó algo.""",
            ),
        ),
        keywords=(
            "notificación",
            "notificaciones",
            "push",
            "alertas",
            "campana",
            "insignia",
            "silenciar",
            "desactivar",
            "correo",
            "tranquilidad",
        ),
        related=("permissions", "follow-and-private-accounts"),
        updated="2026-09-01",
        cta="Sigue tus viajes sin el ruido.",
    ),
    Article(
        slug="app-settings",
        title="Idioma, modo oscuro, sonidos y vibración",
        summary="Todos los ajustes que hay detrás del engranaje de tu perfil, y qué cambia cada uno.",
        category="account",
        intro="El engranaje de tu propio perfil lo abre todo. Los ajustes se guardan en tu dispositivo, así que son por instalación: cambiar el tema en tu teléfono no lo cambia en tu tableta.",
        blocks=(
            Block(
                anchor="language",
                heading="Idioma",
                body="""Ntripi está disponible en inglés, francés, árabe, alemán, español y chino. Sigue el idioma de tu dispositivo cuando es uno de los seis, y aquí puedes cambiarlo.

El árabe pasa toda la interfaz a derecha-izquierda. La elección viaja también con los documentos legales y con este centro de ayuda cuando los abres desde la aplicación.""",
            ),
            Block(
                anchor="theme",
                heading="Tema",
                body="""Sistema, Claro u Oscuro. **Sistema** sigue a tu teléfono, incluido su cambio automático de día y noche, y es la opción por defecto.

El modo oscuro es un negro de verdad, no un gris: conviene saberlo si lees planes en la cama.""",
            ),
            Block(
                anchor="sounds-and-haptics",
                heading="Efectos de sonido y vibración",
                body="""Dos interruptores independientes. Los **efectos de sonido** son las pequeñas señales: una notificación que llega, una valoración que se registra. La **vibración** son los toques que notas, incluido un zumbido corto por estrella al poner una valoración.

Cada uno se confirma a sí mismo con el ajuste que acabas de elegir, para que oigas o notes lo que estás activando.""",
            ),
            Block(
                anchor="shake-to-report",
                heading="Agitar para informar",
                body="""Activado por defecto en el móvil: agitar captura la pantalla y abre un informe de fallo. Si gesticulas mucho mientras lees, desactívalo aquí — **Ajustes ▸ Soporte ▸ Agitar para informar**.

Es deliberadamente difícil de activar por accidente: exige dos sacudidas distintas, te ignora si la aplicación no está en primer plano y espera unos segundos antes de poder dispararse de nuevo.""",
            ),
            Block(
                anchor="account-rows",
                heading="El resto del menú",
                body="""- **Estado de la cuenta** — decisiones de moderación y recursos
- **Cuentas bloqueadas** — todas las personas que has bloqueado, y un toque para desbloquear
- **Solicitudes de seguimiento** — solo aparece si tu cuenta es privada
- **Centro de ayuda** y **Acerca de** — incluido este sitio

Cambiar tu contraseña o eliminar tu cuenta está en la pantalla de edición de tu perfil, en Seguridad.""",
            ),
        ),
        keywords=(
            "ajustes",
            "configuración",
            "idioma",
            "traducir",
            "modo oscuro",
            "modo claro",
            "tema",
            "sonido",
            "sonidos",
            "vibración",
            "háptica",
            "preferencias",
        ),
        related=("app-map", "notifications", "permissions"),
        updated="2026-09-01",
        cta="Haz que la aplicación sea tuya.",
    ),
    Article(
        slug="permissions",
        title="Qué permisos pide Ntripi, y por qué",
        summary="Ubicación, notificaciones, fotos y movimiento: para qué sirve cada uno, cuándo se te pide y cómo cambiar de opinión.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi pide cuatro cosas, cada una en el momento en que resulta útil por primera vez y no al arrancar. **Nunca pide tu cámara, tus contactos, tu micrófono ni tu ubicación en segundo plano.** Rechazar cualquiera de ellas deja la aplicación funcionando.",
        blocks=(
            Block(
                anchor="location",
                heading="Ubicación: ¿para qué?",
                kind=KIND_FAQ,
                body="""Para centrar el mapa en donde estás cuando añades una parada, y no tener que cruzar un continente para encontrar el pueblo en el que te encuentras.

Se pide la primera vez que usas el botón de localización del mapa, y **solo mientras usas la aplicación**: no hay ubicación en segundo plano ni rastreo. Rechazarla no bloquea nada: el mapa se abre en otro sitio y tú te desplazas al tuyo.""",
            ),
            Block(
                anchor="notifications",
                heading="Notificaciones: por qué, y por qué solo una vez",
                kind=KIND_FAQ,
                body="""Para avisarte de solicitudes de seguimiento, valoraciones, guardados y decisiones de moderación.

Se pide la primera vez que abres la **pantalla de notificaciones**, es decir, justo cuando acabas de demostrar que las quieres. iOS permite a una aplicación exactamente un aviso por instalación, así que pedirlo al arrancar, delante de una aplicación que aún no has visto, gastaría esa única oportunidad con un desconocido.""",
            ),
            Block(
                anchor="photos",
                heading="Fotos: ¿qué ve Ntripi?",
                kind=KIND_FAQ,
                body="""Solo la imagen que eliges. Ntripi abre el selector de fotos de tu sistema, que devuelve un único archivo y nada más: no tiene ninguna vista de tu galería.

A cada subida se le **eliminan los metadatos EXIF**, incluidas las coordenadas GPS del lugar donde se tomó la foto. Consulta [las fotos de portada](/help/trip-cover-photos).""",
            ),
            Block(
                anchor="motion",
                heading="Movimiento y vibración: ¿para qué?",
                kind=KIND_FAQ,
                body="""Agitar el teléfono envía un informe de fallo, y el teléfono vibra brevemente para confirmar cosas como poner una valoración.

Ambos se pueden desactivar en **Ajustes**: **Agitar para informar** y **Vibración**. Nada sobre tu movimiento sale del dispositivo.""",
            ),
            Block(
                anchor="never-asked",
                heading="Qué no pide nunca Ntripi",
                kind=KIND_FAQ,
                body="""La **cámara**, tus **contactos**, tu **micrófono** y la **ubicación en segundo plano**. Ninguno aparece en la aplicación, y ninguno está declarado en las versiones que publicamos.

Si alguna vez algo afirma que Ntripi pide alguno de ellos, no somos nosotros: [cuéntanoslo](/help/contact).""",
            ),
            Block(
                anchor="changing-your-mind",
                heading="¿Cómo cambio un permiso después?",
                kind=KIND_FAQ,
                body="""Los permisos pertenecen a tu sistema operativo, no a Ntripi, así que se cambian allí:

- **iPhone o iPad** — Ajustes ▸ baja hasta Ntripi ▸ activa o desactiva Ubicación o Notificaciones.
- **Android** — Ajustes ▸ Aplicaciones ▸ Ntripi ▸ Permisos.

Esto importa sobre todo para las notificaciones, que iOS no volverá a pedir: una vez rechazadas, la aplicación Ajustes es el único camino de vuelta.""",
            ),
        ),
        keywords=(
            "permiso",
            "permisos",
            "privacidad",
            "ubicación",
            "gps",
            "cámara",
            "fotos",
            "notificaciones",
            "micrófono",
            "contactos",
            "rastreo",
            "seguimiento",
            "permitir",
            "denegar",
        ),
        related=("your-data-and-privacy", "notifications", "add-locations-from-google-maps"),
        updated="2026-09-01",
        cta="Comprueba exactamente qué pide la aplicación, y qué no.",
    ),
    Article(
        slug="your-data-and-privacy",
        title="Qué datos guarda Ntripi, y cómo borrarlos",
        summary="Un resumen en lenguaje claro de qué se conserva, quién puede verlo y cómo eliminar tu cuenta para siempre.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Ntripi guarda lo que escribes y lo que subes, más lo necesario para iniciar tu sesión. No hay publicidad, no hay rastreo publicitario de terceros y no se vende nada. La [política de privacidad](/privacy) es el texto que rige; esta es la versión corta.",
        blocks=(
            Block(
                anchor="what-is-stored",
                heading="¿Qué guarda Ntripi sobre mí?",
                kind=KIND_FAQ,
                body="""- **Tu cuenta** — nombre visible, nombre de usuario, correo electrónico y fecha de nacimiento (que no se le muestra a nadie).
- **Lo que creas** — viajes, paradas, notas, valoraciones y cualquier imagen que subas.
- **Tus conexiones** — a quién sigues, quién te sigue, a quién has bloqueado.
- **Datos de sesión** — lo justo para mantenerte con la sesión iniciada, y un identificador de dispositivo si activaste las notificaciones push.

A las imágenes subidas se les eliminan los metadatos EXIF, incluidas las coordenadas GPS del lugar donde se tomó una foto.""",
            ),
            Block(
                anchor="who-sees-it",
                heading="¿Quién puede ver lo que escribo?",
                kind=KIND_FAQ,
                body="""Quien diga tu [ajuste de visibilidad](/help/share-an-itinerary-privately), y nadie más. Un viaje puesto en **solo yo** lo ves tú y quien hayas invitado a editarlo.

Tu fecha de nacimiento nunca es visible para otro usuario, en ningún ajuste. Tu correo electrónico no aparece en tu perfil.""",
            ),
            Block(
                anchor="moderation",
                heading="¿Alguien en Ntripi lee mis viajes?",
                kind=KIND_FAQ,
                body="""No de forma rutinaria. Los textos y las imágenes se comprueban automáticamente al publicarse, y una persona solo mira algo cuando se denuncia o cuando esas comprobaciones lo marcan.

Las comprobaciones automáticas envían el contenido y nada más: ni identificador de usuario, ni correo, ni nombre.""",
            ),
            Block(
                anchor="deleting",
                heading="¿Cómo elimino mi cuenta?",
                kind=KIND_FAQ,
                body="""En la pantalla de edición de tu perfil, en Seguridad ▸ **Eliminar cuenta**. Lo confirmas con tu contraseña, o con Google si así inicias sesión.

La eliminación es permanente y se lleva tus viajes con ella. Los viajes que otras personas guardaron dejan de funcionar, ya que un marcador es un puntero y no una copia.""",
            ),
            Block(
                anchor="requests",
                heading="¿Cómo pido una copia de mis datos?",
                kind=KIND_FAQ,
                body="""Escribe a **[privacy@ntripi.app](mailto:privacy@ntripi.app)**. Esa dirección es el contacto de protección de datos que figura en la [política de privacidad](/privacy), y llega a las personas que pueden tramitar realmente una solicitud.

La misma dirección cubre las solicitudes de rectificación, limitación y oposición.""",
            ),
        ),
        keywords=(
            "privacidad",
            "datos",
            "rgpd",
            "eliminar cuenta",
            "borrar",
            "exportar",
            "datos personales",
            "rastreo",
            "anuncios",
            "publicidad",
            "quién puede ver",
        ),
        related=("permissions", "sign-in-and-account-security", "share-an-itinerary-privately"),
        updated="2026-09-01",
    ),
    Article(
        slug="sign-in-and-account-security",
        title="Iniciar sesión, contraseñas y eliminar tu cuenta",
        summary="Acceso con correo, Google o Apple, restablecer una contraseña, por qué algunas acciones exigen correo verificado y cómo marcharse.",
        category="account",
        schema=SCHEMA_FAQ,
        intro="Puedes iniciar sesión con un correo electrónico y una contraseña, con Google o con Apple. Las tres llegan a la misma cuenta, y puedes añadir una contraseña más tarde a una cuenta creada con Google.",
        blocks=(
            Block(
                anchor="forgot-password",
                heading="He olvidado mi contraseña",
                kind=KIND_FAQ,
                body="""Usa **He olvidado mi contraseña** en la pantalla de acceso. Llega un enlace de restablecimiento por correo y es válido durante un rato corto.

Si no llega nada, mira en la carpeta de spam y confirma que usas la dirección con la que te registraste. Si te registraste con Google, puede que no tengas contraseña: inicia sesión con Google.""",
            ),
            Block(
                anchor="verify-email",
                heading="¿Por qué no puedo crear un viaje, valorar o seguir?",
                kind=KIND_FAQ,
                body="""Esas tres cosas necesitan un correo verificado. Busca el enlace de verificación en tu bandeja de entrada, o usa el aviso de tu perfil para enviar otro.

Iniciar sesión con Google en la misma dirección también la verifica. El requisito es lo que mantiene las cuentas desechables fuera de las valoraciones y de las listas de seguidores.""",
            ),
            Block(
                anchor="changing-password",
                heading="¿Cómo cambio mi contraseña?",
                kind=KIND_FAQ,
                body="""Perfil ▸ editar ▸ **Seguridad ▸ Cambiar contraseña**. Lo confirmas con la actual.

Cambiarla cierra todas las **demás** sesiones y mantiene la que estás usando, así que si la cambias porque crees que alguien ha entrado, eso solo ya lo expulsa.""",
            ),
            Block(
                anchor="age",
                heading="¿Por qué me pide Ntripi la fecha de nacimiento?",
                kind=KIND_FAQ,
                body="""Ntripi tiene una edad mínima de **16 años**, y las [condiciones](/terms) lo dicen, lo que obliga a preguntarla en vez de darla por supuesta.

Nunca aparece en tu perfil ni es visible para otro usuario. Se pide una vez y no se vuelve a pedir.""",
            ),
            Block(
                anchor="suspended",
                heading="Mi cuenta está suspendida",
                kind=KIND_FAQ,
                body="""Habrás recibido un correo explicando por qué, con un enlace para recurrir. Los recursos los lee una persona.

Si ya no tienes el correo, el formulario de recurso puede enviarte un enlace nuevo. Consulta [contenido oculto y recursos](/help/hidden-content-and-appeals).""",
            ),
            Block(
                anchor="deleting",
                heading="¿Cómo elimino mi cuenta?",
                kind=KIND_FAQ,
                body="""Perfil ▸ editar ▸ **Seguridad ▸ Eliminar cuenta**, confirmado con tu contraseña o con Google.

Es permanente, y se lleva tus viajes con ella. Si solo quieres desaparecer de la vista, poner tus viajes en [solo yo](/help/share-an-itinerary-privately) y hacer privada tu cuenta es reversible, y eliminarla no.""",
            ),
        ),
        keywords=(
            "acceso",
            "iniciar sesión",
            "entrar",
            "contraseña",
            "contraseña olvidada",
            "restablecer",
            "google",
            "apple",
            "verificar",
            "verificación",
            "correo",
            "sin acceso",
            "eliminar cuenta",
            "edad",
            "16",
        ),
        related=("your-data-and-privacy", "troubleshooting"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-and-block",
        title="Cómo denunciar contenido o bloquear a alguien",
        summary="Marca un viaje, una reseña o un perfil que incumple las normas, y corta con alguien con quien preferirías no tratar.",
        category="safety",
        schema=SCHEMA_HOWTO,
        intro="Denunciar envía algo a moderación; bloquear elimina a una persona de tu experiencia. Son herramientas distintas y puedes usar las dos. Ninguna le dice a la otra persona lo que has hecho.",
        blocks=(
            Block(
                anchor="report",
                heading="Denunciar un viaje, una reseña o un perfil",
                kind=KIND_STEP,
                body="""Usa la acción de bandera sobre el propio elemento: un viaje, una parada, una reseña, una nota o un perfil. Elige un motivo y añade lo que pueda ayudar.

Denunciar desde el elemento lleva el contexto consigo, y por eso es mejor que enviarnos una descripción por correo. No necesitas cuenta para denunciar desde una página pública compartida.""",
            ),
            Block(
                anchor="reasons",
                heading="Elegir un motivo",
                body="""Los motivos son: material de abuso sexual infantil, contenido sexual, violencia o amenazas, discurso de odio, acoso, spam y otros.

Elige el más cercano: determina con qué urgencia se trata la denuncia. **Todo lo que implique a un menor recibe la máxima prioridad** y va a una cola aparte.""",
            ),
            Block(
                anchor="what-happens",
                heading="¿Qué pasa después de denunciar?",
                body="""Entra en la cola de moderación. El contenido denunciado por varias personas distintas, o corroborado por las comprobaciones automáticas, puede ocultarse de inmediato mientras una persona lo revisa.

Al autor nunca se le dice quién lo denunció. Normalmente no recibirás respuesta: el resultado es que el contenido se queda o se va.""",
            ),
            Block(
                anchor="block",
                heading="Bloquear a alguien",
                kind=KIND_STEP,
                body="""Desde su perfil, o manteniendo el dedo sobre algo que haya publicado.

Bloquear corta la visibilidad **en ambos sentidos**: dejas de verlo y deja de verte. Cualquier seguimiento entre vosotros se elimina. A esa persona no se le dice, y tu perfil pasa a ser para ella indistinguible de uno que nunca existió.""",
            ),
            Block(
                anchor="unblock",
                heading="Desbloquear a alguien",
                kind=KIND_STEP,
                body="""**Ajustes ▸ Cuentas bloqueadas** lista a todas las personas que has bloqueado, con un toque para revertirlo.

Desbloquear no restaura el seguimiento que el bloqueo eliminó: cualquiera de los dos puede volver a seguir si quiere.""",
            ),
            Block(
                anchor="urgent",
                heading="Si alguien está en peligro",
                body="""Contacta primero con los servicios de emergencia de tu zona. Ntripi no puede llegar a nadie lo bastante rápido como para ser la primera llamada adecuada.

Después escribe a **[abuse@ntripi.app](mailto:abuse@ntripi.app)**, que se vigila exactamente para esto.""",
            ),
        ),
        keywords=(
            "denunciar",
            "denuncia",
            "marcar",
            "bloquear",
            "abuso",
            "acoso",
            "spam",
            "inseguro",
            "inapropiado",
            "desbloquear",
            "seguridad",
        ),
        related=("hidden-content-and-appeals", "follow-and-private-accounts", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="hidden-content-and-appeals",
        title="Por qué se ocultó tu contenido, y cómo recurrir",
        summary="Qué significa que un viaje o una reseña esté oculto, dónde ver el motivo y cómo pedir que una persona lo revise otra vez.",
        category="safety",
        schema=SCHEMA_FAQ,
        intro="Si algo que publicaste se ocultó, recibes una notificación y un motivo, y **Ajustes ▸ Estado de la cuenta** guarda el registro. La mayoría de las decisiones se pueden recurrir, y un recurso lo lee una persona.",
        blocks=(
            Block(
                anchor="what-hidden-means",
                heading="¿Qué significa oculto?",
                kind=KIND_FAQ,
                body="""Nadie más puede abrirlo. **Tú sí**: sigue en tu lista con un aviso que explica por qué, y no se borra nada mientras un recurso sea posible.

Ocultar es reversible de una forma en que borrar no lo es, y por eso es el primer paso y no el último.""",
            ),
            Block(
                anchor="why",
                heading="¿Por qué se ocultó el mío?",
                kind=KIND_FAQ,
                body="""O bien lo denunciaron suficientes personas distintas, o una comprobación automática lo marcó, o un moderador decidió que incumple las [normas de la comunidad](/guidelines).

El motivo está en el aviso y en **Ajustes ▸ Estado de la cuenta**. Algunas ocultaciones son provisionales — aplicadas automáticamente mientras una persona llega a ellas — que es justo por lo que se pueden recurrir.""",
            ),
            Block(
                anchor="appealing",
                heading="¿Cómo recurro?",
                kind=KIND_FAQ,
                body="""**Ajustes ▸ Estado de la cuenta** lista cada decisión con un botón de recurso. Explica con tus palabras por qué crees que fue un error.

Un recurso abierto por decisión, y un intento por decisión en un mes: el límite existe para que la cola siga siendo lo bastante corta como para que los recursos se lean de verdad.""",
            ),
            Block(
                anchor="warnings",
                heading="Me han avisado pero no han ocultado nada",
                kind=KIND_FAQ,
                body="""Una advertencia es una anotación en tu cuenta sin que se retire nada. Es una señal, y también un registro: una segunda advertencia se anota como segunda, no se funde con la primera.

Las advertencias se pueden recurrir como todo lo demás.""",
            ),
            Block(
                anchor="suspended",
                heading="Toda mi cuenta está suspendida",
                kind=KIND_FAQ,
                body="""No puedes iniciar sesión, así que el recurso no puede vivir dentro de la aplicación. El correo de suspensión lleva un enlace a un formulario web; si ya no lo tienes, el formulario puede enviar un enlace nuevo a tu dirección.

Las suspensiones son reversibles, y un recurso que prospera restaura la cuenta en vez de reconstruirla.""",
            ),
            Block(
                anchor="after",
                heading="¿Qué pasa después de recurrir?",
                kind=KIND_FAQ,
                body="""Una persona lo lee y o bien restaura el contenido o bien mantiene la decisión, y se te dice cuál de las dos.

Si una decisión se revoca, el contenido vuelve tal como estaba: no se había borrado nada mientras tanto.""",
            ),
        ),
        keywords=(
            "oculto",
            "retirado",
            "eliminado",
            "retirada",
            "moderación",
            "recurso",
            "recurrir",
            "expulsado",
            "suspendido",
            "advertencia",
            "contenido bloqueado",
            "restaurado",
        ),
        related=("report-and-block", "sign-in-and-account-security", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="troubleshooting",
        title="Ntripi no funciona: problemas habituales y soluciones",
        summary="Los mensajes que más aparecen, qué significa cada uno en realidad y qué hacer a continuación.",
        category="troubleshooting",
        schema=SCHEMA_FAQ,
        intro="La mayoría de los problemas en Ntripi vienen de tres cosas: dos personas editando el mismo viaje, una conexión perdida, o un paso de la cuenta que aún no se ha completado. Busca abajo el mensaje que viste.",
        blocks=(
            Block(
                anchor="modified-please-reload",
                heading="«Este itinerario se ha modificado, recárgalo»",
                kind=KIND_FAQ,
                body="""El viaje cambió después de que tu pantalla lo cargara, normalmente porque lo tienes abierto en otro dispositivo o porque alguien a quien invitaste a editar guardó antes.

Recarga el viaje y vuelve a hacer tu cambio. Ntripi rechaza el guardado en vez de sobrescribir en silencio lo que llegó mientras escribías.""",
            ),
            Block(
                anchor="someone-else-is-editing",
                heading="«Alguien más está editando este viaje»",
                kind=KIND_FAQ,
                body="""Solo una persona puede editar un viaje a la vez. Otra persona — o tú, en otro dispositivo — lo tiene ahora mismo.

Espera a que termine, o toma el relevo si lleva un rato inactiva. Si eres el propietario, siempre puedes recuperarlo. Tomar el relevo termina la sesión de la otra persona, así que se le avisará en vez de perder trabajo en silencio.""",
            ),
            Block(
                anchor="lost-the-edit",
                heading="Estaba editando y ha dejado de dejarme guardar",
                kind=KIND_FAQ,
                body="""Alguien tomó el relevo del viaje mientras lo tenías abierto. **Lo que escribiste no se pierde**: la pantalla sigue exactamente igual, con todos los campos rellenos.

Tienes dos salidas, y las dos conservan tu trabajo: recupera el viaje y guarda, o copia tu texto y pégalo cuando la otra persona termine. No se descarta nada hasta que tú mismo sales de la pantalla.""",
            ),
            Block(
                anchor="image-rejected",
                heading="Mi foto se rechazó al subirla",
                kind=KIND_FAQ,
                body="""Las subidas se comprueban automáticamente antes de guardarse. Una imagen puede rechazarse por ser demasiado pequeña, por tener un formato no admitido, o por un contenido que no cumple las [normas de la comunidad](/guidelines).

Prueba con una imagen mayor, de al menos 600 píxeles en su lado más corto. Si crees que el rechazo fue un error, [ponte en contacto](/help/contact).""",
            ),
            Block(
                anchor="text-rejected",
                heading="Mi texto se rechazó al intentar guardarlo",
                kind=KIND_FAQ,
                body="""El texto que escribes se comprueba frente a las [normas de la comunidad](/guidelines) antes de guardarse.

También puedes ver un aviso discreto bajo un campo mientras escribes. Ese es solo una advertencia: nunca te bloquea y nunca cambia lo que escribiste. Los nombres de lugares en particular pueden activar una advertencia sin ser ningún problema.""",
            ),
            Block(
                anchor="cannot-create",
                heading="No puedo crear un viaje, valorar ni seguir a nadie",
                kind=KIND_FAQ,
                body="""Estas acciones necesitan un correo verificado. Busca el enlace de verificación en tu bandeja de entrada, o usa el aviso de tu perfil para enviar otro.

Iniciar sesión con Google en la misma dirección también la verifica.""",
            ),
            Block(
                anchor="offline",
                heading="Hay una barra que dice que estoy sin conexión",
                kind=KIND_FAQ,
                body="""Ntripi ha detectado que la conexión se ha caído. Puedes seguir leyendo todo lo ya cargado; los controles que necesitarían el servidor se atenúan hasta que vuelvas.

La barra desaparece sola cuando vuelve la conexión: no hay nada que tocar.""",
            ),
            Block(
                anchor="still-stuck",
                heading="Nada de esto coincide con lo que veo",
                kind=KIND_FAQ,
                body="Infórmalo desde la aplicación: **agita el teléfono** y Ntripi captura la pantalla para que puedas rodear el problema antes de enviarlo. Consulta [cómo contactarnos](/help/contact).",
            ),
        ),
        keywords=(
            "error",
            "problema",
            "problemas",
            "roto",
            "no funciona",
            "fallo",
            "fallando",
            "atascado",
            "no puedo guardar",
            "recargar",
            "sin conexión",
            "cierre inesperado",
            "fallo técnico",
            "arreglar",
            "ayuda",
        ),
        related=("contact", "getting-started"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-a-bug",
        title="Cómo informar de un fallo en Ntripi",
        summary="Agita el teléfono para capturar la pantalla, rodea lo que está mal y envíalo — o usa el botón en la web.",
        category="troubleshooting",
        schema=SCHEMA_HOWTO,
        intro="**Agita tu teléfono.** Ntripi captura la pantalla que estabas mirando, te da un lápiz para rodear el problema y lo envía con tu comentario. Es mucho más rápido que describir un diseño con palabras, y adjunta tu dispositivo y tu versión por ti.",
        blocks=(
            Block(
                anchor="shake",
                heading="Agitar el teléfono",
                kind=KIND_STEP,
                body="""En cualquier parte de la aplicación, en el momento en que algo se ve mal. Se captura una imagen de esa pantalla exacta.

Hacen falta dos sacudidas distintas, así que un paseo o un trayecto en autobús no lo activarán. También se ignora mientras la aplicación está en segundo plano, y espera unos segundos antes de poder dispararse de nuevo.""",
            ),
            Block(
                anchor="draw",
                heading="Rodear el problema",
                kind=KIND_STEP,
                body="""Dibuja directamente sobre la captura. Un círculo alrededor de lo que está mal elimina un párrafo entero de explicaciones.

Puedes navegar mientras el informador está abierto si necesitas capturar otra pantalla.""",
            ),
            Block(
                anchor="describe",
                heading="Elegir una categoría y describirlo",
                kind=KIND_STEP,
                body="""Elige entre: cierre inesperado, visual, datos, lentitud u otro. Después cuenta qué hiciste, qué esperabas y qué pasó.

No se envía nada hasta que tocas enviar.""",
            ),
            Block(
                anchor="what-is-sent",
                heading="Qué se envía con él",
                body="""Tu comentario, tu categoría, la captura de pantalla y detalles técnicos sobre el dispositivo y la versión de la aplicación: las cosas tediosas de escribir y que siempre son las primeras preguntas.

A la captura se le eliminan los metadatos como a cualquier otra subida. Nunca se le muestra a otro usuario, y los informes de fallos se borran cuando quedan cerrados y antiguos, porque una captura puede contener información de otra persona.""",
            ),
            Block(
                anchor="web-and-off",
                heading="En la web, o con el gesto desactivado",
                body="""Los navegadores no detectan sacudidas, así que en la web usa **Ajustes ▸ Soporte ▸ Informar de un fallo**, que abre el mismo informador.

Si desactivaste el gesto en el móvil, esa misma opción del menú sigue funcionando. Para volver a activarlo: **Ajustes ▸ Soporte ▸ Agitar para informar**.""",
            ),
        ),
        keywords=(
            "fallo",
            "fallos",
            "error",
            "informar",
            "roto",
            "cierre inesperado",
            "comentarios",
            "agitar",
            "captura de pantalla",
            "problema",
        ),
        related=("troubleshooting", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="contact",
        title="Cómo contactar con el soporte de Ntripi",
        summary="Dónde enviar un fallo, un problema de seguridad, una solicitud de privacidad o una pregunta general, y qué incluir.",
        category="about",
        schema=SCHEMA_CONTACT,
        intro="La forma más rápida de informar de un problema con la aplicación es **agitar el teléfono**: Ntripi captura la pantalla y te deja dibujar sobre ella antes de enviarla. Para todo lo demás, usa la dirección de abajo que corresponda a lo que necesitas.",
        blocks=(
            Block(
                anchor="report-a-bug",
                heading="Informar de un fallo desde la aplicación",
                body="""**Agita tu teléfono.** Ntripi hace una captura, te da un lápiz para rodear lo que está mal y te deja añadir un comentario y una categoría antes de enviarlo.

La captura va con el informe, lo que te ahorra describir un diseño con palabras. No se envía nada hasta que tocas enviar.

Puedes desactivar el gesto en **Ajustes ▸ Soporte ▸ Agitar para informar**. En la web no hay sacudida, así que usa **Ajustes ▸ Soporte ▸ Informar de un fallo**.""",
            ),
            Block(
                anchor="email-us",
                heading="Escríbenos",
                body="""- **[support@ntripi.app](mailto:support@ntripi.app)** — la aplicación está rota, o te has quedado atascado.
- **[abuse@ntripi.app](mailto:abuse@ntripi.app)** — contenido o conductas que incumplen las [normas de la comunidad](/guidelines), y cualquier cosa urgente sobre la seguridad de alguien.
- **[privacy@ntripi.app](mailto:privacy@ntripi.app)** — solicitudes de protección de datos, y todo lo que cubre la [política de privacidad](/privacy).
- **[contact@ntripi.app](mailto:contact@ntripi.app)** — todo lo demás.""",
            ),
            Block(
                anchor="what-to-include",
                heading="Qué incluir",
                body="""Un informe se atiende mucho más rápido con:

- **Qué hiciste**, en el orden en que lo hiciste.
- **Qué esperabas**, y qué pasó en su lugar.
- **Una captura de pantalla**, si el problema se ve.
- **Tu dispositivo y la versión de la aplicación** — el informador integrado los adjunta solo, una razón más para usarlo cuando puedas.""",
            ),
            Block(
                anchor="reporting-content",
                heading="Denunciar contenido en vez de un fallo",
                body="""Para denunciar algo que ha publicado otra persona, usa la acción de bandera sobre el propio viaje, reseña o perfil, y no el correo. Llega directamente a la cola de moderación y lleva el contexto consigo.

Las denuncias no se le muestran a la persona denunciada.""",
            ),
        ),
        keywords=(
            "soporte",
            "ayuda",
            "correo",
            "contacto",
            "comentarios",
            "fallo",
            "fallos",
            "informar",
            "abuso",
            "privacidad",
            "reclamación",
        ),
        related=("troubleshooting",),
        updated="2026-09-01",
    ),
    Article(
        slug="whats-new",
        title="Novedades de Ntripi",
        summary="Versiones recientes: qué se ha añadido, qué ha cambiado y qué se ha corregido.",
        category="about",
        schema=SCHEMA_RELEASES,
        intro="Ntripi está en desarrollo activo antes de su lanzamiento público. Cada versión de abajo indica qué ha cambiado y por qué puede importarte.",
        releases=RELEASES,
        keywords=(
            "registro de cambios",
            "notas de versión",
            "actualizaciones",
            "novedades",
            "versión",
            "cambios",
            "qué ha cambiado",
            "historial",
        ),
        related=("getting-started", "contact"),
        updated="2026-09-01",
    ),
)
