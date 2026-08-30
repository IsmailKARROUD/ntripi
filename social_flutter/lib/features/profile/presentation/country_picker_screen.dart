import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/countries.dart';

/// Full-screen country picker.
///
/// Push this route and await the result — it returns a [String] country code
/// on selection, or `null` if the user taps "Clear" (when [allowClear] is
/// true) or presses back without selecting.
///
/// Usage:
///   final code = await Navigator.of(context).push<String?>(
///     MaterialPageRoute(builder: (_) => CountryPickerScreen(allowClear: true)),
///   );
class CountryPickerScreen extends StatefulWidget {
  /// When true, shows a "None / Clear" option at the top.
  final bool allowClear;

  /// Country codes to exclude from the list (already selected elsewhere).
  final List<String> exclude;

  const CountryPickerScreen({
    super.key,
    this.allowClear = false,
    this.exclude = const [],
  });

  @override
  State<CountryPickerScreen> createState() => _CountryPickerScreenState();
}

class _CountryPickerScreenState extends State<CountryPickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Country> _filtered(String langCode) {
    final excluded = widget.exclude.map((c) => c.toUpperCase()).toSet();
    final list = kCountries.where((c) => !excluded.contains(c.code)).toList();
    // Source list is EN-alphabetical; re-sort so FR users get FR order.
    list.sort((a, b) => a.localizedName(langCode).compareTo(b.localizedName(langCode)));
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase().trim();
    // Match both spellings so "Germany" still finds "Allemagne" and vice versa.
    return list
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.nameFr.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final langCode = Localizations.localeOf(context).languageCode;
    final filtered = _filtered(langCode);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: nt.surface,
      appBar: AppBar(
        backgroundColor: nt.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: nt.bark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.countryPickerTitle,
          style: TextStyle(
            color: nt.bark,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.countrySearchHint,
                hintStyle: TextStyle(color: nt.text3, fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded, color: nt.text2, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: nt.text2),
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
              itemCount: filtered.length + (widget.allowClear ? 1 : 0),
              itemBuilder: (context, index) {
                if (widget.allowClear && index == 0) {
    final nt = context.nt;
                  return ListTile(
                    leading: Icon(Icons.block_rounded, color: nt.text2, size: 20),
                    title: Text(
                      AppLocalizations.of(context)!.countryNoneClear,
                      style: TextStyle(color: nt.text2, fontWeight: FontWeight.w500),
                    ),
                    onTap: () => Navigator.of(context).pop(''),
                  );
                }
                final country = filtered[index - (widget.allowClear ? 1 : 0)];
                return ListTile(
                  leading: Text(
                    country.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    country.localizedName(langCode),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: nt.bark,
                    ),
                  ),
                  trailing: Text(
                    country.code,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: nt.text2,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(country.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
