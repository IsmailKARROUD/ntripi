// presentation/annotation_screen.dart — Full-screen annotation editor.
//
// Matches Screen 11 "Add annotation" from the design.
// Pushed via Navigator.push<AnnotationFormResult>. Returns the result on Save,
// null if the user backs out.
//
// Optional stopName / stopSubtitle show a context card at the top so the user
// knows which stop they are annotating.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_form_dialog.dart'
    show AnnotationFormResult;
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class AnnotationScreen extends StatefulWidget {
  final bool isEdit;
  final String? initialContent;
  final AnnotationType? initialType;

  /// When set, a stop-context card is shown at the top (stop-level annotations).
  final String? stopName;
  final String? stopSubtitle;

  /// When provided, the screen performs the save itself (shows a spinner,
  /// calls this callback, then pops). Use this when the caller needs to make
  /// an API call as part of saving — avoids showing a loading state on the
  /// previous screen after the annotation screen has already popped.
  ///
  /// When null the screen pops with the raw [AnnotationFormResult] and the
  /// caller handles persistence (existing behaviour for the detail screen).
  final Future<void> Function(AnnotationFormResult result)? onSaveAsync;

  const AnnotationScreen({
    super.key,
    required this.isEdit,
    this.initialContent,
    this.initialType,
    this.stopName,
    this.stopSubtitle,
    this.onSaveAsync,
  });

  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends State<AnnotationScreen> {
  late AnnotationType _type;
  late final TextEditingController _contentController;
  bool _saving = false;

  static const _palette = {
    AnnotationType.advice: (
      bg: Color(0xFFE0EBE4),
      fg: kForest,
      icon: Icons.lightbulb_rounded,
      label: 'Tip',
      desc: 'Something useful or pro-tip.',
    ),
    AnnotationType.caution: (
      bg: Color(0xFFFFE3CC),
      fg: Color(0xFFA05D1F),
      icon: Icons.warning_rounded,
      label: 'Caution',
      desc: 'Pay attention — surprises possible.',
    ),
    AnnotationType.avoid: (
      bg: Color(0xFFFFD6D2),
      fg: Color(0xFFA02828),
      icon: Icons.block_rounded,
      label: 'Avoid',
      desc: 'Don\'t do this. Save your time.',
    ),
    AnnotationType.info: (
      bg: Color(0xFFDCEAF6),
      fg: Color(0xFF3B6EA5),
      icon: Icons.info_rounded,
      label: 'Info',
      desc: 'A neutral fact worth knowing.',
    ),
  };

  // Baseline of the editable fields, captured after seeding from widget, so
  // backing out without changes does not trigger the discard confirmation.
  List<Object?>? _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? AnnotationType.advice;
    _contentController =
        TextEditingController(text: widget.initialContent ?? '');
    _initialSnapshot = _snapshot();
  }

  List<Object?> _snapshot() => [_type, _contentController.text];

  bool get _isDirty {
    final base = _initialSnapshot;
    if (base == null) return false;
    final now = _snapshot();
    if (now.length != base.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != base[i]) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    return confirmDestructiveAction(
      context: context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    final result = (content: content, type: _type);

    if (widget.onSaveAsync != null) {
      setState(() => _saving = true);
      try {
        await widget.onSaveAsync!(result);
        if (mounted) Navigator.pop(context);
      } on Exception catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } else {
      Navigator.pop<AnnotationFormResult>(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = widget.isEdit ? l10n.editAnnotationTitle : l10n.addAnnotationDialogTitle;
    final canSave = !_saving && _contentController.text.trim().isNotEmpty;

    return PopScope(
      // Block the back gesture/button while there are unsaved edits; the
      // callback then offers a discard confirmation.
      canPop: !_isDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: kSand,
      appBar: AppBar(
        backgroundColor: kSand,
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: NTripiRingLoader(size: 20),
            )
          else
            TextButton(
            onPressed: canSave ? _save : null,
            child: Text(
              widget.isEdit ? l10n.saveButton : l10n.addButton,
              style: TextStyle(
                color: canSave ? kForest : kText3,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, // allow dismissing the keyboard by dragging the list down
        children: [
          // ── Stop context card (optional) ──────────────────────────────────
          if (widget.stopName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: kMist,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.location_on_rounded,
                          size: 16, color: kForest),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.stopName!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kBark,
                            ),
                          ),
                          if (widget.stopSubtitle != null)
                            Text(
                              widget.stopSubtitle!,
                              style: const TextStyle(
                                  fontSize: 11, color: kText2),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Type selector ─────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 6),
            child: Text(
              'TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kText2,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.2,
              children: AnnotationType.values.map((t) {
                final p = _palette[t]!;
                final active = _type == t;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? p.bg : kSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? p.fg : kBorder,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: active
                                ? p.fg.withValues(alpha: 0.2)
                                : p.bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(p.icon, size: 16, color: p.fg),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.desc,
                          style: const TextStyle(
                            fontSize: 11,
                            color: kText2,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Message field ─────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 6),
            child: Text(
              'MESSAGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kText2,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
            ),
            child: TextField(
              controller: _contentController,
              autofocus: true,
              maxLines: 5,
              minLines: 3,
              onChanged: (_) => setState(() {}), // rebuild for Save enable
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.annotationContentHint,
                hintStyle:  TextStyle(color: kText3),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:  EdgeInsets.fromLTRB(16, 14, 16, 14),
              ),
              style: const TextStyle(
                fontSize: 14,
                color: kBark,
                height: 1.5,
              ),
            ),
          ),

          // Hint
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 6, 22, 0),
            child: Text(
              'Keep it short — under 200 characters reads best on small screens.',
              style: TextStyle(fontSize: 11, color: kText2),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Convenience function — matches the existing call-site API.
/// Pushes [AnnotationScreen] and returns the result.
Future<AnnotationFormResult?> showAnnotationScreen(
  BuildContext context, {
  bool isEdit = false,
  String? initialContent,
  AnnotationType? initialType,
  String? stopName,
  String? stopSubtitle,
  Future<void> Function(AnnotationFormResult result)? onSaveAsync,
}) {
  return Navigator.push<AnnotationFormResult>(
    context,
    MaterialPageRoute(
      builder: (_) => AnnotationScreen(
        isEdit: isEdit,
        initialContent: initialContent,
        initialType: initialType,
        stopName: stopName,
        stopSubtitle: stopSubtitle,
        onSaveAsync: onSaveAsync,
      ),
    ),
  );
}
