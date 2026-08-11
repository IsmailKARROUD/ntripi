// features/reports/presentation/blocked_users_screen.dart
//
// The list of accounts the user has blocked, with a one-tap unblock. App-store
// reviewers look for this specifically: a block you cannot find and lift is not
// considered a real blocking feature.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: nt.surface,
      appBar: AppBar(title: Text(l10n.blockedUsers)),
      body: blocked.when(
        loading: () => const Center(child: NTripiRingLoader()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.couldNotLoadItineraries,
              style: TextStyle(color: nt.text2),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.blockedUsersEmpty,
                  style: TextStyle(color: nt.text2),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, indent: 72, color: nt.border),
            itemBuilder: (context, index) {
              final user = users[index];
              return _BlockedRow(
                userId: user.id,
                username: user.username,
                displayName: user.displayName,
                avatarUrl: user.avatarUrl,
              );
            },
          );
        },
      ),
    );
  }
}

class _BlockedRow extends ConsumerStatefulWidget {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  const _BlockedRow({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  @override
  ConsumerState<_BlockedRow> createState() => _BlockedRowState();
}

class _BlockedRowState extends ConsumerState<_BlockedRow> {
  bool _working = false;

  Future<void> _unblock() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the await: the container outlives this row, so the list
    // is refreshed even if the user leaves the screen mid-request.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _working = true);
    try {
      await ref.read(reportRepositoryProvider).unblock(widget.userId);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, l10n))),
      );
      return;
    }

    container.invalidate(blockedUsersProvider);

    // Leaving the screen while the DELETE is in flight disposes this row's ref.
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.blockedUserRemoved(widget.username))),
    );
    // No setState after success — the provider invalidation rebuilds the list
    // and this row is gone.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    return ListTile(
      leading: UserAvatar(avatarUrl: widget.avatarUrl, radius: 22),
      title: Text(
        widget.displayName?.isNotEmpty == true
            ? widget.displayName!
            : '@${widget.username}',
        style: TextStyle(fontWeight: FontWeight.w600, color: nt.bark),
      ),
      subtitle: widget.displayName?.isNotEmpty == true
          ? Text('@${widget.username}', style: TextStyle(color: nt.text2))
          : null,
      trailing: _working
          ? const SizedBox(
              width: 20, height: 20, child: NTripiRingLoader(size: 18))
          : OutlinedButton(
              onPressed: _unblock,
              child: Text(l10n.unblockUser),
            ),
    );
  }
}
