import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

const _kSupportedLocales = [
  (code: 'en', flag: '🇬🇧', label: 'English'),
  (code: 'fr', flag: '🇫🇷', label: 'Français'),
];

class LocalePickerButton extends ConsumerWidget {
  const LocalePickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCode = ref.watch(localeProvider).languageCode;
    final current = _kSupportedLocales.firstWhere(
      (l) => l.code == currentCode,
      orElse: () => _kSupportedLocales.first,
    );

    return PopupMenuButton<String>(
      onSelected: (code) =>
          ref.read(localeProvider.notifier).setLocale(Locale(code)),
      color: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => _kSupportedLocales
          .map(
            (l) => PopupMenuItem<String>(
              value: l.code,
              child: Row(
                children: [
                  Text(l.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    l.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: kBark,
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
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(
              current.code.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kText2,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: kText3),
          ],
        ),
      ),
    );
  }
}
