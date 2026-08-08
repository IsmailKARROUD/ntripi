// shared/widgets/date_of_birth_field.dart
//
// The birthdate input, shared by all three places that collect one: the
// register screen, the Google consent sheet, and the ToS re-acceptance gate.
// One widget rather than three, because the minimum-age rule and the "no
// default date" property below have to hold identically everywhere.
//
// A FormField<DateTime> rather than a TextFormField: it participates in the
// register screen's existing Form validation without asking the user to parse
// a date format that differs across our six locales.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Must stay in step with MINIMUM_AGE in app/services/age_service.py. The
/// server is the authority — this only spares the user a round trip.
const int kMinimumAge = 16;

const int _maxPlausibleAge = 120;

class DateOfBirthField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Shown instead of the hint before anything is picked. Used by the Google
  /// path when the People API supplied a date — the user still sees it and can
  /// change it, so it is a prefill, never a silent assertion.
  final String? hintOverride;

  final bool enabled;

  const DateOfBirthField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintOverride,
    this.enabled = true,
  });

  static bool isOldEnough(DateTime dob, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var age = today.year - dob.year;
    // Same boundary as the server's tuple compare: a birthday later this year
    // has not happened yet, which is what makes Feb-29 births land correctly.
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age -= 1;
    }
    return age >= kMinimumAge;
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Null until something is picked, deliberately: opening on a plausible
      // adult birthday is a leading question, and a neutral age screen is the
      // whole point. Re-opening keeps whatever was chosen last.
      initialDate: value,
      firstDate: DateTime(now.year - _maxPlausibleAge, now.month, now.day),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: AppLocalizations.of(context)!.dobPickerHelp,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // Locale-aware so a French user is never shown 8/8/2026 meaning August.
    final formatter = DateFormat.yMMMMd(Localizations.localeOf(context).toString());

    return FormField<DateTime>(
      initialValue: value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) {
        if (value == null) return l10n.registerDobRequired;
        if (!isOldEnough(value!)) return l10n.registerDobTooYoung(kMinimumAge);
        return null;
      },
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: enabled ? () => _pick(context) : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  errorText: state.errorText,
                  suffixIcon: Icon(Icons.calendar_today_outlined,
                      size: 18, color: nt.text3),
                ),
                child: Text(
                  value != null
                      ? formatter.format(value!)
                      : (hintOverride ?? l10n.registerDobHint),
                  style: TextStyle(
                    fontSize: 15,
                    color: value != null ? nt.bark : nt.text3,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
