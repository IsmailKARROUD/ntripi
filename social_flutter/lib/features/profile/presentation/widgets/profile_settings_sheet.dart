import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
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
    final currentCode = ref.read(localeProvider).languageCode;

    final languages = [
      (code: 'en', label: l10n.languageEnglish),
      (code: 'fr', label: l10n.languageFrench),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: kSand,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.languagePickerTitle.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < languages.length; i++) ...[
                      if (i > 0)
                        Container(
                          height: 1,
                          color: kBorder,
                          margin: const EdgeInsets.only(left: 16),
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
                                  color: kMist,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  languages[i].code.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: kForest,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  languages[i].label,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: kBark,
                                  ),
                                ),
                              ),
                              if (currentCode == languages[i].code)
                                const Icon(Icons.check_rounded,
                                    size: 18, color: kForest),
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
    final currentLocale = ref.watch(localeProvider);
    final langDetail = currentLocale.languageCode == 'fr'
        ? l10n.languageFrench
        : l10n.languageEnglish;

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              color: kText3.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.settingsTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kBark,
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
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsNotifications,
                detail: l10n.settingsNotificationsOff,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.language_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsLanguage,
                detail: langDetail,
                isLast: true,
                onTap: () => _showLanguagePicker(context, ref),
              ),
            ],
          ),
          _SheetSection(
            label: l10n.settingsSupport,
            children: [
              _SheetRow(
                icon: Icons.help_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsHelpCenter,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.info_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsAbout,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.gavel_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
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
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: _SheetRow(
                icon: Icons.logout_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kText2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kBark,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  Text(detail!,
                      style: const TextStyle(fontSize: 13, color: kText2)),
                  const SizedBox(width: 4),
                ],
                if (showChevron)
                  const Icon(Icons.chevron_right, size: 20, color: kText3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsets.only(left: 56),
            color: kBorder,
          ),
      ],
    );
  }
}
