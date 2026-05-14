import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/data/countries.dart';
import 'package:social_flutter/shared/data/languages.dart';
import 'package:social_flutter/shared/models/user.dart';

/// Horizontal row of up to three identity fact chips:
///   Passport  |  Lives in  |  Speaks
///
/// Only renders chips for fields that are set (non-null / non-empty).
/// If all three are empty, renders nothing (zero height).
class ProfileIdentityFacts extends StatelessWidget {
  final User user;

  const ProfileIdentityFacts({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final passports = user.passportCountries ?? [];
    final resident = user.residentCountry;
    final langs = user.languages ?? [];

    final chips = <Widget>[];

    if (passports.isNotEmpty) {
      final flags = passports
          .map((c) => countryByCode(c)?.flag ?? '')
          .where((f) => f.isNotEmpty)
          .join('');
      final codes = passports.join(' · ');
      chips.add(_IdentityFactChip(
        icon: Icons.badge_rounded,
        subLabel: 'Passport',
        value: codes,
        prefix: flags.isNotEmpty ? flags : null,
      ));
    }

    if (resident != null && resident.isNotEmpty) {
      final country = countryByCode(resident);
      chips.add(_IdentityFactChip(
        icon: Icons.location_on_rounded,
        subLabel: 'Lives in',
        value: country?.name ?? resident,
        prefix: country?.flag,
      ));
    }

    if (langs.isNotEmpty) {
      final label = langs
          .map((c) => languageByCode(c)?.code ?? c)
          .join(' · ');
      chips.add(_IdentityFactChip(
        icon: Icons.translate_rounded,
        subLabel: 'Speaks',
        value: label,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      children: chips
          .map((chip) => Expanded(child: chip))
          .toList()
          // Add 6px gaps between chips
          .fold<List<Widget>>([], (acc, w) {
            if (acc.isNotEmpty) acc.add(const SizedBox(width: 6));
            acc.add(w);
            return acc;
          }),
    );
  }
}

class _IdentityFactChip extends StatelessWidget {
  final IconData icon;
  final String subLabel;
  final String value;
  final String? prefix; // flag emoji(s)

  const _IdentityFactChip({
    required this.icon,
    required this.subLabel,
    required this.value,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: kForest),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  prefix != null ? '$prefix $value' : value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
