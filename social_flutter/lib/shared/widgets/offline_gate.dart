import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

/// Gates a mutation-triggering control on connectivity.
///
/// Build the control via [builder] and pass `online ? action : null` as its
/// callback so it gets native disabled styling. When offline the gate absorbs
/// all taps and shows a "you're offline" popover anchored to the control —
/// mirroring the view-only edit hint UX.
///
/// The existing save-failure snackbar path stays as the fallback for
/// false-online states (e.g. captive portals) this gate cannot detect.
class OfflineGate extends ConsumerWidget {
  const OfflineGate({super.key, required this.builder});

  final Widget Function(bool online) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Optimistic while the stream seeds — never falsely lock the UI.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final child = builder(online);
    if (online) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showOfflineHint(context),
      child: AbsorbPointer(child: child),
    );
  }
}

/// Shows the shared "you're offline" popover anchored to [context]'s widget.
/// Exposed for controls that gate themselves (EditPencilButton, FollowButton).
void showOfflineHint(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  showFieldHelp(
    context,
    title: l10n.offlineActionTitle,
    message: l10n.offlineActionMessage,
    pointer: true,
  );
}
