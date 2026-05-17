// features/search/presentation/search_screen.dart — User search screen.
//
// Editorial redesign — matches the visual language of follow_list_screen:
//   · kSand background, custom top bar (no AppBar).
//   · Inline search TextField with back button and clear button.
//   · Results grouped in SectionCard rows with AvatarInitials fallback.
//   · Editorial empty / no-results / error placeholders.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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
    setState(() {}); // refresh clear button visibility
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: kSurface,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: _SearchTopBar(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
              ),
              Container(height: 1, color: kBorder),
              Expanded(
                child: resultsAsync.when(
                  loading: () =>
                      const Center(child: NTripiCompassLoader()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        extractErrorMessage(error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kText2),
                      ),
                    ),
                  ),
                  data: (users) {
                    final l10n = AppLocalizations.of(context)!;
                    if (_searchController.text.isEmpty) {
                      return _EmptyStatePlaceholder(
                        icon: Icons.search_rounded,
                        message: l10n.searchForPeople,
                      );
                    }
                    if (users.isEmpty) {
                      return _EmptyStatePlaceholder(
                        icon: Icons.person_search_outlined,
                        message: l10n.noUsersFound,
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: [
                        SectionLabel(
                          icon: Icons.people_rounded,
                          label: l10n.searchResultsCount(users.length),
                        ),
                        SectionCard(
                          children: [
                            for (var i = 0; i < users.length; i++)
                              _SearchResultRow(
                                user: users[i],
                                isLast: i == users.length - 1,
                                onTap: () =>
                                    context.push('/profile/${users[i].id}'),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _SearchTopBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchTopBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.searchPeoplePlaceholder,
                  hintStyle: const TextStyle(
                    color: kText3,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: kBark,
                  letterSpacing: -0.2,
                ),
                onChanged: onChanged,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.playlist_remove_outlined),
              color: kBark,
              onPressed: onClear,
            ),
          FieldHelpIcon(
            helpTitle: AppLocalizations.of(context)!.navSearch,
            color: kBark,
            helpMessage: AppLocalizations.of(context)!.searchUsersHelp,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// ── Result row ────────────────────────────────────────────────────────────────

class _SearchResultRow extends StatelessWidget {
  final User user;
  final bool isLast;
  final VoidCallback onTap;

  const _SearchResultRow({
    required this.user,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                AvatarInitials(
                  name: user.nameForDisplay,
                  avatarUrl: user.avatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.nameForDisplay,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kBark,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          if (user.isPrivate) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.lock_rounded,
                                size: 13, color: kText3),
                          ],
                        ],
                      ),
                      Text(
                        user.handle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kText2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (user.followersCount > 0)
                        Text(
                          AppLocalizations.of(context)!.followerCountLabel(user.followersCount),
                          style: const TextStyle(fontSize: 11, color: kText3),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: kText3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsets.only(left: 70),
            color: kBorder,
          ),
      ],
    );
  }
}

// ── Empty / placeholder states ────────────────────────────────────────────────

class _EmptyStatePlaceholder extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyStatePlaceholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: kText3),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: kText2)),
        ],
      ),
    );
  }
}
