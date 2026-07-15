import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Compact System/Light/Dark picker pill for pre-auth screens — the styling
/// twin of [LocalePickerButton], for users who have no settings sheet yet.
class ThemePickerButton extends ConsumerWidget {
  const ThemePickerButton({super.key});

  static const _icons = {
    ThemeMode.system: Icons.brightness_auto_rounded,
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      ThemeMode.system: l10n.themeSystem,
      ThemeMode.light: l10n.themeLight,
      ThemeMode.dark: l10n.themeDark,
    };
    final current = ref.watch(themeModeProvider);

    return PopupMenuButton<ThemeMode>(
      onSelected: (mode) =>
          ref.read(themeModeProvider.notifier).setMode(mode),
      color: nt.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => ThemeMode.values
          .map(
            (mode) => PopupMenuItem<ThemeMode>(
              value: mode,
              child: Row(
                children: [
                  Icon(_icons[mode], size: 18, color: nt.forest),
                  const SizedBox(width: 12),
                  Text(
                    labels[mode]!,
                    style: TextStyle(
                      fontSize: 14,
                      color: nt.bark,
                      fontWeight:
                          mode == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        // inverse of the page surface so the pill stands out on the plain
        // auth background: dark pill in light mode, light pill in dark mode
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: nt.inverseSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[current], size: 18, color: nt.onInverseSurface),
            const SizedBox(width: 5),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: nt.onInverseSurface.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
