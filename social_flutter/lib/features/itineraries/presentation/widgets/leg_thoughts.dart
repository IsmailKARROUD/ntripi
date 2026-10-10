// widgets/leg_thoughts.dart — a transport leg's "Thoughts", for a reader.
//
// Shown under the leg on the trip page's transit card and in the stop page's
// Transit section — one widget, so the two cannot drift apart. Folded to two
// lines by ExpandableText. Plain text: the leg form is a plain field with no
// markdown toolbar, so a typed `#` or `*` has to stay a character.
//
// Translation rides the group already on screen — the trip's toggle on the trip
// page, the stop's on the stop page. legThoughtsMembers is what each screen adds
// to that group's members; neither page grows a toggle of its own.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/translation/presentation/translatable_text.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/shared/widgets/expandable_text.dart';

/// One translation member per leg that has thoughts.
List<TranslationMember> legThoughtsMembers(Iterable<TransportLeg> legs) => [
      for (final leg in legs)
        if (leg.hasNotes)
          TranslationMember(
            contentType: 'transport_leg',
            contentId: leg.id,
            sourceLang: leg.sourceLang,
            fields: {'notes': leg.notes},
          ),
    ];

class LegThoughts extends StatelessWidget {
  const LegThoughts({
    super.key,
    required this.leg,
    this.anchor,
    this.translate = true,
  });

  /// A leg with thoughts ([TransportLeg.hasNotes]).
  final TransportLeg leg;

  /// The group whose toggle covers this leg. Null shows the thoughts as written.
  final TranslationAnchor? anchor;

  /// False while the trip is being edited — whoever edits reads the original.
  final bool translate;

  @override
  Widget build(BuildContext context) {
    final anchor = this.anchor;
    if (anchor == null) return _thoughts(context, leg.notes!);
    return TranslatableText(
      anchor: anchor,
      contentType: 'transport_leg',
      contentId: leg.id,
      field: 'notes',
      original: leg.notes!,
      enabled: translate,
      builder: _thoughts,
    );
  }

  Widget _thoughts(BuildContext context, String text) {
    final nt = context.nt;
    return ExpandableText(
      text,
      expandOnTextTap: true,
      style: TextStyle(fontSize: 12.5, height: 1.4, color: nt.text2),
      // The transit palette, not nt.forest: forest falls to ~3.9:1 on the dark
      // transitBg, under AA for 12 px text.
      linkStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: nt.transitText,
      ),
    );
  }
}
