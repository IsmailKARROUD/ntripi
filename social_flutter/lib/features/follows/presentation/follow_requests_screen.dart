// features/follows/presentation/follow_requests_screen.dart
//
// Shows a list of pending follow requests with Accept and Reject buttons.
// After accepting or rejecting, the item is removed immediately (optimistic UI).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refetch on open: followRequestsProvider is keep-alive, so without this the
    // second visit shows whatever the first one fetched and a request that
    // arrived in between stays invisible. Silent — the cached list stays put
    // and a failure leaves it alone.
    if (_opened) return;
    _opened = true;
    unawaited(ref.read(followRequestsProvider.notifier).silentRefresh());
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final requestsAsync = ref.watch(followRequestsProvider);

    return Scaffold(
      backgroundColor: nt.surface,
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
                child: EditorialTopBar(title: AppLocalizations.of(context)!.followRequestsTitle),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: requestsAsync.when(
                  loading: () =>
                      const Center(child: NTripiSkeleton()),
                  error: (error, _) => RefreshableCenter(
                    onRefresh: () =>
                        ref.read(followRequestsProvider.notifier).refresh(),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            extractErrorMessage(error, AppLocalizations.of(context)!),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: nt.text2),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => ref
                                .read(followRequestsProvider.notifier)
                                .refresh(),
                            child: Text(AppLocalizations.of(context)!.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (requests) {
                    if (requests.isEmpty) {
                      // Pullable too: "no requests" is exactly the state where
                      // the user wants to ask again, and the RefreshIndicator
                      // below it is unreachable from here.
                      return RefreshableCenter(
                        onRefresh: () =>
                            ref.read(followRequestsProvider.notifier).refresh(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 56, color: nt.text3),
                            const SizedBox(height: 10),
                            Text(
                              AppLocalizations.of(context)!.noRequests,
                              style: TextStyle(color: nt.text2),
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
                            label: AppLocalizations.of(context)!.requestsCountLabel(requests.length),
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
          SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reject() async {
    final l10n = AppLocalizations.of(context)!;
    // Tier 2: the requester is never told they were declined, so a mis-tap
    // can only be fixed by asking them to send a new request.
    final confirmed = await confirmDestructiveAction(
      context: context,
      icon: Icons.person_remove_rounded,
      title: l10n.declineRequestTitle,
      message: l10n.declineRequestMessage(widget.request.username),
      confirmLabel: l10n.declineRequestConfirm,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(followRequestsProvider.notifier)
          .rejectRequest(widget.request.followId);
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
    final nt = context.nt;
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: nt.bark,
                        letterSpacing: -0.1,
                      ),
                    ),
                    Text(
                      '@${r.username}',
                      style: TextStyle(
                        fontSize: 12,
                        color: nt.text2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                const NTripiRingLoader(size: 24)
              else
                OfflineGate(
                  builder: (online) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: online ? _accept : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: nt.forest,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(AppLocalizations.of(context)!.acceptButton,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: online ? _reject : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: nt.danger,
                          side: BorderSide(color: nt.danger),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(AppLocalizations.of(context)!.rejectButton,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (!widget.isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 70),
            color: nt.border,
          ),
      ],
    );
  }
}
