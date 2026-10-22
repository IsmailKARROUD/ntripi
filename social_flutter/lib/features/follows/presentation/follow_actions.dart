// features/follows/presentation/follow_actions.dart — ending a follow from
// either end: removing a follower, and unfollowing from the Following list.
//
// Shaped like confirmAndBlock (ugc_actions.dart): the container, messenger and
// l10n are captured before the first await, so a change the server has made
// reaches every cache even if the calling screen is gone when it lands.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/ui/destructive_actions.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/follow_button.dart';

/// Confirm, then remove [userId] from the signed-in user's followers — from
/// the Followers list or the ⋯ menu on their profile. They are not told.
///
/// [onConfirmed] fires once the user agrees, before the request, so a row can
/// show its spinner for the part that actually waits. Returns true once the
/// server has removed them.
Future<bool> confirmAndRemoveFollower(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String username,
  VoidCallback? onConfirmed,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final me = ref.read(myProfileProvider).value;

  final confirmed = await confirmDestructiveAction(
    context: context,
    icon: Icons.person_remove_rounded,
    title: l10n.removeFollowerTitle(username),
    // Privacy unknown reads as public: never promise a barrier that may not
    // exist — a public account's removed follower can follow straight back.
    message: (me?.isPrivate ?? false)
        ? l10n.removeFollowerMessagePrivate
        : l10n.removeFollowerMessagePublic,
    confirmLabel: l10n.removeFollowerButton,
  );
  if (!confirmed || !context.mounted) return false;
  onConfirmed?.call();

  final FollowCounts counts;
  try {
    counts = await container.read(followRepositoryProvider).removeFollower(userId);
  } on Exception catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, l10n))),
      );
    }
    return false;
  }

  final myId = await _myId(container, me);
  if (myId != null) {
    final mine = followersProvider(myId);
    if (container.exists(mine)) {
      container.read(mine.notifier).removeLocally(userId);
    }
  }
  // Both profiles from the answer: my followers count, and their following
  // count and follows_you. Their Following list still names this account,
  // which no answer carries.
  adoptMyCounts(container, counts.me);
  adoptTheirFollowState(container, userId,
      followsYou: false, counts: counts.them);
  container.invalidate(followingProvider(userId));

  if (context.mounted) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.removedFollowerSnackbar(username))),
    );
  }
  return true;
}

/// Confirm, then unfollow [userId] — the row action on the signed-in user's
/// own Following list. Same dialog as the profile's Following button.
///
/// A 404 `not_following` means the row was stale (unfollowed on another
/// device, say): the state asked for already holds, so it counts as done.
/// [onConfirmed] and the return value work as in [confirmAndRemoveFollower].
Future<bool> confirmAndUnfollow(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String username,
  VoidCallback? onConfirmed,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final me = ref.read(myProfileProvider).value;

  final confirmed = await confirmUnfollow(context, username: username);
  if (!confirmed || !context.mounted) return false;
  onConfirmed?.call();

  FollowCounts? counts;
  try {
    counts = await container.read(followRepositoryProvider).unfollowUser(userId);
  } on Exception catch (e) {
    if (apiErrorCode(e) != 'not_following') {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, l10n))),
        );
      }
      return false;
    }
  }

  final myId = await _myId(container, me);
  if (myId != null) {
    final mine = followingProvider(myId);
    if (container.exists(mine)) {
      container.read(mine.notifier).removeLocally(userId);
    }
  }
  if (counts != null) {
    // Both profiles from the answer: my following count, and their followers
    // count and is_following.
    adoptMyCounts(container, counts.me);
    adoptTheirFollowState(container, userId,
        isFollowing: false, followIsPending: false, counts: counts.them);
  } else {
    // Already unfollowed elsewhere: nothing was written here, so there is no
    // answer to adopt, and the profiles are read again.
    container.invalidate(myProfileProvider);
    container.invalidate(userProfileProvider(userId));
  }
  // Their Followers list, and the trips they share with followers only —
  // content no answer carries, and no longer ours to open.
  container.invalidate(followersProvider(userId));
  container.invalidate(userItinerariesProvider(userId));

  if (context.mounted) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.unfollowedSnackbar(username))),
    );
  }
  return true;
}

/// The signed-in user's id, which keys their own cached lists. Usually loaded
/// before the action began; a deep link can reach a profile first, so wait for
/// the load the first read started rather than skip the edit. Null only when
/// that load failed, and then there is no list of mine to edit either.
Future<String?> _myId(ProviderContainer container, User? me) async {
  if (me != null) return me.id;
  try {
    return (await container.read(myProfileProvider.future)).id;
  } catch (_) {
    return null;
  }
}
