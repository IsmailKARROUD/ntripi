// features/follows/presentation/follow_requests_screen.dart
//
// Shows a list of pending follow requests with Accept and Reject buttons.
// After accepting or rejecting, the item is removed immediately (optimistic UI).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class FollowRequestsScreen extends ConsumerWidget {
  const FollowRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(followRequestsProvider);

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
              const SafeArea(
                bottom: false,
                child: EditorialTopBar(title: 'Follow Requests'),
              ),
              Container(height: 1, color: kBorder),
              Expanded(
                child: requestsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            extractErrorMessage(error),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kText2),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => ref
                                .read(followRequestsProvider.notifier)
                                .refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (requests) {
                    if (requests.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 56, color: kText3),
                            SizedBox(height: 10),
                            Text(
                              'No pending requests',
                              style: TextStyle(color: kText2),
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () =>
                          ref.read(followRequestsProvider.notifier).refresh(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 80),
                        children: [
                          SectionLabel(
                            icon: Icons.person_add_outlined,
                            label: 'Requests · ${requests.length}',
                          ),
                          SectionCard(
                            children: [
                              for (var i = 0; i < requests.length; i++)
                                _FollowRequestTile(
                                  request: requests[i],
                                  isLast: i == requests.length - 1,
                                ),
                            ],
                          ),
                        ],
                      ),
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

class _FollowRequestTile extends ConsumerStatefulWidget {
  final FollowRequestItem request;
  final bool isLast;

  const _FollowRequestTile({required this.request, required this.isLast});

  @override
  ConsumerState<_FollowRequestTile> createState() => _FollowRequestTileState();
}

class _FollowRequestTileState extends ConsumerState<_FollowRequestTile> {
  bool _isLoading = false;

  Future<void> _accept() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(followRequestsProvider.notifier)
          .acceptRequest(widget.request.followId);
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

  Future<void> _reject() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(followRequestsProvider.notifier)
          .rejectRequest(widget.request.followId);
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
    final r = widget.request;
    final name = r.displayName ?? '@${r.username}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              AvatarInitials(name: name, avatarUrl: r.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kBark,
                        letterSpacing: -0.1,
                      ),
                    ),
                    Text(
                      '@${r.username}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: kText2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                FilledButton(
                  onPressed: _accept,
                  style: FilledButton.styleFrom(
                    backgroundColor: kForest,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFBA1A1A),
                    side: const BorderSide(color: Color(0xFFBA1A1A)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
        if (!widget.isLast)
          Container(
            height: 1,
            margin: const EdgeInsets.only(left: 70),
            color: kBorder,
          ),
      ],
    );
  }
}
