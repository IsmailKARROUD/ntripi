import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/app_locales.dart';

class LocalePickerButton extends ConsumerWidget {
  const LocalePickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final currentCode = ref.watch(localeProvider).languageCode;
    final current = kAppLocales.firstWhere(
      (l) => l.code == currentCode,
      orElse: () => kAppLocales.first,
    );

    return PopupMenuButton<String>(
      onSelected: (code) =>
          ref.read(localeProvider.notifier).setLocale(Locale(code)),
      color: nt.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => kAppLocales
          .map(
            (l) => PopupMenuItem<String>(
              value: l.code,
              child: Row(
                children: [
                  Text(l.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    localeLabel(l10n, l.code),
                    style: TextStyle(
                      fontSize: 14,
                      color: nt.bark,
                      fontWeight: l.code == currentCode
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: nt.surface,
          border: Border.all(color: nt.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(
              current.code.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: nt.text2,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: nt.text3),
          ],
        ),
      ),
    );
  }
}
