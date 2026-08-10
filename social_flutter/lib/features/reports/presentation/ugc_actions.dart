// features/reports/presentation/ugc_actions.dart — the report/block affordance.
//
// One widget, used on every surface that shows content somebody else wrote:
// itinerary detail, stop detail, review tiles, profiles. A report action that
// is missing from any one of them is an app-store rejection risk, and four
// hand-rolled menus would drift apart the first time the options changed.
//
// Never shown on your own content — [UgcActionsMenu] is simply omitted by the
// caller when the viewer is the author.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/report_content_sheet.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Overflow menu offering Report and (when a user is identified) Block.
class UgcActionsMenu extends ConsumerWidget {
  final ReportTarget target;

  /// The account behind the content. Null when it cannot be identified (an
  /// anonymised review, say) — the menu then offers Report only.
  final String? authorUserId;
  final String? authorUsername;

  /// Called after a successful block so the caller can leave the screen or
  /// refresh its list — the content is about to become invisible.
  final VoidCallback? onBlocked;

  final Color? iconColor;

  /// Custom trigger, replacing the default icon. Lets a caller with its own
  /// button styling (the profile hero's frosted glass) wear it here — the two
  /// are mutually exclusive in PopupMenuButton, and only the `child` form
  /// leaves the widget's own size intact instead of forcing IconButton's.
  final Widget? child;

  const UgcActionsMenu({
    super.key,
    required this.target,
    this.authorUserId,
    this.authorUsername,
    this.onBlocked,
    this.iconColor,
    this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final canBlock = authorUserId != null;

    return PopupMenuButton<String>(
      icon: child == null
          ? Icon(Icons.more_horiz, color: iconColor ?? context.nt.text2)
          : null,
      tooltip: l10n.reportContent,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, size: 20),
              const SizedBox(width: 12),
              Text(l10n.reportContent),
            ],
          ),
        ),
        if (canBlock)
          PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 20),
                const SizedBox(width: 12),
                Text(l10n.blockUser),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (value == 'report') {
          showReportContentSheet(context, ref, target);
        } else {
          confirmAndBlock(
            context, ref,
            userId: authorUserId!,
            username: authorUsername ?? '',
            onBlocked: onBlocked,
          );
        }
      },
      child: child,
    );
  }
}

/// Confirm-then-block, shared by the overflow menu and the profile screen.
///
/// Tier 2 destructive confirmation: blocking severs any follow in both
/// directions, which is not obvious from the word "block" and is not undone by
/// unblocking.
Future<void> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String username,
  VoidCallback? onBlocked,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await confirmDestructiveAction(
    context: context,
    icon: Icons.block_rounded,
    title: l10n.blockUserTitle(username),
    message: l10n.blockUserMessage,
    confirmLabel: l10n.blockUser,
  );
  if (!confirmed) return;

  try {
    await ref.read(reportRepositoryProvider).block(userId);
    ref.invalidate(blockedUsersProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.blockedUserAdded(username))),
    );
    onBlocked?.call();
  } on Exception catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(extractErrorMessage(e, l10n))),
    );
  }
}
