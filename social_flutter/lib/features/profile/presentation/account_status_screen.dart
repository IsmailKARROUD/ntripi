// features/profile/presentation/account_status_screen.dart — "Account status".
//
// Lists every moderation action taken against the signed-in user and lets them
// appeal the ones the server marks appealable. The server owns the rules (one
// open appeal per item, 30-day lock after a rejection); this screen only renders
// the verdict and surfaces the coded errors if a stale row is submitted anyway.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/profile/domain/violation.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/appeal_sheet.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final violationsAsync = ref.watch(myViolationsProvider);

    return Scaffold(
      backgroundColor: nt.surface,
      appBar: AppBar(title: Text(l10n.accountStatusTitle)),
      body: violationsAsync.when(
        loading: () => const Center(child: NTripiRingLoader()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.errorGenericRetry,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nt.text2),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(myViolationsProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (violations) {
          if (violations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 44, color: nt.text3),
                    const SizedBox(height: 14),
                    Text(
                      l10n.violationsEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: nt.text2),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myViolationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: violations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ViolationCard(violation: violations[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ViolationCard extends ConsumerWidget {
  final Violation violation;

  const _ViolationCard({required this.violation});

  String _actionLabel(AppLocalizations l10n) => switch (violation.action) {
        ModerationAction.hide => l10n.violationHidden,
        ModerationAction.delete => l10n.violationRemoved,
        ModerationAction.warn => l10n.violationWarned,
        ModerationAction.ban => l10n.violationBanned,
        ModerationAction.unknown => l10n.violationOther,
      };

  /// Current state of the item, in the user's terms: an open or decided appeal
  /// outranks the raw penalty, and a lifted penalty is worth saying out loud.
  String _statusLabel(AppLocalizations l10n) {
    if (violation.appealStatus == AppealStatus.pending) return l10n.appealPending;
    if (violation.appealStatus == AppealStatus.restored) return l10n.appealRestored;
    if (violation.appealStatus == AppealStatus.reduced) return l10n.appealReduced;
    if (violation.appealStatus == AppealStatus.upheld) return l10n.appealRejected;
    if (!violation.active) return l10n.violationLifted;
    if (violation.appealable) return l10n.appealAvailable;
    return _actionLabel(l10n);
  }

  Future<void> _openAppealSheet(BuildContext context, WidgetRef ref) async {
    await showAppealSheet(
      context,
      ref,
      targetType: violation.targetType,
      targetId: violation.targetId ?? '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final isLifted = !violation.active ||
        violation.appealStatus == AppealStatus.restored;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: nt.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  violation.itemTitle ?? _actionLabel(l10n),
                  style: TextStyle(fontWeight: FontWeight.w700, color: nt.bark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLifted ? nt.mist : nt.cautionBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(l10n),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLifted ? nt.forest : nt.cautionFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_actionLabel(l10n)} · ${_formatDate(violation.createdAt)}',
            style: TextStyle(fontSize: 13, color: nt.text2),
          ),
          if (violation.cooldownUntil != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.appealCooldownUntil(_formatDate(violation.cooldownUntil!)),
              style: TextStyle(fontSize: 12, color: nt.text3),
            ),
          ],
          if (violation.appealable) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                onPressed: () => _openAppealSheet(context, ref),
                child: Text(l10n.appealSubmit),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
