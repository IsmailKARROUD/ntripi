import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

void showProfileSettingsSheet(
  BuildContext context, {
  required VoidCallback onLogout,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SettingsSheet(
      onLogout: () {
        Navigator.pop(ctx);
        onLogout();
      },
    ),
  );
}

class _SettingsSheet extends ConsumerWidget {
  final VoidCallback onLogout;

  const _SettingsSheet({
    required this.onLogout,
  });

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final currentCode = ref.read(localeProvider).languageCode;

    final languages = [
      (code: 'en', label: l10n.languageEnglish),
      (code: 'fr', label: l10n.languageFrench),
      (code: 'ar', label: l10n.languageArabic),
      (code: 'es', label: l10n.languageSpanish),
      (code: 'de', label: l10n.languageGerman),
      (code: 'zh', label: l10n.languageChinese),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: nt.sand,
      builder: (ctx) => SafeArea(
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
                          margin: const EdgeInsetsDirectional.only(start: 16),
                        ),
                      InkWell(
                        onTap: () {
                          ref
                              .read(localeProvider.notifier)
                              .setLocale(Locale(languages[i].code));
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                                  languages[i].code.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: nt.forest,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  languages[i].label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: nt.bark,
                                  ),
                                ),
                              ),
                              if (currentCode == languages[i].code)
                                Icon(Icons.check_rounded,
                                    size: 18, color: nt.forest),
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
      backgroundColor: nt.sand,
      builder: (ctx) => SafeArea(
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
                          margin: const EdgeInsetsDirectional.only(start: 16),
                        ),
                      InkWell(
                        onTap: () {
                          ref
                              .read(themeModeProvider.notifier)
                              .setMode(modes[i].mode);
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                                child: Icon(modes[i].icon,
                                    size: 16, color: nt.forest),
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
                                Icon(Icons.check_rounded,
                                    size: 18, color: nt.forest),
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
    final langDetail = switch (currentLocale.languageCode) {
      'fr' => l10n.languageFrench,
      'ar' => l10n.languageArabic,
      'es' => l10n.languageSpanish,
      'de' => l10n.languageGerman,
      'zh' => l10n.languageChinese,
      _ => l10n.languageEnglish,
    };
    final themeDetail = switch (ref.watch(themeModeProvider)) {
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
      ThemeMode.system => l10n.themeSystem,
    };

    return Container(
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          _SheetSection(
            label: l10n.settingsAccount,
            children: [
              _SheetRow(
                icon: Icons.notifications_outlined,
                iconBg: nt.mist,
                iconColor: nt.forest,
                label: l10n.settingsNotifications,
                detail: l10n.settingsNotificationsOff,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.language_rounded,
                iconBg: nt.mist,
                iconColor: nt.forest,
                label: l10n.settingsLanguage,
                detail: langDetail,
                onTap: () => _showLanguagePicker(context, ref),
              ),
              _SheetRow(
                // inverse badge so the theme control stands apart from the
                // green-tinted rows around it
                icon: Icons.dark_mode_outlined,
                iconBg: nt.inverseSurface,
                iconColor: nt.onInverseSurface,
                label: l10n.settingsTheme,
                detail: themeDetail,
                isLast: true,
                onTap: () => _showThemePicker(context, ref),
              ),
            ],
          ),
          _SheetSection(
            label: l10n.settingsSupport,
            children: [
              _SheetRow(
                icon: Icons.help_outline_rounded,
                iconBg: nt.mist,
                iconColor: nt.forest,
                label: l10n.settingsHelpCenter,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.info_outline_rounded,
                iconBg: nt.mist,
                iconColor: nt.forest,
                label: l10n.settingsAbout,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.gavel_rounded,
                iconBg: nt.mist,
                iconColor: nt.forest,
                label: l10n.settingsTerms,
                isLast: true,
                onTap: () => _comingSoon(context),
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
              child: _SheetRow(
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
    );
  }

  static void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.comingSoon)),
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

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? detail;
  final bool showChevron;
  final bool isLast;
  final VoidCallback? onTap;

  const _SheetRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.detail,
    this.showChevron = true,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(16))
              : BorderRadius.zero,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  Text(detail!,
                      style: TextStyle(fontSize: 13, color: nt.text2)),
                  const SizedBox(width: 4),
                ],
                if (showChevron)
                  Icon(Icons.chevron_right, size: 20, color: nt.text3),
              ],
            ),
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
