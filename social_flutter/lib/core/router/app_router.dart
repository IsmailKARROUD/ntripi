import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/router/app_links.dart';
import 'package:ntripi/core/router/navigation_ext.dart';
import 'package:ntripi/core/storage/secure_storage.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ntripi/features/auth/presentation/forgot_password_screen.dart';
import 'package:ntripi/features/auth/presentation/login_screen.dart';
import 'package:ntripi/features/auth/presentation/register_screen.dart';
import 'package:ntripi/features/auth/presentation/splash_screen.dart';
import 'package:ntripi/features/auth/presentation/suspended_screen.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/features/feed/presentation/feed_screen.dart';
import 'package:ntripi/features/follows/presentation/follow_list_screen.dart';
import 'package:ntripi/features/follows/presentation/follow_requests_screen.dart';
import 'package:ntripi/features/help/presentation/about_screen.dart';
import 'package:ntripi/features/help/presentation/help_center_screen.dart';
import 'package:ntripi/features/help/presentation/report_bug_screen.dart';
import 'package:ntripi/features/notifications/presentation/notification_settings_screen.dart';
import 'package:ntripi/features/notifications/presentation/notifications_screen.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/stop_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/editors_screen.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/itinerary_unavailable_view.dart';
import 'package:ntripi/features/itineraries/presentation/map_picker_screen.dart';
import 'package:ntripi/features/itineraries/presentation/saved_itineraries_screen.dart';
import 'package:ntripi/features/itineraries/presentation/stop_form_screen.dart';
import 'package:ntripi/features/itineraries/domain/dimension_key.dart';
import 'package:ntripi/features/itineraries/presentation/dimension_ratings_screen.dart';
import 'package:ntripi/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:ntripi/features/profile/presentation/account_status_screen.dart';
import 'package:ntripi/features/reports/presentation/blocked_users_screen.dart';
import 'package:ntripi/features/profile/presentation/change_password_screen.dart';
import 'package:ntripi/features/profile/presentation/delete_account_screen.dart';
import 'package:ntripi/features/profile/presentation/profile_by_username_screen.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_unavailable_view.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/search/presentation/search_screen.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/profile_tab_icon.dart';

/// Routes that require no authentication check — the only screens a signed-out
/// user can be on, which is also how a notification tap knows to stand down.
///
/// /suspended is public because the interceptor clears the tokens before
/// landing there — without it the guard would immediately bounce a banned user
/// to /login.
const kPublicRoutes = [
  '/login',
  '/register',
  '/splash',
  '/forgot-password',
  '/suspended',
];

// Typed, not inferred: the redirect asks the router itself whether anything is
// on screen yet, and an inferred type would depend on its own initializer.
final GoRouter appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/splash',
  // A shared link that arrives while the app is running opens over the screen
  // the user is on, or waits for splash or a sign-in — see app_links.dart.
  onEnter: appLinkOnEnter(),
  redirect: (context, state) async {
    // A shared link that launched the app goes through splash first.
    final launch = appLinkLaunchRedirect(state);
    if (launch != null) return launch;

    // The app never starts on an editing form — on the web, a reload or a
    // pasted address could start it anywhere.
    final landing = editingRouteLaunchRedirect(appRouter, state);
    if (landing != null) return landing;

    final hasAuth = await hasLiveRefreshToken();
    final isPublic = kPublicRoutes.contains(state.matchedLocation);

    // A trip or a profile waits through the sign-in, like a shared link.
    if (!hasAuth && !isPublic) return signInRedirect(state.uri);
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

    // Terminal screen for a suspended account — pushed by AuthInterceptor when
    // any response carries the account_deactivated code.
    GoRoute(
      path: '/suspended',
      builder: (context, state) => const SuspendedScreen(),
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
        // Branch 0 — Feed (public discovery feed)
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
          ],
        ),

        // Branch 1 — Search
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

        // Branch 4 — Own profile
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
              path: '/settings/account-status',
              builder: (_, __) => const AccountStatusScreen(),
            ),
            GoRoute(
              path: '/settings/blocked-users',
              builder: (_, __) => const BlockedUsersScreen(),
            ),
            GoRoute(
              path: '/follow-requests',
              builder: (_, __) => const FollowRequestsScreen(),
            ),
            GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen(),
            ),
            GoRoute(
              path: '/settings/notifications',
              builder: (_, __) => const NotificationSettingsScreen(),
            ),
            GoRoute(
              path: '/settings/help',
              builder: (_, __) => const HelpCenterScreen(),
            ),
            GoRoute(
              path: '/settings/help/report-bug',
              builder: (_, __) => const ReportBugScreen(),
            ),
            GoRoute(
              path: '/settings/about',
              builder: (_, __) => const AboutScreen(),
            ),
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
      // Owner-only in practice — the screen is only reachable from the owner's
      // own edit form, and every endpoint behind it is owner-gated server-side.
      path: '/itineraries/:id/editors',
      parentNavigatorKey: navigatorKey,
      builder: (_, s) => EditorsScreen(itineraryId: s.pathParameters['id']!),
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
    // Listed AFTER StatefulShellRoute so /profile/me in Branch 4 is matched
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

    // Where shared links land (see app_links.dart). A profile link names a
    // handle, so it resolves to an id before it is the profile screen.
    GoRoute(
      path: '/u/:username',
      parentNavigatorKey: navigatorKey,
      builder:
          (_, s) => ProfileByUsernameScreen(
            username: s.pathParameters['username']!,
          ),
    ),
    // A link to /share/i/ or /share/u/ that cannot name anything — cut short
    // when it was copied. The same "not available" answer as a deleted target,
    // and nothing is fetched.
    GoRoute(
      path: '/unavailable/:kind',
      parentNavigatorKey: navigatorKey,
      builder:
          (context, s) => Scaffold(
            backgroundColor: context.nt.surface,
            body: s.pathParameters['kind'] == 'profile'
                ? ProfileUnavailableView(
                    onBack: () => context.popOr('/profile/me'),
                  )
                : ItineraryUnavailableView(
                    reason: ItineraryUnavailable.notAvailable,
                    onBack: () => context.popOr('/profile/me'),
                  ),
          ),
    ),
  ],
);

/// The shell on its own, so a test can pin its keyboard contract without the
/// whole router (whose redirect reads secure storage).
@visibleForTesting
Widget appShellForTesting(StatefulNavigationShell navigationShell) =>
    _AppShell(navigationShell: navigationShell);

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
    // TosGate's gate: it already loads the profile app-wide, so this costs no request.
    final signedIn = ref.watch(hasSessionProvider).value ?? false;
    final avatarUrl = signedIn
        ? ref.watch(myProfileProvider.select((p) => p.value?.avatarUrl))
        : null;
    final photo = avatarUrl == null || avatarUrl.isEmpty
        ? null
        : ref.watch(cachedImageProvider)(avatarUrl);
    return Scaffold(
      // Resizes (the default) to lift the tabs above the keyboard, and hands them
      // no keyboard inset — so a tab's own Scaffold has nothing left to lift.
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
            child: MediaQuery(
              // Built from this context, above the Scaffold, so the keyboard
              // inset it consumed must go too or every tab lifts a second time.
              data: MediaQuery.of(context)
                  .removePadding(
                    removeTop: _showDownloadBanner || isOffline,
                    removeBottom: true,
                  )
                  .removeViewInsets(removeBottom: true),
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
              icon: const Icon(Icons.dynamic_feed_outlined),
              activeIcon: const Icon(Icons.dynamic_feed),
              label: AppLocalizations.of(context)!.navFeed,
            ),
            BottomNavigationBarItem(
              // person_search, not plain search: this tab only searches users.
              icon: const Icon(Icons.person_search_outlined),
              activeIcon: const Icon(Icons.person_search),
              label: AppLocalizations.of(context)!.navSearch,
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
              icon: ProfileTabIcon(photo: photo),
              activeIcon: ProfileTabIcon(photo: photo, selected: true),
              label: AppLocalizations.of(context)!.navProfile,
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
