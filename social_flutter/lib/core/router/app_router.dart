// core/router/app_router.dart — go_router configuration.
//
// Route definitions:
//   /login          → LoginScreen (public)
//   /register       → RegisterScreen (public)
//   /profile/me     → MyProfileScreen (requires auth) [tab: My Profile]
//   /profile/:id    → UserProfileScreen (requires auth)
//   /search         → SearchScreen (requires auth) [tab: Search]
//   /follow-requests → FollowRequestsScreen (requires auth)
//
// Auth guard:
//   The redirect callback checks for a stored token.
//   Protected routes redirect to /login if no token is found.
//
// ShellRoute + BottomNavigationBar:
//   The three main tabs (Search, My Profile, Feed placeholder) share
//   a persistent BottomNavigationBar using go_router's ShellRoute.
//   Navigating between tabs preserves each tab's scroll position and state.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/features/auth/presentation/login_screen.dart';
import 'package:social_flutter/features/auth/presentation/register_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_list_screen.dart';
import 'package:social_flutter/features/follows/presentation/follow_requests_screen.dart';
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
    // Feed tab (placeholder) = index 2
    return 1; // Default to profile tab for unknown routes
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex(context),
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/search');
              break;
            case 1:
              context.go('/profile/me');
              break;
            case 2:
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
            icon: Icon(Icons.home_outlined),
            label: 'Feed',
          ),
        ],
      ),
    );
  }
}
