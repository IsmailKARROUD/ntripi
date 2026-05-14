import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
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

    final hasPassport = passports.isNotEmpty;
    final hasResident = resident != null && resident.isNotEmpty;
    final hasLanguages = langs.isNotEmpty;

    if (!hasPassport && !hasResident && !hasLanguages) {
      return const SizedBox.shrink();
    }

    // Passport: full-width row — one Text entry per country.
    Widget? passportRow;
    if (hasPassport) {
      passportRow = _PassportRow(codes: passports);
    }

    final l10n = AppLocalizations.of(context)!;
    final residentChip = hasResident
        ? _IdentityFactChip(
            icon: Icons.location_on_rounded,
            subLabel: l10n.livesInLabel,
            value: countryByCode(resident)?.name ?? resident,
            prefix: countryByCode(resident)?.flag,
          )
        : null;

    final speaksChip = hasLanguages
        ? _IdentityFactChip(
            icon: Icons.translate_rounded,
            subLabel: l10n.speaksLabel,
            value: langs.map((c) => languageByCode(c)?.code ?? c).join(' · '),
          )
        : null;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (passportRow != null) passportRow,
        if (residentChip != null) residentChip,
        if (speaksChip != null) speaksChip,
      ],
    );
  }
}

class _PassportRow extends StatelessWidget {
  final List<String> codes;
  const _PassportRow({required this.codes});

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
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_rounded, size: 18, color: kForest),
          const SizedBox(width: 6),
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.passportLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: codes.map((c) {
                    final country = countryByCode(c);
                    final flag = country?.flag ?? '';
                    final name = country?.name ?? c;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '$flag $name',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kBark,
                          height: 1.2,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: kForest),
          const SizedBox(width: 6),
          IntrinsicWidth(
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
