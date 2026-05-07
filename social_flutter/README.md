# Ntripi — Flutter Frontend

Flutter mobile/web app for the Ntripi social travel platform.

## Project Structure

```
social_flutter/
└── lib/
    ├── main.dart                        ← Entry point, ProviderScope, MaterialApp.router
    ├── core/
    │   ├── api/
    │   │   ├── api_client.dart          ← Dio singleton + AuthInterceptor (attaches Bearer token, clears on 401)
    │   │   └── api_endpoints.dart       ← All URL constants
    │   ├── router/
    │   │   └── app_router.dart          ← go_router config: auth guard + ShellRoute + all routes
    │   ├── services/
    │   │   └── geocoding_service.dart   ← Nominatim place search (debounced, ODbL compliant)
    │   ├── storage/
    │   │   └── secure_storage.dart      ← flutter_secure_storage wrapper (JWT token)
    │   └── ui/
    │       └── destructive_actions.dart ← Tier-1/2/3 destructive action helpers
    ├── features/
    │   ├── auth/
    │   │   └── presentation/
    │   │       ├── login_screen.dart
    │   │       └── register_screen.dart
    │   ├── follows/
    │   │   └── presentation/
    │   │       ├── follow_list_screen.dart      ← Followers / Following list
    │   │       └── follow_requests_screen.dart  ← Incoming pending follow requests
    │   ├── itineraries/
    │   │   ├── data/
    │   │   │   └── itinerary_repository.dart    ← All itinerary API calls
    │   │   ├── domain/
    │   │   │   ├── itinerary.dart               ← Itinerary model; derives StopType via _parseTracks()
    │   │   │   ├── track.dart                   ← Track model (ordered list of parallel stops)
    │   │   │   ├── stop.dart                    ← Stop model (trackId + rank; no position)
    │   │   │   ├── annotation.dart              ← Stop-level annotation model
    │   │   │   ├── itinerary_annotation.dart    ← Itinerary-level annotation model
    │   │   │   ├── transit_segment.dart
    │   │   │   ├── transport_leg.dart           ← TransportLeg + TransportMode enum (11 modes)
    │   │   │   ├── allowed_user.dart
    │   │   │   ├── my_rating.dart               ← Own rating (5 optional dimensions)
    │   │   │   ├── ratings_page.dart            ← Community ratings page model
    │   │   │   └── dimension_key.dart           ← DimensionKey enum (overall/safety/experience/accessibility/familyFriendly)
    │   │   ├── presentation/
    │   │   │   ├── itinerary_list_screen.dart
    │   │   │   ├── itinerary_detail_screen.dart ← Full detail, edit mode, reorder, inline stop/segment add
    │   │   │   ├── itinerary_form_screen.dart   ← Create / edit itinerary header + cover image upload
    │   │   │   ├── stop_form_screen.dart        ← Add / edit a stop (trackId, afterStopId, afterTrackId, beforeTrackId)
    │   │   │   ├── segment_form_screen.dart     ← Add / edit a transit segment
    │   │   │   ├── map_picker_screen.dart       ← OSM map coordinate picker
    │   │   │   ├── ratings_page_screen.dart     ← Community ratings list + star distribution
    │   │   │   ├── dimension_ratings_screen.dart← Per-dimension rating list (safety / experience / …)
    │   │   │   └── widgets/
    │   │   │       ├── stop_card.dart
    │   │   │       ├── parallel_stop_group.dart ← Renders stops within a track as swipeable pages
    │   │   │       ├── segment_card.dart        ← Segment between two stops
    │   │   │       ├── leg_tile.dart            ← One leg row in segment form
    │   │   │       ├── leg_form_dialog.dart     ← Bottom sheet: add / edit a leg
    │   │   │       ├── transport_badge.dart     ← Mode chip shown on segment card
    │   │   │       ├── annotation_chip.dart     ← Single annotation chip (advice/caution/avoid/info)
    │   │   │       ├── annotation_form_dialog.dart ← Bottom sheet: add / edit an annotation
    │   │   │       ├── cover_image_field.dart   ← Cover image picker + upload widget
    │   │   │       ├── rate_itinerary_dialog.dart  ← Rating dialog (overall + 4 optional dimensions)
    │   │   │       └── itinerary_summary_card.dart ← Card used on list and profile screens
    │   │   └── providers/
    │   │       └── itinerary_providers.dart     ← All Riverpod notifiers for itineraries
    │   ├── profile/
    │   │   ├── presentation/
    │   │   │   ├── my_profile_screen.dart
    │   │   │   ├── user_profile_screen.dart
    │   │   │   └── delete_account_screen.dart
    │   │   └── providers/
    │   │       └── profile_provider.dart
    │   └── search/
    │       └── presentation/
    │           └── search_screen.dart
    └── shared/
        ├── models/
        │   ├── user.dart
        │   └── follow.dart
        └── widgets/
            ├── follow_button.dart    ← 3-state Follow / Following / Requested
            └── user_avatar.dart
```

---

## Features

### Authentication
- Register and login with JWT stored securely in `flutter_secure_storage`.
- Auth guard in go_router redirects unauthenticated users to `/login`.
- 401 from the API clears the token and redirects to login automatically.

### Profile & Social
- View and edit own profile (display name, bio, avatar).
- View other users' public profiles with follow status.
- Hybrid follow system: public accounts auto-accept, private accounts create pending requests.
- Manage incoming follow requests (accept / reject).
- Browse followers and following lists.
- Delete own account (type-to-confirm + password re-entry).

### Itineraries
- Create, edit, and delete itineraries with title, description, currency, visibility, and cover image.
- **Cover image upload**: pick an image from the gallery, upload it to the server; processed server-side (Pillow resize + EXIF strip + 1200×630 cover-fit crop).
- Four visibility levels: **Public**, **Followers only**, **Restricted** (allowlist), **Only me**.
- Allowlist management for restricted itineraries.
- **Itinerary-level notes**: add trip-wide annotations (advice/caution/avoid/info) shown in a "Notes" section between description and ratings. Separate from per-stop annotations.
- Pull-to-refresh on all itinerary screens.

### Stops
- Add stops to an itinerary with place name, address, coordinates, place type, duration, cost, and notes.
- **Stop role is derived from track position** — the first track is always the origin, the last track is always the arrival, and all tracks in between are waypoints. Computed client-side in `Itinerary._parseTracks()`; no `type` field in the UI or API.
- **Tracks**: each track holds one or more parallel alternative stops (e.g. two hotel options for the same night). Tracks and stops within a track are ordered by fractional-index `rank` strings. Rendered by `ParallelStopGroup` as swipeable pages.
- **ETag / If-Match**: the repository tracks the itinerary's `updatedAt` and sends it as the `If-Match` header on every mutation. On 412 (stale), `ItineraryStaleException` is thrown and a reload dialog is shown.
- Place search via Nominatim (debounced 400ms) or manual map picker.
- Insert a stop in any track or create a new track at any position.
- Edit and delete stops (deleting the last stop in a track also deletes the track).
- **Duplicate stop detection**: live amber warning when the same place is entered twice (uses ≤0.0001° coordinate tolerance); confirmation dialog before saving.
- Annotations per stop: advice / caution / avoid / info chips. Can be queued before the stop is saved.

### Transit Segments
- Add a transit segment between any two stops with one or more legs.
- **Add the first leg directly** from the detail screen without navigating to the segment form first.
- **Duplicate segment detection**: if a segment already exists for the chosen stop pair, a dialog offers: Cancel / Discard new / Join (merge legs for review) / Replace.
- Edit segments (full replace of stop references + leg list).
- Delete segments.
- Segment controls are accessible directly from the itinerary detail screen (no need to navigate into edit sub-screens for common actions).

### Transport Legs
- Each leg has: mode, line (transit modes only), direction, duration (h + min), cost, is_free, notes.
- 11 modes: Walk, Bus, Tram, Metro, Train, Taxi, Uber, Bike, Ferry, Car, Airplane.
- Line and Direction fields shown only for transit modes (Bus, Tram, Metro, Train, Ferry, Airplane).
- Legs are always edited via segment PATCH (full replacement) — the Flutter app never calls individual leg endpoints.

### Ratings
- Submit or update a rating with 1–5 stars for the **overall** dimension (required) plus four optional dimensions: **safety**, **experience**, **accessibility**, **family-friendly**.
- Delete own rating at any time.
- Tapping the rating row opens the full `RatingsPageScreen` with community average, star distribution chart, and individual rater list.
- Each dimension has a dedicated `DimensionRatingsScreen` (reachable from the ratings page) showing the filtered list and per-dimension average. Dimension scores use color-coded stars (green ≥ 4, amber ≥ 3, red < 3).
- Dimension averages are only displayed when at least 3 users have rated that dimension.

### Edit Mode (Itinerary Detail)
- Pencil button enters edit mode; **Done** (✓) button exits.
- Back button intercepted by `PopScope` — exits edit mode.
- Inline **+ Stop** (creates new track) and **+ // stop** (adds to same track) buttons.
- **Segment orphan warning**: inserting a new track between two tracks that share a transit segment prompts the user to delete the segment before proceeding — it would otherwise become invisible.
- OSM map with stop markers and polyline (toggle show/hide).

---

## Navigation (go_router)

| Route                                              | Screen                           |
|----------------------------------------------------|----------------------------------|
| `/login`                                           | LoginScreen                      |
| `/register`                                        | RegisterScreen                   |
| `/profile/me`                                      | MyProfileScreen (tab)            |
| `/profile/:userId`                                 | UserProfileScreen                |
| `/profile/:userId/followers`                       | FollowListScreen                 |
| `/profile/:userId/following`                       | FollowListScreen                 |
| `/follow-requests`                                 | FollowRequestsScreen             |
| `/search`                                          | SearchScreen (tab)               |
| `/itineraries`                                     | ItineraryListScreen (tab)        |
| `/itineraries/new`                                 | ItineraryFormScreen (create)     |
| `/itineraries/:id`                                 | ItineraryDetailScreen            |
| `/itineraries/:id/edit`                            | ItineraryFormScreen (edit)       |
| `/itineraries/:id/stops/new`                       | StopFormScreen (create)          |
| `/itineraries/:id/stops/:stopId/edit`              | StopFormScreen (edit)            |
| `/itineraries/:id/segments/new`                    | SegmentFormScreen (create)       |
| `/itineraries/:id/segments/:segmentId/edit`        | SegmentFormScreen (edit)         |
| `/itineraries/:id/ratings`                         | RatingsPageScreen                |
| `/itineraries/:id/ratings/:dimension`              | DimensionRatingsScreen           |
| `/map-picker`                                      | MapPickerScreen                  |
| `/settings/delete-account`                         | DeleteAccountScreen              |

A `ShellRoute` wraps all protected routes with a persistent `BottomNavigationBar`.
`:dimension` is one of: `overall`, `safety`, `experience`, `accessibility`, `family_friendly`.

---

## Architecture

| Concern        | Solution                                                                      |
|----------------|-------------------------------------------------------------------------------|
| State          | Riverpod (`AsyncNotifierProvider`, `FamilyAsyncNotifier`)                     |
| Navigation     | go_router with auth redirect guard                                            |
| HTTP           | Dio with `AuthInterceptor` (attaches `Bearer` token, clears on 401)           |
| Secure storage | flutter_secure_storage (JWT token)                                            |
| Maps           | flutter_map + OpenStreetMap tiles (ODbL attribution always visible)           |
| Geocoding      | Nominatim (400ms debounce to respect 1 req/s rate limit)                      |

### Key design patterns

**Tracks as first-class model** — `Itinerary.tracks` is a `List<Track>`, each containing a `List<Stop>` already sorted by `rank` (server pre-sorts). The detail screen iterates over tracks, not a flat stop list. `StopType` is assigned per track index: first = origin, last = arrival, rest = waypoint.

**ETag on every mutation** — `ItineraryDetailNotifier._etag` reads `state.value?.eTag` and passes it to every repository call. On 412, the repository throws `ItineraryStaleException`; the presentation layer catches it and shows a "reload" dialog.

**Immediate commit** — All stop/segment mutations commit to the server immediately from their sub-screens. There is no deferred reorder queue.

**Epsilon coordinate comparison** — Duplicate stop detection uses `0.0001°` (~11m) tolerance instead of exact equality, because Nominatim returns more decimal places than PostgreSQL `NUMERIC(9,6)` stores.

**Segment orphan guard** — `onAddStopAfter` in the detail screen checks whether a segment connects the current track to the next. If one is found, a confirmation dialog prompts to delete it before inserting the new track.

**Destructive action tiers** — Never call `showDialog` directly for destructive actions. Use:
- `showUndoableActionSnackbar()` (Tier 1 — undo snackbar)
- `confirmDestructiveAction()` (Tier 2 — simple confirmation)
- `confirmTypedDestructiveAction()` (Tier 3 — type-to-confirm)

---

## Running the App

### Development (local backend)

Backend must be running at `http://localhost:8000`:
```bash
cd ../social_api
source venv/bin/activate
PYTHONPATH=. uvicorn app.main:app --reload
```

Flutter:
```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SHARE_BASE_URL=http://localhost:8000
```

Or use `scripts/dev.sh`.

### Production (live backend)

No local backend needed:
```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app
```

Or use `scripts/prod.sh`.

### Prerequisites
- Flutter 3.x (stable channel), Dart SDK bundled
- Android Studio / Xcode for simulators, or a physical device

```bash
cd social_flutter
flutter pub get
```

---

## Dependencies (key packages)

| Package                  | Purpose                                    |
|--------------------------|--------------------------------------------|
| flutter_riverpod         | State management                           |
| go_router                | Declarative navigation + auth guard        |
| dio                      | HTTP client with interceptors              |
| flutter_secure_storage   | Secure JWT storage                         |
| flutter_map              | OSM tile map rendering                     |
| latlong2                 | LatLng type for flutter_map                |
| image_picker             | Gallery / camera image selection           |
| share_plus               | Native share sheet for share links         |
