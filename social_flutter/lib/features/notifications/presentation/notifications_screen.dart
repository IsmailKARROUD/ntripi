// features/notifications/presentation/notifications_screen.dart
//
// The bell screen. Opening it marks everything read — the badge exists to get
// the user here, so leaving it lit after they arrived would be noise.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _opened = false;

  /// A reload is in flight that the user did not drag for — drives the progress
  /// line under the top bar, since the rows stay put throughout and would
  /// otherwise give no sign anything was happening.
  bool _refreshing = false;

  /// Captured while the widget is still mounted. `ref` is backed by
  /// BuildContext, so touching it in dispose() throws in Riverpod 3 — and this
  /// screen can be torn down by a redirect the user never asked for (an
  /// unfollow elsewhere invalidating the session's profile, say), which is
  /// exactly when the queue most needs settling. The notifier itself outlives
  /// the widget: notificationsProvider is keep-alive, not autoDispose.
  NotificationsNotifier? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier = ref.read(notificationsProvider.notifier);

    // Refetch on open, before touching anything. notificationsProvider is
    // keep-alive, so without this the second visit renders whatever the first
    // one fetched — and marking that cached feed read would mark a row the user
    // has never been shown read on the server, badge and all. The row would
    // then never surface anywhere. Refresh first, act second.
    if (_opened) return;
    _opened = true;
    // Deferred a frame: didChangeDependencies runs inside the build pipeline,
    // and _pullInArrivals calls setState to raise the progress line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_pullInArrivals());
    });
  }

  @override
  void dispose() {
    // Leaving the screen settles the delete queue: waiting out a timer nobody is
    // watching only widens the window where killing the app resurrects a row.
    _notifier?.flushPending();
    super.dispose();
  }

  /// Bring the feed up to date, then clear the badge — in that order.
  ///
  /// Both entry points need the same bargain: the rows keep their unread tint
  /// (so the user sees what is new), and the bell does not stay lit. The order
  /// is the load-bearing part. Marking read first would clear the badge for a
  /// row that is not on screen yet, and since the server is the authority on
  /// read state, that row would never be surfaced as new anywhere again.
  ///
  /// Safe when the first load failed: silentRefresh leaves the error in place
  /// and markAllRead early-returns on a null value, so a badge is never cleared
  /// over a feed the user was never shown.
  Future<void> _pullInArrivals() async {
    setState(() => _refreshing = true);
    try {
      await _notifier?.silentRefresh();
      if (!mounted) return;
      await _notifier?.markAllRead();
    } finally {
      // Guarded: the user can leave mid-request, and this runs either way.
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync = ref.watch(notificationsProvider);

    // The poller only maintains the badge; an arrival in it is this screen's
    // cue that a row landed while the user was sitting here. Keyed off the
    // timestamp rather than the count: markAllRead below drives the count to 0
    // (so a count rise would loop), and a read on another device can cancel out
    // an arrival and mask it entirely.
    ref.listen(notificationBadgeProvider, (previous, next) {
      if (next.value?.arrivedSince(previous?.value) ?? false) {
        unawaited(_pullInArrivals());
      }
    });

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
                child: EditorialTopBar(
                  title: l10n.notificationsTitle,
                  actions: [
                    IconButton(
                      icon: Icon(Icons.tune_rounded, size: 20, color: nt.bark),
                      tooltip: l10n.settingsNotifications,
                      onPressed: () => context.push('/settings/notifications'),
                    ),
                  ],
                ),
              ),
              EditorialDivider(loading: _refreshing),
              Expanded(
                child: notificationsAsync.when(
                  loading: () => const Center(child: NTripiSkeleton()),
                  error: (error, _) => _ErrorView(error: error),
                  data: (notifications) => notifications.isEmpty
                      ? const _EmptyView()
                      : _Feed(notifications: notifications),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feed extends ConsumerWidget {
  final List<AppNotification> notifications;

  const _Feed({required this.notifications});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Optimistic while the stream seeds — never falsely lock the UI.
    final online = ref.watch(isOnlineProvider).value ?? true;

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 80),
        children: [
          SectionLabel(
            icon: Icons.notifications_none_rounded,
            label: l10n.notificationsCountLabel(notifications.length),
          ),
          SectionCard(
            children: [
              // SectionCard rounds its corners but does not clip, so the swipe
              // pane would square them off. Clipping here rather than in
              // SectionCard, which the whole app draws with.
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < notifications.length; i++)
                      _row(
                        context,
                        ref,
                        notifications[i],
                        isLast: i == notifications.length - 1,
                        online: online,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ClearAllButton(enabled: notifications.isNotEmpty),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    AppNotification n, {
    required bool isLast,
    required bool online,
  }) {
    final route = n.route();
    final tile = NotificationTile(
      notification: n,
      isLast: isLast,
      onTap: route == null ? null : () => context.push(route),
      onDelete: online ? () => _delete(context, ref, n) : null,
    );

    return Dismissible(
      key: ValueKey(n.id),
      // endToStart only — a start-to-end swipe is the system back gesture.
      direction:
          online ? DismissDirection.endToStart : DismissDirection.none,
      background: const _SwipeBackground(),
      onDismissed: (_) => _delete(context, ref, n),
      child: tile,
    );
  }

  /// Shared by the swipe and the ✕. Nothing is sent yet — dismiss() only queues
  /// the DELETE, which is what makes UNDO real rather than a second write.
  void _delete(BuildContext context, WidgetRef ref, AppNotification n) {
    if (!ref.read(notificationsProvider.notifier).dismiss(n.id)) return;
    showUndoableActionSnackbar(
      context: context,
      // Same constant as the queued timer, or UNDO outlives its own window.
      duration: kNotificationUndoWindow,
      message: AppLocalizations.of(context)!.notificationDeleted,
      onUndo: () async =>
          ref.read(notificationsProvider.notifier).undoDismiss(n.id),
    );
  }
}

/// The pane revealed behind a row being swiped away.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      color: nt.dangerTint,
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 20),
      child: Icon(Icons.delete_outline_rounded, size: 22, color: nt.danger),
    );
  }
}

class _ClearAllButton extends ConsumerStatefulWidget {
  final bool enabled;

  const _ClearAllButton({required this.enabled});

  @override
  ConsumerState<_ClearAllButton> createState() => _ClearAllButtonState();
}

class _ClearAllButtonState extends ConsumerState<_ClearAllButton> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: OfflineGate(
        builder: (online) => TextButton.icon(
          // Nothing to clear, nothing to confirm — don't offer the action.
          onPressed:
              widget.enabled && online && !_clearing ? _clearAll : null,
          // The loader takes the icon's slot rather than the label's: the
          // request empties the whole feed, so the word has to stay readable
          // while it runs or the row reads as a button that lost its purpose.
          icon: _clearing
              ? const NTripiRingLoader(size: 16)
              : Icon(Icons.backspace_outlined, size: 16, color: nt.text2),
          label: Text(
            l10n.notificationsClearAll,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: nt.text2,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    // Tier 2: the whole feed goes at once and there is nothing to undo.
    final confirmed = await confirmDestructiveAction(
      context: context,
      icon: Icons.backspace_outlined,
      title: l10n.notificationsClearAllTitle,
      message: l10n.notificationsClearAllMessage,
      confirmLabel: l10n.notificationsClearAll,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      await ref.read(notificationsProvider.notifier).clearAll();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, l10n))),
      );
    } finally {
      // Guarded: on success the feed empties, which swaps _Feed for _EmptyView
      // and unmounts this button before the finally runs.
      if (mounted) setState(() => _clearing = false);
    }
  }
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return RefreshableCenter(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 56, color: nt.text3),
            const SizedBox(height: 10),
            Text(
              l10n.notificationsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: nt.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  final Object error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return RefreshableCenter(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              extractErrorMessage(error, l10n),
              textAlign: TextAlign.center,
              style: TextStyle(color: nt.text2),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(notificationsProvider.notifier).refresh(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
