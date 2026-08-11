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
  bool _markedRead = false;

  /// Captured while the widget is still mounted. `ref` is backed by
  /// BuildContext, so touching it in dispose() throws in Riverpod 3 — and this
  /// screen can be torn down by a redirect the user never asked for (an
  /// unfollow elsewhere invalidating the session's profile, say), which is
  /// exactly when the queue most needs settling. The notifier itself outlives
  /// the widget: notificationsProvider is keep-alive, not autoDispose.
  ///
  /// Seeded here for a teardown that beats the first build, then kept current
  /// by the watch in [build] — an invalidated provider swaps the instance, and
  /// dispose() has to flush the queue that is actually live.
  NotificationsNotifier? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier = ref.read(notificationsProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the screen settles the delete queue: waiting out a timer nobody is
    // watching only widens the window where killing the app resurrects a row.
    _notifier?.flushPending();
    super.dispose();
  }

  /// A notification landed while this screen was open. Bring it in without a
  /// spinner, then clear the badge again — the same bargain opening the screen
  /// makes: the row keeps its unread tint, the bell does not stay lit.
  Future<void> _pullInArrivals() async {
    await _notifier?.silentRefresh();
    if (!mounted) return;
    await _notifier?.markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync = ref.watch(notificationsProvider);
    // Watched, not read once: an invalidated provider swaps the instance, and
    // dispose() must flush the queue that is actually live.
    _notifier = ref.watch(notificationsProvider.notifier);

    // Mark read once the first page has actually arrived — doing it in initState
    // would clear the badge even when the load failed and the user saw nothing.
    if (!_markedRead && notificationsAsync.hasValue) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(notificationsProvider.notifier).markAllRead();
      });
    }

    // The poller only maintains the badge; a rise in it is this screen's cue
    // that a row landed while the user was sitting here. No loop: markAllRead
    // drives the count to 0, and 0 is not a rise.
    ref.listen(unreadNotificationCountProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null || after <= before) return;
      unawaited(_pullInArrivals());
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
              Container(height: 1, color: nt.border),
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

/// Pull-to-refresh over a state that has nothing to scroll.
///
/// Without this the gesture only existed inside _Feed, so the two states where
/// the user most wants to re-check — an empty feed and a failed load — were the
/// two with no way to ask again. AlwaysScrollableScrollPhysics is what lets a
/// viewport shorter than its box still register the drag.
class _RefreshableCenter extends ConsumerWidget {
  final Widget child;

  const _RefreshableCenter({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return _RefreshableCenter(
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
    return _RefreshableCenter(
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
