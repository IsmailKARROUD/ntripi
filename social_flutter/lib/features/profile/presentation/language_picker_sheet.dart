import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/languages.dart';

// Mirrors the backend cap in social_api/app/schemas/user.py (_check_languages).
const int _kMaxLanguages = 60;

/// Shows a multi-select language checklist and returns the full chosen set of
/// language codes. Closing the sheet any way — Done, back, or scrim-tap —
/// submits the current selection (see the PopScope below); the caller only
/// gets `null` if the sheet is somehow torn down without popping.
///
/// [selected] pre-ticks the languages the user already has so they can add or
/// remove in one pass.
Future<List<String>?> showLanguagePickerSheet(
  BuildContext context, {
  List<String> selected = const [],
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LanguagePickerSheet(initialSelected: selected),
  );
}

class _LanguagePickerSheet extends StatefulWidget {
  final List<String> initialSelected;
  const _LanguagePickerSheet({required this.initialSelected});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  // Codes are stored upper-cased to match the backend + Language.code casing.
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected.map((c) => c.toUpperCase()).toSet();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(String code) {
    final upper = code.toUpperCase();
    if (_selected.contains(upper)) {
      setState(() => _selected.remove(upper));
      return;
    }
    // Enforce the cap client-side so the user gets a clear message instead of a
    // 422 at save time. Mirror of the backend limit in schemas/user.py.
    if (_selected.length >= _kMaxLanguages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.maxLanguagesReached(_kMaxLanguages)),
        ),
      );
      return;
    }
    setState(() => _selected.add(upper));
  }

  List<Language> _filtered(String langCode) {
    final list = List<Language>.from(kLanguages);
    // Source list is EN-alphabetical; re-sort so FR users get FR order.
    list.sort((a, b) => a.localizedName(langCode).compareTo(b.localizedName(langCode)));
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase();
    // Match both spellings so "German" still finds "Allemand" and vice versa.
    return list
        .where((l) =>
            l.name.toLowerCase().contains(q) ||
            l.nameFr.toLowerCase().contains(q) ||
            l.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final langCode = Localizations.localeOf(context).languageCode;
    final filtered = _filtered(langCode);
    final media = MediaQuery.of(context);
    // 70% of the screen, and never tall enough to push the Done row up under
    // the status bar on short devices.
    final sheetHeight = math.min(
      media.size.height * 0.5,
      media.size.height - media.padding.top - 12,
    );
    // canPop:false so back-button / scrim-tap / drag-dismiss all route through
    // onPopInvokedWithResult and submit the current selection (close = submit).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_selected.toList());
      },
      // Material, not a coloured DecoratedBox: the rows are ListTiles, which
      // paint their background and ink splash on the nearest Material ancestor
      // — a coloured box in between hides both (Flutter asserts on it).
      child: Material(
        color: nt.sand,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        // A fixed height, not a maximum: the sheet is bottom-anchored, so any
        // height change (keyboard inset, a search that narrows the list) would
        // walk its top edge — and Done with it — up and down the screen.
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: nt.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.selectLanguagesTitle,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: nt.bark,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    // Live count against the cap — plain digits, locale-agnostic.
                    Text(
                      '${_selected.length}/$_kMaxLanguages',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: nt.text2,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selected.toList()),
                      style: TextButton.styleFrom(foregroundColor: nt.forest),
                      child: Text(
                        l10n.done,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.languageSearchHint,
                    hintStyle: TextStyle(color: nt.text3, fontSize: 15),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: nt.text2, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: nt.text2),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: nt.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: nt.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: nt.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: nt.forest, width: 1.5),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  // The keyboard overlays the sheet rather than resizing it, so
                  // pad the scroll extent by its height or the last rows can
                  // never be scrolled out from behind it.
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  // Scrolling the list puts the keyboard away, which is the only
                  // way back to the full-height list once search has focus.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final lang = filtered[index];
                    final isSelected = _selected.contains(lang.code);
                    return ListTile(
                      onTap: () => _toggle(lang.code),
                      // Leading check indicator: filled when selected, outline when not.
                      leading: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? nt.forest : nt.text3,
                        size: 22,
                      ),
                      title: Text(
                        lang.localizedName(langCode),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: nt.bark,
                        ),
                      ),
                      trailing: Text(
                        lang.code,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: nt.text2,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
