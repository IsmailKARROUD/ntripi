import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
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

  List<Country> get _filtered {
    final excluded = widget.exclude.map((c) => c.toUpperCase()).toSet();
    final list = kCountries.where((c) => !excluded.contains(c.code)).toList();
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase().trim();
    return list
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: kSand,
      appBar: AppBar(
        backgroundColor: kSand,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kBark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Select country',
          style: TextStyle(
            color: kBark,
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
                hintText: 'Search countries…',
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
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length + (widget.allowClear ? 1 : 0),
              itemBuilder: (context, index) {
                if (widget.allowClear && index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.block_rounded, color: kText2, size: 20),
                    title: const Text(
                      'None / Clear',
                      style: TextStyle(color: kText2, fontWeight: FontWeight.w500),
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
                    country.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: kBark,
                    ),
                  ),
                  trailing: Text(
                    country.code,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kText2,
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
