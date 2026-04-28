import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
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
    final hasAuth = token != null && token.isNotEmpty;

    // Routes that require no authentication check
    const publicRoutes = ['/login', '/register', '/splash'];
    final isPublic = publicRoutes.contains(state.matchedLocation);

    if (!hasAuth && !isPublic) return '/login';
    if (hasAuth && (state.matchedLocation == '/login' ||
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
            dimension: DimensionKey.fromPath(state.pathParameters['dimension']!),
          ),
        ),
        GoRoute(
          path: '/itineraries/:id/stops/new',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return StopFormScreen(
              itineraryId: state.pathParameters['id']!,
              insertAfterPosition: extra?['insertAfterPosition'] as int?,
            );
          },
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
class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/search')) return 0;
    if (loc.startsWith('/profile/me')) return 1;
    if (loc.startsWith('/itineraries')) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
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
