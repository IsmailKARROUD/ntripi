import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart'
    show ConnectivityResult, Connectivity;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:social_flutter/features/auth/presentation/login_screen.dart';
import 'package:social_flutter/features/auth/presentation/register_screen.dart';
import 'package:social_flutter/features/auth/presentation/splash_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_list_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_requests_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/map_picker_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/segment_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_form_screen.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/presentation/dimension_ratings_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/profile/presentation/delete_account_screen.dart';
import 'package:social_flutter/features/profile/presentation/my_profile_screen.dart';
import 'package:social_flutter/features/profile/presentation/user_profile_screen.dart';
import 'package:social_flutter/features/search/presentation/search_screen.dart';

final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) async {
    final token = await readToken();
    final hasAuth = token != null && token.isNotEmpty && !isJwtExpired(token);

    // Routes that require no authentication check
    const publicRoutes = ['/login', '/register', '/splash'];
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
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),

    // Public auth routes
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),

    // Protected routes with persistent bottom nav (ShellRoute)
    ShellRoute(
      builder: (context, state, child) => _AppShell(child: child),
      routes: [
        GoRoute(
          path: '/profile/me',
          builder: (context, state) => const MyProfileScreen(),
        ),
        GoRoute(
          path: '/settings/delete-account',
          builder: (context, state) => const DeleteAccountScreen(),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (context, state) =>
              UserProfileScreen(userId: state.pathParameters['userId']!),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/follow-requests',
          builder: (context, state) => const FollowRequestsScreen(),
        ),
        GoRoute(
          path: '/profile/:userId/followers',
          builder: (context, state) => FollowListScreen(
            userId: state.pathParameters['userId']!,
            type: FollowListType.followers,
          ),
        ),
        GoRoute(
          path: '/profile/:userId/following',
          builder: (context, state) => FollowListScreen(
            userId: state.pathParameters['userId']!,
            type: FollowListType.following,
          ),
        ),
        GoRoute(
          path: '/itineraries',
          builder: (context, state) => const ItineraryListScreen(),
        ),
        GoRoute(
          path: '/itineraries/new',
          builder: (context, state) => const ItineraryFormScreen(),
        ),
        GoRoute(
          path: '/itineraries/:id',
          builder: (context, state) => ItineraryDetailScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/edit',
          builder: (context, state) => ItineraryFormScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/ratings',
          builder: (context, state) => RatingsHubScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/ratings/:dimension',
          builder: (context, state) => DimensionRatingsScreen(
            itineraryId: state.pathParameters['id']!,
            dimension:
                DimensionKey.fromPath(state.pathParameters['dimension']!),
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/stops/new',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return StopFormScreen(
              itineraryId: state.pathParameters['id']!,
              trackId: extra?['trackId'] as String?,
              afterStopId: extra?['afterStopId'] as String?,
              afterTrackId: extra?['afterTrackId'] as String?,
              beforeTrackId: extra?['beforeTrackId'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/itineraries/:id/stops/:stopId',
          builder: (context, state) => StopFormScreen(
            itineraryId: state.pathParameters['id']!,
            stopId: state.pathParameters['stopId']!,
            viewOnly: true,
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/stops/:stopId/edit',
          builder: (context, state) => StopFormScreen(
            itineraryId: state.pathParameters['id']!,
            stopId: state.pathParameters['stopId']!,
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/segments/new',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return SegmentFormScreen(
              itineraryId: state.pathParameters['id']!,
              initialFromStopId: extra?['fromStopId'] as String?,
              initialToStopId: extra?['toStopId'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/itineraries/:id/segments/:segmentId/edit',
          builder: (context, state) => SegmentFormScreen(
            itineraryId: state.pathParameters['id']!,
            segmentId: state.pathParameters['segmentId']!,
          ),
        ),
        GoRoute(
          path: '/map-picker',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return MapPickerScreen(
              initialLat: extra?['lat'] as double?,
              initialLng: extra?['lng'] as double?,
            );
          },
        ),
      ],
    ),
  ],
);

/// Shell with persistent bottom navigation bar.
class _AppShell extends StatefulWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  // Shown only on the web build. Users reach the web app via "Continue on web"
  // on the marketing page, so we nudge them toward the native app once they're
  // inside. Dismissed for the session — intentionally not persisted so it
  // reappears on the next visit as a soft reminder.
  bool _showDownloadBanner = kIsWeb;
  bool _isOffline = false;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/search')) return 0;
    if (loc.startsWith('/profile/me')) return 1;
    if (loc.startsWith('/itineraries')) return 2;
    return 1;
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();

    // Reflect connectivity on cold launch — the stream only fires on changes.
    _checkInitialConnection();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none);
      });
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnection() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() {
      _isOffline = results.contains(ConnectivityResult.none);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_showDownloadBanner)
            _DownloadBanner(
                onDismiss: () => setState(() => _showDownloadBanner = false)),
          if (_isOffline) const _OfflineBanner(),
          // Banners above use SafeArea(bottom: false) and consume the top
          // status-bar inset. MediaQuery still reports that inset to the
          // child Scaffold's AppBar, which would re-add it and leave a gap
          // below the status bar. Strip the top inset when a banner shows.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: _showDownloadBanner || _isOffline,
              child: widget.child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE4EDE6))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex(context),
          elevation: 0,
          backgroundColor: Colors.white,
          selectedItemColor: kForest,
          unselectedItemColor: const Color(0xFF93A898),
          onTap: (i) {
            switch (i) {
              case 0:
                context.go('/search');
              case 1:
                context.go('/profile/me');
              case 2:
                context.go('/itineraries');
              case 3:
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feed coming soon!')),
                );
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.article_outlined),
              activeIcon: Icon(Icons.article),
              label: 'Itineraries',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dynamic_feed_outlined),
              activeIcon: Icon(Icons.dynamic_feed),
              label: 'Feed',
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
    return const ColoredBox(
      color: kRatingRed,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(left: 12, right: 12, top: 0, bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(
                'You\'re Offline! Some features may be unavailable.',
                style:
                    TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
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
    return ColoredBox(
      color: kForest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.smartphone, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'For a better experience, download the Ntripi app.',
                  style:
                      TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
              ),
              if (kAndroidDownloadUrl.isNotEmpty)
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kAndroidDownloadUrl),
                      mode: LaunchMode.externalApplication),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Download'),
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
