// features/notifications/presentation/notifications_screen.dart
//
// The bell screen. Opening it marks everything read — the badge exists to get
// the user here, so leaving it lit after they arrived would be noise.

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

  @override
  void dispose() {
    // Leaving the screen settles the delete queue: waiting out a timer nobody is
    // watching only widens the window where killing the app resurrects a row.
    ref.read(notificationsProvider.notifier).flushPending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final notificationsAsync = ref.watch(notificationsProvider);

    // Mark read once the first page has actually arrived — doing it in initState
    // would clear the badge even when the load failed and the user saw nothing.
    if (!_markedRead && notificationsAsync.hasValue) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(notificationsProvider.notifier).markAllRead();
      });
    }

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

class _ClearAllButton extends ConsumerWidget {
  final bool enabled;

  const _ClearAllButton({required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: OfflineGate(
        builder: (online) => TextButton.icon(
          // Nothing to clear, nothing to confirm — don't offer the action.
          onPressed: enabled && online ? () => _clearAll(context, ref) : null,
          icon: Icon(Icons.backspace_outlined, size: 16, color: nt.text2),
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

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    // Tier 2: the whole feed goes at once and there is nothing to undo.
    final confirmed = await confirmDestructiveAction(
      context: context,
      icon: Icons.backspace_outlined,
      title: l10n.notificationsClearAllTitle,
      message: l10n.notificationsClearAllMessage,
      confirmLabel: l10n.notificationsClearAll,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(notificationsProvider.notifier).clearAll();
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, l10n))),
      );
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Center(
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
    return Center(
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
