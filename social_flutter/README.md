# Ntripi — Flutter Frontend

Flutter mobile app for the Ntripi social travel platform.

## Project Structure

```
social_flutter/
└── lib/
    ├── main.dart                        ← Entry point, ProviderScope, MaterialApp.router
    ├── core/
    │   ├── api/
    │   │   ├── api_client.dart          ← Dio singleton + AuthInterceptor (attaches Bearer token)
    │   │   └── api_endpoints.dart       ← All URL constants
    │   ├── router/
    │   │   └── app_router.dart          ← go_router config: auth guard + ShellRoute + all routes
    │   ├── services/
    │   │   └── geocoding_service.dart   ← Nominatim place search (debounced, ODbL compliant)
    │   └── storage/
    │       └── secure_storage.dart      ← flutter_secure_storage wrapper (JWT token)
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
    │   │   │   ├── itinerary.dart
    │   │   │   ├── stop.dart
    │   │   │   ├── annotation.dart
    │   │   │   ├── transit_segment.dart
    │   │   │   ├── transport_leg.dart           ← TransportLeg + TransportMode enum
    │   │   │   ├── allowed_user.dart
    │   │   │   └── ratings_page.dart
    │   │   ├── presentation/
    │   │   │   ├── itinerary_list_screen.dart
    │   │   │   ├── itinerary_detail_screen.dart ← Full detail, edit mode, reorder
    │   │   │   ├── itinerary_form_screen.dart   ← Create / edit itinerary header
    │   │   │   ├── stop_form_screen.dart        ← Add / edit a stop
    │   │   │   ├── segment_form_screen.dart     ← Add / edit a transit segment
    │   │   │   ├── map_picker_screen.dart       ← OSM map coordinate picker
    │   │   │   ├── ratings_page_screen.dart     ← Community ratings list + distribution
    │   │   │   └── widgets/
    │   │   │       ├── stop_card.dart
    │   │   │       ├── segment_card.dart        ← Segment between two stops
    │   │   │       ├── leg_tile.dart            ← One leg row in segment form
    │   │   │       ├── leg_form_dialog.dart     ← Bottom sheet: add / edit a leg
    │   │   │       ├── transport_badge.dart     ← Mode chip shown on segment card
    │   │   │       └── annotation_chip.dart
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
- Delete own account (GDPR).

### Itineraries
- Create, edit, and delete itineraries with title, description, currency, visibility, and safety rating.
- Four visibility levels: **Public**, **Followers only**, **Restricted** (allowlist), **Only me**.
- Allowlist management for restricted itineraries.
- Pull-to-refresh on all itinerary screens.

### Stops
- Add stops to an itinerary with type (origin / waypoint / destination), place name, address, coordinates, place type, duration, cost, and notes.
- Place search via Nominatim (debounced, 400ms) or manual map picker.
- Insert a stop at any position (mid-list inserts shift existing stops up server-side).
- Edit and delete stops.
- **Duplicate stop detection**: live amber warning when the same place is entered twice; confirmation dialog before saving.
- Annotations per stop: advice / caution / avoid / info chips. Can be added before the stop is saved (queued locally, submitted after create).

### Transit Segments
- Add a transit segment between any two stops with one or more legs.
- **Duplicate segment detection**: if a segment already exists for the chosen stop pair, a dialog offers: Cancel / Discard new / Join (merge legs for review) / Replace.
- Edit segments (full replace of stop references + leg list).
- Delete segments.

### Transport Legs
- Each leg has: mode, line (transit modes only), direction, duration (h + min), cost, is_free, notes.
- Supported modes: Walk, Bus, Tram, Metro, Train, Taxi, Uber, Bike, Ferry, Car, Airplane.
- Line and Direction fields are only shown for transit modes (Bus, Tram, Metro, Train, Ferry, Airplane).
- Legs are always edited via the **segment PATCH** (full replacement), not via individual leg endpoints. The backend exposes per-leg endpoints for future non-Flutter consumers.

### Ratings
- Submit, update, or delete a 1–5 star rating for any itinerary you can view.
- Tapping the rating row opens the full ratings page with community average, star distribution chart, and individual rater list.

### Edit Mode (Itinerary Detail)
- Pencil button enters edit mode; **Save** button commits pending changes.
- Back button intercepted by `PopScope`: Stay / Discard / Save dialog when there are unsaved changes.
- Inline **+ Stop** and **+ Segment** separators between every pair of consecutive stops.
- **Reorder mode**: tap the reorder icon to switch to a drag-handle list (`ReorderableListView`). Reordering is deferred — positions are sent to the server only on Save.
- OSM map with stop markers and polyline, always visible.

---

## Navigation (go_router)

| Route                                         | Screen                        |
|-----------------------------------------------|-------------------------------|
| `/login`                                      | LoginScreen                   |
| `/register`                                   | RegisterScreen                |
| `/profile/me`                                 | MyProfileScreen (tab)         |
| `/profile/:userId`                            | UserProfileScreen             |
| `/profile/:userId/followers`                  | FollowListScreen              |
| `/profile/:userId/following`                  | FollowListScreen              |
| `/follow-requests`                            | FollowRequestsScreen          |
| `/search`                                     | SearchScreen (tab)            |
| `/itineraries`                                | ItineraryListScreen (tab)     |
| `/itineraries/new`                            | ItineraryFormScreen (create)  |
| `/itineraries/:id`                            | ItineraryDetailScreen         |
| `/itineraries/:id/edit`                       | ItineraryFormScreen (edit)    |
| `/itineraries/:id/stops/new`                  | StopFormScreen (create)       |
| `/itineraries/:id/stops/:stopId/edit`         | StopFormScreen (edit)         |
| `/itineraries/:id/segments/new`               | SegmentFormScreen (create)    |
| `/itineraries/:id/segments/:segmentId/edit`   | SegmentFormScreen (edit)      |
| `/itineraries/:id/ratings`                    | RatingsPageScreen             |
| `/map-picker`                                 | MapPickerScreen               |
| `/settings/delete-account`                    | DeleteAccountScreen           |

A `ShellRoute` wraps all protected routes with a persistent `BottomNavigationBar` (Search / Profile / Itineraries / Feed).

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

**Deferred reorder** — Stop drag-reordering accumulates in `_pendingOrder` locally and is only sent to the server when the user taps Save. All other stop/segment mutations commit immediately from their sub-screens.

**ReorderableListView isolation** — When reorder mode is active, the full `body` is replaced with a standalone `ReorderableListView` (no outer `CustomScrollView`), preventing gesture conflicts that would silently swallow drag events.

**`_pendingOrder` sync** — `ref.listen` keeps `_pendingOrder` consistent when sub-screens add or delete stops. The update is deferred with `addPostFrameCallback` to avoid calling `setState` during a provider build.

**Epsilon coordinate comparison** — Duplicate stop detection uses `0.0001°` (~11m) tolerance instead of exact equality, because Nominatim returns more decimal places than PostgreSQL `NUMERIC(9,6)` stores.

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

### Production (live backend)

No local backend needed. Uses the deployed Railway instance:
```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app
```

### Production builds

For release builds (iOS / Android / Web):
```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app
```

### Prerequisites
- Flutter 3.x (stable channel)
- Dart SDK (bundled with Flutter)
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
