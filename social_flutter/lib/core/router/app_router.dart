// core/router/app_router.dart — go_router configuration.
//
// Route definitions:
//   /login                    → LoginScreen (public)
//   /register                 → RegisterScreen (public)
//   /settings/delete-account  → DeleteAccountScreen (requires auth)
//   /profile/me     → MyProfileScreen (requires auth) [tab: My Profile]
//   /profile/:id    → UserProfileScreen (requires auth)
//   /search         → SearchScreen (requires auth) [tab: Search]
//   /follow-requests → FollowRequestsScreen (requires auth)
//   /itineraries    → ItineraryListScreen (requires auth) [tab: Itineraries]
//   /itineraries/new             → ItineraryFormScreen (create)
//   /itineraries/:id             → ItineraryDetailScreen
//   /itineraries/:id/edit        → ItineraryFormScreen (edit)
//   /itineraries/:id/stops/new         → StopFormScreen (create)
//   /itineraries/:id/stops/:stopId/edit → StopFormScreen (edit)
//   /map-picker     → MapPickerScreen (lat/lng picker, returns PlaceSuggestion)
//
// Auth guard:
//   The redirect callback checks for a stored token.
//   Protected routes redirect to /login if no token is found.
//
// ShellRoute + BottomNavigationBar:
//   Four main tabs (Search, Profile, Itineraries, Feed) share a persistent
//   BottomNavigationBar using go_router's ShellRoute.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/features/auth/presentation/login_screen.dart';
import 'package:social_flutter/features/auth/presentation/register_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_list_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_requests_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/map_picker_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/segment_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/profile/presentation/delete_account_screen.dart';
import 'package:social_flutter/features/profile/presentation/my_profile_screen.dart';
import 'package:social_flutter/features/profile/presentation/user_profile_screen.dart';
import 'package:social_flutter/features/search/presentation/search_screen.dart';

/// Shared GoRouter instance.
final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/profile/me',

  // Redirect guard: check auth before allowing access to protected routes.
  redirect: (context, state) async {
    final token = await readToken();
    final hasAuth = token != null && token.isNotEmpty;

    final publicRoutes = ['/login', '/register'];
    final isPublicRoute = publicRoutes.contains(state.matchedLocation);

    if (!hasAuth && !isPublicRoute) {
      // Not authenticated, trying to access a protected route → redirect to login.
      return '/login';
    }

    if (hasAuth && isPublicRoute) {
      // Already authenticated, trying to visit login/register → skip to profile.
      return '/profile/me';
    }

    // No redirect needed.
    return null;
  },

  routes: [
    // Public routes (no shell / bottom nav bar)
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),

    // Protected routes with persistent BottomNavigationBar (ShellRoute)
    ShellRoute(
      builder: (context, state, child) {
        return _AppShell(child: child);
      },
      routes: [
        // My Profile tab
        GoRoute(
          path: '/profile/me',
          builder: (context, state) => const MyProfileScreen(),
        ),

        // Account deletion screen
        GoRoute(
          path: '/settings/delete-account',
          builder: (context, state) => const DeleteAccountScreen(),
        ),

        // Other user's profile (pushed on top, no bottom nav change)
        GoRoute(
          path: '/profile/:userId',
          builder: (context, state) {
            final userId = state.pathParameters['userId']!;
            return UserProfileScreen(userId: userId);
          },
        ),

        // Search tab
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),

        // Follow requests (navigated to from MyProfileScreen)
        GoRoute(
          path: '/follow-requests',
          builder: (context, state) => const FollowRequestsScreen(),
        ),

        // Followers list for any user
        GoRoute(
          path: '/profile/:userId/followers',
          builder: (context, state) => FollowListScreen(
            userId: state.pathParameters['userId']!,
            type: FollowListType.followers,
          ),
        ),

        // Following list for any user
        GoRoute(
          path: '/profile/:userId/following',
          builder: (context, state) => FollowListScreen(
            userId: state.pathParameters['userId']!,
            type: FollowListType.following,
          ),
        ),

        // ----------------------------------------------------------------
        // Itinerary routes
        // ----------------------------------------------------------------

        // My itineraries list (tab)
        GoRoute(
          path: '/itineraries',
          builder: (context, state) => const ItineraryListScreen(),
        ),

        // Create a new itinerary — must be BEFORE /itineraries/:id so
        // the literal 'new' is matched before the parameterized segment.
        GoRoute(
          path: '/itineraries/new',
          builder: (context, state) => const ItineraryFormScreen(),
        ),

        // Full itinerary detail
        GoRoute(
          path: '/itineraries/:id',
          builder: (context, state) => ItineraryDetailScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),

        // Edit itinerary header
        GoRoute(
          path: '/itineraries/:id/edit',
          builder: (context, state) => ItineraryFormScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),

        // Ratings page — must be before stops subroutes to avoid ambiguity
        GoRoute(
          path: '/itineraries/:id/ratings',
          builder: (context, state) => RatingsPageScreen(
            itineraryId: state.pathParameters['id']!,
          ),
        ),

        // Add a new stop — must be BEFORE stops/:stopId/edit
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

        // Edit an existing stop
        GoRoute(
          path: '/itineraries/:id/stops/:stopId/edit',
          builder: (context, state) => StopFormScreen(
            itineraryId: state.pathParameters['id']!,
            stopId: state.pathParameters['stopId']!,
          ),
        ),

        // Add a new segment — must be BEFORE segments/:segmentId/edit
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

        // Edit an existing segment
        GoRoute(
          path: '/itineraries/:id/segments/:segmentId/edit',
          builder: (context, state) => SegmentFormScreen(
            itineraryId: state.pathParameters['id']!,
            segmentId: state.pathParameters['segmentId']!,
          ),
        ),

        // Map picker — receives optional initial lat/lng via `extra`
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

/// Shell widget that wraps protected screens with a BottomNavigationBar.
class _AppShell extends StatelessWidget {
  final Widget child;

  const _AppShell({required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/search')) return 0;
    if (location.startsWith('/profile/me')) return 1;
    if (location.startsWith('/itineraries')) return 2;
    // Feed tab (placeholder) = index 3
    return 1; // Default to profile for unknown routes
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex(context),
        type: BottomNavigationBarType.fixed, // Required for 4+ items
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/search');
              break;
            case 1:
              context.go('/profile/me');
              break;
            case 2:
              context.go('/itineraries');
              break;
            case 3:
              // Feed tab — placeholder for future implementation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Feed coming soon!')),
              );
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Itineraries',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Feed',
          ),
        ],
      ),
    );
  }
}
