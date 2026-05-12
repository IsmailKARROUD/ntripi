// features/search/presentation/search_screen.dart — User search screen.
//
// Features:
//   - TextField at top (not a separate route — inline search bar).
//   - Results update as user types, debounced by 400ms.
//   - Each result shows avatar, display_name, username, lock icon if private.
//   - Tapping a result navigates to /profile/:userId.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Cancel any pending timer.
    _debounceTimer?.cancel();

    // Start a new timer. If the user types again within 400ms, this
    // timer is cancelled and restarted, so the API is only called after
    // the user pauses for 400ms.
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search users...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                    },
                  )
                : null,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: FieldHelpIcon(
              helpTitle: 'Search users',
              helpMessage:
                  'Find people by their @username or by their display name. Tap a result to view their profile.',
              size: 22,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: resultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              extractErrorMessage(error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (users) {
          if (_searchController.text.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Search for people to follow',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          if (users.isEmpty) {
            return const Center(
              child: Text('No users found.',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              return _SearchResultTile(user: users[index]);
            },
          );
        },
      ),
    ),),);
  }
}

class _SearchResultTile extends StatelessWidget {
  final User user;

  const _SearchResultTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: UserAvatar(avatarUrl: user.avatarUrl, radius: 22),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.nameForDisplay,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (user.isPrivate) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock, size: 14, color: Colors.grey.shade500),
          ],
        ],
      ),
      subtitle: Text(
        user.handle,
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Text(
        '${user.followersCount} followers',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      onTap: () {
        context.push('/profile/${user.id}');
      },
    );
  }
}
