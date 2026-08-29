// features/notifications/presentation/notification_settings_screen.dart
//
// Per-type switches for the optional notifications.
//
// Only the three optional types appear here. Follow requests and moderation
// actions are deliberately absent: a request nobody sees can never be answered,
// and an author who is not told their content was hidden cannot appeal in time.
// Showing them as locked rows would invite the question; showing nothing is the
// honest version, and the footnote below says so.
//
// Preferences are enforced server-side at write time — a muted type never
// creates a row — so this screen writes through PATCH /users/me rather than
// keeping the value locally. The only local state is which row is mid-save:
// the switch cannot move until the server answers, so without it a tap has
// nothing to show for itself for the length of a round trip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/toggle_feedback.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final profileAsync = ref.watch(myProfileProvider);

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
                child: EditorialTopBar(title: l10n.settingsNotifications),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: profileAsync.when(
                  loading: () => const Center(child: NTripiSkeleton()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        extractErrorMessage(error, l10n),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: nt.text2),
                      ),
                    ),
                  ),
                  data: (user) => _Switches(user: user),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which row is mid-save. The switches render from the server's answer, so a
/// flip has nothing to show for itself until the round trip lands.
enum _NotifPref { ratings, saves, followAccepted }

class _Switches extends ConsumerStatefulWidget {
  final User user;

  const _Switches({required this.user});

  @override
  ConsumerState<_Switches> createState() => _SwitchesState();
}

class _SwitchesState extends ConsumerState<_Switches> {
  final _pending = <_NotifPref>{};

  /// Marks the row busy, saves, and acknowledges only once the new value is on
  /// screen — so the cue, the tap and the thumb sliding are one event rather
  /// than a sound now and an animation a second later.
  Future<void> _update(_NotifPref pref, bool value) async {
    setState(() => _pending.add(pref));
    await ref.read(myProfileProvider.notifier).updateProfile(
          notifyRatings: pref == _NotifPref.ratings ? value : null,
          notifySaves: pref == _NotifPref.saves ? value : null,
          notifyFollowAccepted:
              pref == _NotifPref.followAccepted ? value : null,
        );
    // updateProfile is AsyncValue.guard'd and never throws — it writes the
    // failure into myProfileProvider, which swaps this whole list for an error
    // message. So still being mounted IS the success test, and a failed save
    // gets no acknowledgement.
    if (!mounted) return;
    setState(() => _pending.remove(pref));
    toggleFeedback(ref);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final user = widget.user;

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 40),
      children: [
        SectionLabel(
          icon: Icons.notifications_none_rounded,
          label: l10n.notificationSettingsOptionalLabel,
        ),
        // Disabled while offline: the switch writes straight to the server, so
        // flipping it with no connection would show a state that was not saved.
        OfflineGate(
          builder: (online) => SectionCard(
            children: [
              _SwitchRow(
                icon: Icons.star_rounded,
                label: l10n.notificationSettingsRatings,
                detail: l10n.notificationSettingsRatingsDetail,
                value: user.notifyRatings,
                pending: _pending.contains(_NotifPref.ratings),
                onChanged: online
                    ? (v) => _update(_NotifPref.ratings, v)
                    : null,
              ),
              _SwitchRow(
                icon: Icons.bookmark_rounded,
                label: l10n.notificationSettingsSaves,
                detail: l10n.notificationSettingsSavesDetail,
                value: user.notifySaves,
                pending: _pending.contains(_NotifPref.saves),
                onChanged:
                    online ? (v) => _update(_NotifPref.saves, v) : null,
              ),
              _SwitchRow(
                icon: Icons.how_to_reg_rounded,
                label: l10n.notificationSettingsFollowAccepted,
                detail: l10n.notificationSettingsFollowAcceptedDetail,
                value: user.notifyFollowAccepted,
                isLast: true,
                pending: _pending.contains(_NotifPref.followAccepted),
                onChanged: online
                    ? (v) => _update(_NotifPref.followAccepted, v)
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Text(
            l10n.notificationSettingsAlwaysOnNote,
            style: TextStyle(fontSize: 12.5, color: nt.text2, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final bool value;
  final bool isLast;
  final bool pending;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.pending = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // The spinner takes the icon's place rather than the switch's:
              // a switch that unmounts and comes back at its new value cannot
              // animate, and that slide is the acknowledgement.
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nt.mist,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: pending
                    ? const NTripiRingLoader(size: 20)
                    : Icon(icon, size: 16, color: nt.forest),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: nt.bark,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      style: TextStyle(fontSize: 12.5, color: nt.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: value,
                // Disabled mid-save: a second tap would race the first, and
                // both would land on whatever the server answered last.
                onChanged: pending ? null : onChanged,
                activeTrackColor: nt.forest,
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 56),
            color: nt.border,
          ),
      ],
    );
  }
}
