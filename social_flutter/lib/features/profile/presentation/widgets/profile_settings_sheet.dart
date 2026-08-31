import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/providers/haptics_enabled_provider.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/toggle_feedback.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/bug_report/providers/shake_report_enabled_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/app_locales.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

void showProfileSettingsSheet(
  BuildContext context, {
  required VoidCallback onLogout,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => _SettingsSheet(
          onLogout: () {
            Navigator.pop(ctx);
            onLogout();
          },
        ),
  );
}

// One handler per switch, shared by the row's own onTap so the two can never
// drift. Each writes its preference *before* toggleFeedback — see its doc: these
// three rows are the only ones whose flip changes what the acknowledgement is
// allowed to do.
void _setSoundEffects(WidgetRef ref, bool enabled) {
  ref.read(soundEffectsEnabledProvider.notifier).setEnabled(enabled);
  toggleFeedback(ref);
}

void _setHaptics(WidgetRef ref, bool enabled) {
  ref.read(hapticsEnabledProvider.notifier).setEnabled(enabled);
  toggleFeedback(ref);
}

void _setShakeReport(WidgetRef ref, bool enabled) {
  ref.read(shakeReportEnabledProvider.notifier).setEnabled(enabled);
  toggleFeedback(ref);
}

class _SettingsSheet extends ConsumerWidget {
  final VoidCallback onLogout;

  const _SettingsSheet({required this.onLogout});

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final currentCode = ref.read(localeProvider).languageCode;
    final languages = kAppLocales;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.languagePickerTitle.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: nt.text2,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: nt.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: nt.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < languages.length; i++) ...[
                          if (i > 0)
                            Container(
                              height: 1,
                              color: nt.border,
                              margin: const EdgeInsetsDirectional.only(
                                start: 16,
                              ),
                            ),
                          InkWell(
                            onTap: () {
                              ref
                                  .read(localeProvider.notifier)
                                  .setLocale(Locale(languages[i].code));
                              Navigator.pop(ctx);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: nt.mist,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      languages[i].flag,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      localeLabel(l10n, languages[i].code),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: nt.bark,
                                      ),
                                    ),
                                  ),
                                  if (currentCode == languages[i].code)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: nt.forest,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final currentMode = ref.read(themeModeProvider);

    final modes = [
      (
        mode: ThemeMode.system,
        icon: Icons.brightness_auto_rounded,
        label: l10n.themeSystem,
      ),
      (
        mode: ThemeMode.light,
        icon: Icons.light_mode_rounded,
        label: l10n.themeLight,
      ),
      (
        mode: ThemeMode.dark,
        icon: Icons.dark_mode_rounded,
        label: l10n.themeDark,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.themePickerTitle.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: nt.text2,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: nt.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: nt.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < modes.length; i++) ...[
                          if (i > 0)
                            Container(
                              height: 1,
                              color: nt.border,
                              margin: const EdgeInsetsDirectional.only(
                                start: 16,
                              ),
                            ),
                          InkWell(
                            onTap: () {
                              ref
                                  .read(themeModeProvider.notifier)
                                  .setMode(modes[i].mode);
                              Navigator.pop(ctx);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: nt.mist,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      modes[i].icon,
                                      size: 16,
                                      color: nt.forest,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      modes[i].label,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: nt.bark,
                                      ),
                                    ),
                                  ),
                                  if (currentMode == modes[i].mode)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: nt.forest,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final currentLocale = ref.watch(localeProvider);
    final langDetail = localeLabel(l10n, currentLocale.languageCode);
    final themeDetail = switch (ref.watch(themeModeProvider)) {
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
      ThemeMode.system => l10n.themeSystem,
    };
    // How many of the three optional types are on. Shows nothing while the
    // profile is still loading rather than flashing a wrong count.
    final me = ref.watch(myProfileProvider).value;
    final notificationsDetail = me == null
        ? null
        : l10n.settingsNotificationsOnCount([
            me.notifyRatings,
            me.notifySaves,
            me.notifyFollowAccepted,
          ].where((on) => on).length);
    // Public accounts auto-accept follows, so their pending list is always
    // empty. The watch sits inside the gate so a public account's settings
    // sheet never spends a follow-requests fetch on a row it will not draw.
    final showFollowRequests = me?.isPrivate ?? false;
    final pendingRequests = showFollowRequests
        ? ref.watch(followRequestsProvider).value?.length
        : null;

    final media = MediaQuery.of(context);
    // A fixed 75% of the screen, not content height: the row list grows over
    // time and a self-sizing sheet changes height between builds. Capped so the
    // top edge never slides under the status bar on short devices.
    final sheetHeight = math.min(
      media.size.height * 0.75,
      media.size.height - media.padding.top - 12,
    );

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: media.padding.bottom + 16),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: nt.text3.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.settingsTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          // Scrollable so the sheet survives short viewports (and any future
          // row) instead of overflowing its Column.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetSection(
                    label: l10n.settingsAccount,
                    children: [
                      EditorialRow(
                        icon: Icons.notifications_outlined,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsNotifications,
                        detail: notificationsDetail,
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/notifications');
                        },
                      ),
                      EditorialRow(
                        icon: Icons.language_rounded,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsLanguage,
                        detail: langDetail,
                        onTap: () => _showLanguagePicker(context, ref),
                      ),
                      EditorialRow(
                        // inverse badge so the theme control stands apart from the
                        // green-tinted rows around it
                        icon: Icons.dark_mode_outlined,
                        iconBg: nt.inverseSurface,
                        iconColor: nt.onInverseSurface,
                        label: l10n.settingsTheme,
                        detail: themeDetail,
                        onTap: () => _showThemePicker(context, ref),
                      ),
                      // Not hidden on web, unlike the shake row below —
                      // audioplayers plays the cue there too.
                      EditorialRow(
                        icon: Icons.volume_up_outlined,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsSoundEffects,
                        subtitle: l10n.settingsSoundEffectsDetail,
                        trailing: Switch(
                          value: ref.watch(soundEffectsEnabledProvider),
                          onChanged: (value) => _setSoundEffects(ref, value),
                        ),
                        onTap: () => _setSoundEffects(
                          ref,
                          !ref.read(soundEffectsEnabledProvider),
                        ),
                      ),
                      // Its own switch, not folded into the sound one: muting
                      // the app is exactly when the tap is the only feedback
                      // left. Not web-guarded either — a harmless no-op there.
                      EditorialRow(
                        icon: Icons.touch_app_outlined,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsHaptics,
                        subtitle: l10n.settingsHapticsDetail,
                        trailing: Switch(
                          value: ref.watch(hapticsEnabledProvider),
                          onChanged: (value) => _setHaptics(ref, value),
                        ),
                        onTap: () =>
                            _setHaptics(ref, !ref.read(hapticsEnabledProvider)),
                      ),
                      EditorialRow(
                        icon: Icons.shield_outlined,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.accountStatusTitle,
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/account-status');
                        },
                      ),
                      if (showFollowRequests)
                        EditorialRow(
                          icon: Icons.person_add_alt_1_outlined,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.followRequestsTitle,
                          // Null, not "0" — a zero is noise, and null is also
                          // what a list still loading gives, so a wrong number
                          // can never flash.
                          detail: (pendingRequests ?? 0) > 0
                              ? '$pendingRequests'
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/follow-requests');
                          },
                        ),
                      // Reviewers check for a blocked list that can be found
                      // and reversed — a block with no way back is not one.
                      EditorialRow(
                        icon: Icons.block_rounded,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.blockedUsers,
                        isLast: true,
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/blocked-users');
                        },
                      ),
                    ],
                  ),
                  // Legal documents, the abuse address and bug reporting all
                  // moved into the Help Center — this section is now the two
                  // doors to it, plus the gesture preference.
                  _SheetSection(
                    label: l10n.settingsSupport,
                    children: [
                      EditorialRow(
                        icon: Icons.help_outline_rounded,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsHelpCenter,
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/help');
                        },
                      ),
                      EditorialRow(
                        icon: Icons.info_outline_rounded,
                        iconBg: nt.mist,
                        iconColor: nt.forest,
                        label: l10n.settingsAbout,
                        isLast: kIsWeb,
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings/about');
                        },
                      ),
                      // Hidden on web, where there is no shake to disable.
                      if (!kIsWeb)
                        EditorialRow(
                          icon: Icons.vibration_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.settingsShakeToReport,
                          subtitle: l10n.settingsShakeToReportDetail,
                          isLast: true,
                          trailing: Switch(
                            value: ref.watch(shakeReportEnabledProvider),
                            onChanged: (value) => _setShakeReport(ref, value),
                          ),
                          onTap: () => _setShakeReport(
                            ref,
                            !ref.read(shakeReportEnabledProvider),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: nt.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: nt.border),
                      ),
                      child: EditorialRow(
                        // red badge — logout ends the session, not a brand action
                        icon: Icons.logout_rounded,
                        iconBg: nt.dangerTint,
                        iconColor: nt.danger,
                        label: l10n.settingsLogout,
                        showChevron: false,
                        isLast: true,
                        onTap: onLogout,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _SheetSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: nt.text2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: nt.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
