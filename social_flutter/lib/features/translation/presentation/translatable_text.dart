// features/translation/presentation/translatable_text.dart — "See translation"
// on screen: the text that swaps, and the link that swaps it.
//
// One TranslationToggle covers a group — a trip's header with its trip-wide
// notes, a stop with its notes and annotations, one review — and every
// TranslatableText in that group watches the same notifier, so one tap swaps
// them all. Read mode only: an editor always works on the original.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

/// The reader's language — the only language anything is translated into.
String _readerLang(WidgetRef ref) =>
    ref.watch(localeProvider.select((locale) => locale.languageCode));

/// One field of user content: its original, or its translation once the
/// group's toggle has been tapped.
class TranslatableText extends ConsumerWidget {
  const TranslatableText({
    super.key,
    required this.anchor,
    required this.contentType,
    required this.contentId,
    required this.field,
    required this.original,
    required this.builder,
    this.enabled = true,
  });

  /// The group this field belongs to — the same anchor its toggle names.
  final TranslationAnchor anchor;
  final String contentType;
  final String contentId;
  final String field;
  final String original;

  /// Builds the text; called with the original or the translation.
  final Widget Function(BuildContext context, String text) builder;

  /// False in edit mode: whoever is editing reads what they are changing.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) return builder(context, original);
    final lang = _readerLang(ref);
    final config = ref.watch(translationConfigProvider).value;
    // Translation off: no notifier is created for content nobody can toggle.
    if (config == null || !config.offers(lang)) return builder(context, original);
    final translated = ref.watch(
      contentTranslationProvider(translationKey(anchor, lang)).select(
          (state) => state.textFor(contentType, contentId, field, original)),
    );
    if (translated == null) return builder(context, original);
    // Laid out by the language it is in. Today that is always the app's own, so
    // this restates the ambient direction — and keeps it right if the two ever
    // differ.
    return Directionality(
      textDirection:
          isRtlLanguage(lang) ? TextDirection.rtl : TextDirection.ltr,
      child: builder(context, translated),
    );
  }
}

/// "See translation" → "Translating…" → "Automatically translated · See
/// original". Draws nothing when translation is off, the app language is not
/// a target, or every member is already in the reader's language.
class TranslationToggle extends ConsumerWidget {
  const TranslationToggle({
    super.key,
    required this.anchor,
    required this.members,
    this.padding = EdgeInsets.zero,
  });

  final TranslationAnchor anchor;

  /// Everything the toggle covers, with the text each field holds now.
  final List<TranslationMember> members;

  /// Applied only when something is drawn, so a hidden toggle leaves no gap.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = _readerLang(ref);
    final config = ref.watch(translationConfigProvider).value;
    if (config == null || !config.offers(lang)) return const SizedBox.shrink();
    final offered = [
      for (final m in members)
        if (m.offersTo(lang)) m,
    ];
    if (offered.isEmpty) return const SizedBox.shrink();

    final key = translationKey(anchor, lang);
    final state = ref.watch(contentTranslationProvider(key));
    // The server found nothing to translate: every field blank or already in
    // the reader's language. Asked again only once the text changes.
    if (state.isFreshFor(offered) && !state.translatesAny(offered)) {
      return const SizedBox.shrink();
    }

    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(contentTranslationProvider(key).notifier);
    // Watched, not read on tap: an unwatched stream reads as still loading,
    // which would count as online. Optimistic while it seeds, as everywhere.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final labelStyle = TextStyle(fontSize: 12.5, color: nt.text3);
    final linkStyle = TextStyle(
      fontSize: 12.5,
      color: nt.forest,
      fontWeight: FontWeight.w600,
    );

    final Widget line;
    if (state.phase == TranslationPhase.loading) {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: nt.text3),
          ),
          const SizedBox(width: 8),
          Text(l10n.translationTranslating, style: labelStyle),
        ],
      );
    } else if (state.phase == TranslationPhase.shown &&
        state.translatesAny(offered)) {
      line = _Link(
        onTap: notifier.showOriginal,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${l10n.translationAutoTranslated} · '),
            TextSpan(text: l10n.translationSeeOriginal, style: linkStyle),
          ]),
          style: labelStyle,
        ),
      );
    } else {
      final problem = state.phase == TranslationPhase.failed
          ? switch (state.problem) {
              TranslationProblem.rateLimited => l10n.translationRateLimited,
              TranslationProblem.unavailable => l10n.translationUnavailable,
              _ => l10n.translationFailed,
            }
          : null;
      line = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Link(
            onTap: () {
              // Answers already held need no network; anything else does.
              if (!online && !state.isFreshFor(offered)) {
                showOfflineHint(context);
                return;
              }
              notifier.translate(members);
            },
            child: Text(l10n.translationSeeTranslation, style: linkStyle),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(problem, style: labelStyle),
            ),
        ],
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.translate_rounded, size: 15, color: nt.text3),
          ),
          const SizedBox(width: 6),
          Flexible(child: line),
        ],
      ),
    );
  }
}

/// A text link with a usable tap target and a button role for screen readers.
class _Link extends StatelessWidget {
  const _Link({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        // Its own node, so the link is not merged into a surrounding row.
        container: true,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: child,
          ),
        ),
      );
}
