import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:social_flutter/features/auth/presentation/forgot_password_screen.dart';
import 'package:social_flutter/features/auth/presentation/login_screen.dart';
import 'package:social_flutter/features/auth/presentation/register_screen.dart';
import 'package:social_flutter/features/auth/presentation/splash_screen.dart';
import 'package:social_flutter/features/feed/presentation/feed_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_list_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_requests_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/map_picker_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/saved_itineraries_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_form_screen.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/presentation/dimension_ratings_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/profile/presentation/change_password_screen.dart';
import 'package:social_flutter/features/profile/presentation/delete_account_screen.dart';
import 'package:social_flutter/features/profile/presentation/profile_screen.dart';
import 'package:social_flutter/features/search/presentation/search_screen.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) async {
    // We check for a live refresh token, NOT an unexpired access token —
    // the access token is short-lived (15 min) and may legitimately be
    // expired between requests. As long as the refresh token is alive,
    // the session is alive; TokenManager handles the rotation on the
    // first API call.
    final refresh = await readRefreshToken();
    final refreshExp = await readRefreshExpiresAt();
    final hasAuth =
        refresh != null &&
        refresh.isNotEmpty &&
        (refreshExp == null || refreshExp.isAfter(DateTime.now()));

    // Routes that require no authentication check
    const publicRoutes = ['/login', '/register', '/splash', '/forgot-password'];
    final isPublic = publicRoutes.contains(state.matchedLocation);

    if (!hasAuth && !isPublic) return '/login';
    if (hasAuth &&
        (state.matchedLocation == '/login' ||
            state.matchedLocation == '/register')) {
      return '/profile/me';
    }

    return null;
  },
  routes: [
    // Splash — shown on cold launch, navigates to login or home
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),

    // Public auth routes
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),

    // Protected routes with persistent bottom nav.
    // StatefulShellRoute keeps each branch's widget tree alive in a separate
    // Navigator — switching tabs shows/hides rather than destroy/rebuild,
    // preserving search text, scroll positions, and loaded results.
    StatefulShellRoute.indexedStack(
      builder:
          (context, state, navigationShell) =>
              _AppShell(navigationShell: navigationShell),
      branches: [
        // Branch 0 — Search
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (_, __) => const SearchScreen(),
              routes: [
                // Nested so profile/follow-list push within the search branch
                // navigator, keeping the bottom bar visible.
                GoRoute(
                  path: 'profile/:userId',
                  builder:
                      (_, s) => ProfileScreen(
                        userId: s.pathParameters['userId']!,
                        profileBaseRoute: '/search/profile',
                      ),
                  routes: [
                    GoRoute(
                      path: 'followers',
                      builder:
                          (_, s) => FollowListScreen(
                            userId: s.pathParameters['userId']!,
                            type: FollowListType.followers,
                            profileBaseRoute: '/search/profile',
                          ),
                    ),
                    GoRoute(
                      path: 'following',
                      builder:
                          (_, s) => FollowListScreen(
                            userId: s.pathParameters['userId']!,
                            type: FollowListType.following,
                            profileBaseRoute: '/search/profile',
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Branch 1 — Own profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile/me',
              builder: (_, __) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/settings/change-password',
              builder: (_, __) => const ChangePasswordScreen(),
            ),
            GoRoute(
              path: '/settings/delete-account',
              builder: (_, __) => const DeleteAccountScreen(),
            ),
            GoRoute(
              path: '/follow-requests',
              builder: (_, __) => const FollowRequestsScreen(),
            ),
          ],
        ),

        // Branch 2 — Itineraries
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/itineraries',
              builder: (_, __) => const ItineraryListScreen(),
            ),
            // NOTE: the itinerary detail / form / stop / map-picker routes are
            // deliberately NOT nested here. They live at the root level (below,
            // next to /profile/:userId) so they render full-screen on the root
            // navigator. Nesting them in this branch made pushing them from a
            // root-level page (e.g. another user's profile, also root) place a
            // SECOND copy of the shell page on the root navigator → duplicate
            // page-key assertion → the navigator wedges and the app freezes
            // (ANR). go_router also forbids a branch sub-route from carrying a
            // root parentNavigatorKey, so escaping requires living at the root.
          ],
        ),

        // Branch 3 — Saved (bookmarked itineraries)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/saved',
              builder: (_, __) => const SavedItinerariesScreen(),
            ),
          ],
        ),

        // Branch 4 — Feed (public discovery feed)
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
          ],
        ),
      ],
    ),

    // Itinerary detail / form / stop / map-picker routes at the root level
    // (parentNavigatorKey) so they render full-screen on the root navigator and
    // can be pushed from ANY context — including root-level pages like another
    // user's profile — without duplicating the shell page. See the note in
    // Branch 2. /itineraries/new is listed before /itineraries/:id so the
    // literal "new" segment wins over the :id wildcard.
    GoRoute(
      path: '/itineraries/new',
      parentNavigatorKey: navigatorKey,
      builder: (_, __) => const ItineraryFormScreen(),
    ),
    GoRoute(
      path: '/itineraries/:id',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return ItineraryDetailScreen(
          itineraryId: s.pathParameters['id']!,
          justCreated: extra?['justCreated'] as bool? ?? false,
        );
      },
    ),
    GoRoute(
      path: '/itineraries/:id/edit',
      parentNavigatorKey: navigatorKey,
      builder:
          (_, s) => ItineraryFormScreen(itineraryId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/itineraries/:id/ratings',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => RatingsHubScreen(itineraryId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/itineraries/:id/ratings/:dimension',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => DimensionRatingsScreen(
        itineraryId: s.pathParameters['id']!,
        dimension: DimensionKey.fromPath(s.pathParameters['dimension']!),
      ),
    ),
    GoRoute(
      path: '/itineraries/:id/stops/new',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return StopFormScreen(
          itineraryId: s.pathParameters['id']!,
          trackId: extra?['trackId'] as String?,
          afterStopId: extra?['afterStopId'] as String?,
          afterTrackId: extra?['afterTrackId'] as String?,
          beforeTrackId: extra?['beforeTrackId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/itineraries/:id/stops/:stopId',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => StopDetailScreen(
        itineraryId: s.pathParameters['id']!,
        stopId: s.pathParameters['stopId']!,
      ),
    ),
    GoRoute(
      path: '/itineraries/:id/stops/:stopId/edit',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => StopFormScreen(
        itineraryId: s.pathParameters['id']!,
        stopId: s.pathParameters['stopId']!,
      ),
    ),
    GoRoute(
      path: '/map-picker',
      parentNavigatorKey: navigatorKey,
      // Fade+scale instead of a Hero: transforms only repaint, while a
      // Hero flight relayouts the live map every frame (froze on device).
      pageBuilder: (_, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return CustomTransitionPage(
          key: s.pageKey,
          child: MapPickerScreen(
            initialLat: extra?['lat'] as double?,
            initialLng: extra?['lng'] as double?,
            deviceLat: extra?['deviceLat'] as double?,
            deviceLng: extra?['deviceLng'] as double?,
          ),
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        );
      },
    ),

    // Other-user profile routes at the root level with parentNavigatorKey so
    // they push on the root navigator (full-screen) rather than inside a branch.
    // Listed AFTER StatefulShellRoute so /profile/me in Branch 1 is matched
    // first — this avoids the /profile/:userId wildcard catching "me".
    GoRoute(
      path: '/profile/:userId',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => ProfileScreen(userId: s.pathParameters['userId']!),
    ),
    GoRoute(
      path: '/profile/:userId/followers',
      parentNavigatorKey: navigatorKey,
      builder:
          (_, s) => FollowListScreen(
            userId: s.pathParameters['userId']!,
            type: FollowListType.followers,
          ),
    ),
    GoRoute(
      path: '/profile/:userId/following',
      parentNavigatorKey: navigatorKey,
      builder:
          (_, s) => FollowListScreen(
            userId: s.pathParameters['userId']!,
            type: FollowListType.following,
          ),
    ),
  ],
);

/// Shell with persistent bottom navigation bar.
class _AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const _AppShell({required this.navigationShell});

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  // Shown only on the web build. Users reach the web app via "Continue on web"
  // on the marketing page, so we nudge them toward the native app once they're
  // inside. Dismissed for the session — intentionally not persisted so it
  // reappears on the next visit as a soft reminder.
  bool _showDownloadBanner = kIsWeb;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    // Single source of truth for connectivity — see ConnectivityService.
    // Default to "online" while the stream is still seeding (optimistic).
    final isOffline =
        !ref
            .watch(isOnlineProvider)
            .maybeWhen(data: (online) => online, orElse: () => true);
    return Scaffold(
      // resizeToAvoidBottomInset: true (default) — the outer scaffold shrinks its
      // body to exactly the space above the keyboard. Inner screens use false so
      // they simply fill this pre-shrunk space without double-counting.
      body: Column(
        children: [
          if (_showDownloadBanner)
            _DownloadBanner(
              onDismiss: () => setState(() => _showDownloadBanner = false),
            ),
          if (isOffline) const _OfflineBanner(),
          // Banners above use SafeArea(bottom: false) and consume the top
          // status-bar inset. MediaQuery still reports that inset to the
          // child Scaffold's AppBar, which would re-add it and leave a gap
          // below the status bar. Strip the top inset when a banner shows.
          // removeBottom: the BottomNavigationBar already reserves the home-
          // indicator inset; without this the child SafeArea re-adds it and
          // leaves an empty strip of surface above the bar.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: _showDownloadBanner || isOffline,
              removeBottom: true,
              child: widget.navigationShell,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: nt.surface,
          border: Border(top: BorderSide(color: nt.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: widget.navigationShell.currentIndex,
          elevation: 0,
          backgroundColor: nt.surface,
          selectedItemColor: nt.forest,
          unselectedItemColor: nt.text3,
          onTap: (i) {
            widget.navigationShell.goBranch(
              i,
              // Tapping the active tab resets its navigation stack.
              initialLocation: i == widget.navigationShell.currentIndex,
            );
          },
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.search_outlined),
              activeIcon: const Icon(Icons.search),
              label: AppLocalizations.of(context)!.navSearch,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded),
              activeIcon: const Icon(Icons.person_rounded),
              label: AppLocalizations.of(context)!.navProfile,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.article_outlined),
              activeIcon: const Icon(Icons.article),
              label: AppLocalizations.of(context)!.navItineraries,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bookmark_border),
              activeIcon: const Icon(Icons.bookmark),
              label: AppLocalizations.of(context)!.navSaved,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.dynamic_feed_outlined),
              activeIcon: const Icon(Icons.dynamic_feed),
              label: AppLocalizations.of(context)!.navFeed,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // onError, not white — dark mode lightens the red, so the fg must darken
    final onError = Theme.of(context).colorScheme.onError;
    return ColoredBox(
      color: nt.ratingRed,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            end: 12,
            top: 0,
            bottom: 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: onError, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.offlineBanner,
                  style: TextStyle(color: onError, fontSize: 13, height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _DownloadBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    // onPrimary, not white — dark mode lightens the green fill
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return ColoredBox(
      color: nt.forest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.smartphone, color: onPrimary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.downloadBanner,
                  style: TextStyle(color: onPrimary, fontSize: 13, height: 1.4),
                ),
              ),
              if (kAndroidDownloadUrl.isNotEmpty)
                TextButton(
                  onPressed:
                      () => launchUrl(
                        Uri.parse(kAndroidDownloadUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                  style: TextButton.styleFrom(
                    foregroundColor: onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.downloadBannerButton,
                  ),
                ),
              IconButton(
                icon: Icon(Icons.close, color: onPrimary, size: 18),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: AppLocalizations.of(context)!.dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
