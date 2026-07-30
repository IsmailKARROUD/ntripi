// shared/widgets/moderation_hint.dart — the advisory line under a prose field.
//
// Debounced so it appears once the writer pauses, never mid-word. Wraps a
// child field rather than replacing it, so adding the hint to a form is a
// one-line change and the field keeps its own decoration.
//
// It is advisory by construction: this widget has no way to disable anything.
// The submit control is the caller's, and nothing here can reach it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:social_flutter/core/moderation/text_precheck.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class ModerationHint extends StatefulWidget {
  final TextEditingController controller;
  final Widget child;

  /// Test seam — the real wordlist can't load under `flutter test`, and its
  /// failure mode is (correctly) "clean", so the hint could never fire.
  @visibleForTesting
  final Future<bool> Function(String text)? checker;

  const ModerationHint({
    super.key,
    required this.controller,
    required this.child,
    this.checker,
  });

  @override
  State<ModerationHint> createState() => _ModerationHintState();
}

class _ModerationHintState extends State<ModerationHint> {
  static const _debounce = Duration(milliseconds: 600);

  Timer? _timer;
  bool _flagged = false;

  @override
  void initState() {
    super.initState();
    // Load the wordlists now so the first check after a pause is instant.
    if (widget.checker == null) warmUpTextPrecheck();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _timer?.cancel();
    _timer = Timer(_debounce, _check);
  }

  Future<void> _check() async {
    // A checker that throws must never surface as a crash — see the never-block
    // contract in text_precheck.dart. Any failure reads as clean.
    bool flagged;
    try {
      flagged = await (widget.checker ?? looksOffensive)(widget.controller.text);
    } catch (_) {
      flagged = false;
    }
    if (!mounted || flagged == _flagged) return;
    setState(() => _flagged = flagged);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.child,
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topLeft,
          child: _flagged
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: nt.text2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.moderationHintTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: nt.text2,
                              ),
                            ),
                            Text(
                              l10n.moderationHintBody,
                              style: TextStyle(fontSize: 12, color: nt.text3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
