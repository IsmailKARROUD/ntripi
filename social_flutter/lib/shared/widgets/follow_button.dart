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
import 'package:social_flutter/features/follows/data/follow_repository.dart';

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
          SnackBar(content: Text(extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUnfollow() async {
    // Show confirmation dialog before unfollowing.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unfollow'),
        content: Text('Unfollow @${widget.targetUsername}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _repo.unfollowUser(widget.targetUserId);
      widget.onChanged(isFollowing: false, followIsPending: false);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Request'),
        content: Text('Cancel follow request to @${widget.targetUsername}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // Unfollow endpoint also cancels pending requests.
      await _repo.unfollowUser(widget.targetUserId);
      widget.onChanged(isFollowing: false, followIsPending: false);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e))),
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
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (widget.isFollowing) {
      // State 1: Currently following.
      return FilledButton(
        onPressed: _handleUnfollow,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.grey.shade200,
          foregroundColor: Colors.black87,
        ),
        child: const Text('Following'),
      );
    }

    if (widget.followIsPending) {
      // State 2: Pending follow request.
      return OutlinedButton(
        onPressed: _handleCancelRequest,
        child: const Text('Requested'),
      );
    }

    // State 3: Not following.
    return FilledButton(
      onPressed: _handleFollow,
      child: const Text('Follow'),
    );
  }
}
