// features/notifications/presentation/notifications_screen.dart
//
// The bell screen. Opening it marks everything read — the badge exists to get
// the user here, so leaving it lit after they arrived would be noise.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markedRead = false;

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
              for (var i = 0; i < notifications.length; i++)
                _tile(context, notifications[i], i == notifications.length - 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, AppNotification n, bool isLast) {
    final route = n.route();
    return NotificationTile(
      notification: n,
      isLast: isLast,
      onTap: route == null ? null : () => context.push(route),
    );
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
