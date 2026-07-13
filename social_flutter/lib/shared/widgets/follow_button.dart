// shared/widgets/follow_button.dart — Smart follow/unfollow button.
//
// This widget handles three distinct visual and behavioral states:
//   1. isFollowing == true  → "Following" (filled) → tap shows confirm unfollow dialog
//   2. followIsPending == true → "Requested" (outlined) → tap shows cancel dialog
//   3. Neither              → "Follow" (filled primary) → tap immediately follows
//
// Why a separate widget?
//   This button appears on UserProfileScreen and potentially in search results.
//   Centralising the logic here ensures consistent behaviour everywhere.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

/// Callback invoked after a follow state change.
/// The calling screen uses this to refresh its data.
typedef OnFollowChanged = void Function({
  required bool isFollowing,
  required bool followIsPending,
});

class FollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final String targetUsername;
  final bool isFollowing;
  final bool followIsPending;
  final OnFollowChanged onChanged;

  const FollowButton({
    super.key,
    required this.targetUserId,
    required this.targetUsername,
    required this.isFollowing,
    required this.followIsPending,
    required this.onChanged,
  });

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _isLoading = false;

  FollowRepository get _repo => FollowRepository(dio);

  Future<void> _handleFollow() async {
    setState(() => _isLoading = true);
    try {
      final result = await _repo.followUser(widget.targetUserId);
      widget.onChanged(
        isFollowing: result.status == 'accepted',
        followIsPending: result.status == 'pending',
      );
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUnfollow() async {
    // Tier 1: act immediately then offer undo via snackbar.
    setState(() => _isLoading = true);
    try {
      await _repo.unfollowUser(widget.targetUserId);
      widget.onChanged(isFollowing: false, followIsPending: false);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    showUndoableActionSnackbar(
      context: context,
      message: AppLocalizations.of(context)!.unfollowedSnackbar(widget.targetUsername),
      onUndo: () async {
        final result = await _repo.followUser(widget.targetUserId);
        widget.onChanged(
          isFollowing: result.status == 'accepted',
          followIsPending: result.status == 'pending',
        );
      },
    );
  }

  Future<void> _handleCancelRequest() async {
    // Tier 2: simple confirmation — cancelling a pending request is harder
    // to undo (requires re-tapping Follow), so we confirm first.
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.cancelRequestTitle,
      message: l10n.cancelRequestMessage(widget.targetUsername),
      confirmLabel: l10n.cancelRequestConfirm,
      cancelLabel: l10n.cancelRequestKeep,
    );

    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      // Unfollow endpoint also cancels pending requests.
      await _repo.unfollowUser(widget.targetUserId);
      widget.onChanged(isFollowing: false, followIsPending: false);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 100,
        height: 36,
        child: Center(child: NTripiRingLoader(size: 32)),
      );
    }

    // Follow actions are mutations — offline they disable and explain on tap.
    return OfflineGate(
      builder: (online) {
        if (widget.isFollowing) {
          // State 1: Currently following.
          return FilledButton(
            onPressed: online ? _handleUnfollow : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.grey.shade200,
              foregroundColor: Colors.black87,
            ),
            child: Text(AppLocalizations.of(context)!.followingButton),
          );
        }

        if (widget.followIsPending) {
          // State 2: Pending follow request.
          return OutlinedButton(
            onPressed: online ? _handleCancelRequest : null,
            child: Text(AppLocalizations.of(context)!.requestedButton),
          );
        }

        // State 3: Not following.
        return FilledButton(
          onPressed: online ? _handleFollow : null,
          child: Text(AppLocalizations.of(context)!.followButton),
        );
      },
    );
  }
}
