import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/languages.dart';

/// Shows a bottom sheet language picker and returns the selected language code,
/// or `null` if the user dismisses without selecting.
///
/// Already-selected language codes are excluded from the list.
Future<String?> showLanguagePickerSheet(
  BuildContext context, {
  List<String> exclude = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LanguagePickerSheet(exclude: exclude),
  );
}

class _LanguagePickerSheet extends StatefulWidget {
  final List<String> exclude;
  const _LanguagePickerSheet({required this.exclude});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Language> _filtered(String langCode) {
    final excluded = widget.exclude.map((c) => c.toUpperCase()).toSet();
    final list = kLanguages.where((l) => !excluded.contains(l.code)).toList();
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
    final langCode = Localizations.localeOf(context).languageCode;
    final filtered = _filtered(langCode);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: kSand,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: kBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context)!.addLanguageTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.languageSearchHint,
                hintStyle: const TextStyle(color: kText3, fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded, color: kText2, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: kText2),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: kSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kForest, width: 1.5),
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final lang = filtered[index];
                return ListTile(
                  title: Text(
                    lang.localizedName(langCode),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: kBark,
                    ),
                  ),
                  trailing: Text(
                    lang.code,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(lang.code),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
