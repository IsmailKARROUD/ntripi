import 'package:flutter/material.dart';
import 'package:ntripi/core/router/app_links.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// The line above the sign-in and sign-up forms while a shared link waits for
/// the sign-in. A share page's "See the full trip" lands a visitor here, and a
/// bare form would not say what it is for.
///
/// Listens to [parkedAppLink], so a link tapped while the screen is already
/// open shows the line too, and it goes once the sign-in takes the link.
class ParkedLinkNotice extends StatelessWidget {
  const ParkedLinkNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: parkedAppLink,
      builder: (context, location, _) {
        final kind = parkedLinkKind(location);
        if (kind == null) return const SizedBox.shrink();
        final nt = context.nt;
        final l10n = AppLocalizations.of(context)!;
        final trip = kind == ParkedLinkKind.trip;
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: nt.mist,
              borderRadius: BorderRadius.circular(NtripiRadius.tile),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  trip ? Icons.map_outlined : Icons.person_outline_rounded,
                  size: 18,
                  color: nt.forest,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trip ? l10n.signInToOpenTrip : l10n.signInToOpenProfile,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: nt.forest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
