// presentation/itinerary_form_screen.dart — Create or edit an itinerary header.
//
// Shared by two flows controlled by ItineraryFormMode:
//
//   CREATE  — user fills the form and taps Save.
//             Step 1: POST /itineraries  → gets the new ID.
//             Step 2: POST /itineraries/{id}/image  (only if image was picked).
//             Image upload is intentionally non-fatal: if it fails the itinerary
//             still exists and the user can add the image later from the edit flow.
//
//   EDIT    — form is pre-filled from itineraryDetailProvider (already cached).
//             Image upload/delete runs BEFORE the header PATCH so the provider
//             refresh triggered by updateHeader reflects the final image state.
//
// Cover image upload is deferred in CREATE mode because the upload endpoint
// requires an itinerary ID that doesn't exist yet when the form opens.

import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/visibility_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

/// Whether this form is creating a new itinerary or editing an existing one.
enum ItineraryFormMode { create, edit }

/// Maps each visibility level to its wire-format string for API payloads.
const _visibilityToString = {
  ItineraryVisibility.public: 'public',
  ItineraryVisibility.followers: 'followers',
  ItineraryVisibility.restricted: 'restricted',
  ItineraryVisibility.onlyMe: 'only_me',
};

class ItineraryFormScreen extends ConsumerStatefulWidget {
  /// Null in create mode; the itinerary ID in edit mode.
  final String? itineraryId;

  const ItineraryFormScreen({super.key, this.itineraryId});

  ItineraryFormMode get mode =>
      itineraryId == null ? ItineraryFormMode.create : ItineraryFormMode.edit;

  @override
  ConsumerState<ItineraryFormScreen> createState() =>
      _ItineraryFormScreenState();
}

class _ItineraryFormScreenState extends ConsumerState<ItineraryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _titleFocusNode = FocusNode();
  List<Currency> _currencies = [];

  String? _currency = 'EUR';

  ItineraryVisibility _visibility = ItineraryVisibility.public;
  bool _saving = false;
  // Guards _initFromProvider so rebuilds don't overwrite the user's edits.
  bool _initialized = false;
  // Create-mode only: collapses cover image + BASICS so the user only sees
  // the mandatory title until they expand. Defaults handle a no-touch save.
  bool _showOptional = false;

  // Cover image state — deferred upload on create, immediate on edit.
  Uint8List? _pendingImageBytes;
  String? _pendingImageFilename;
  bool _removeExistingImage = false;

  Future<void> loadCurrencies() async {
    try {
      // 1. Load the string
      final String response =
          await rootBundle.loadString('assets/data/currencies.json');

      // 2. Decode and cast
      final List<dynamic> data = json.decode(response);

      // 3. Filter the raw maps FIRST, then convert to Dart objects
      final currencies = data
          .where((item) => item['type'] == 'currency') // <-- Optimization here
          .map((item) => Currency.fromJson(item))
          .toList();

      // 4. Sort
      currencies.sort((a, b) => a.code.compareTo(b.code));

      // 5. Update State
      setState(() {
        _currencies = currencies;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.currenciesLoadFailed(e.toString()))),
      );
    }
  }

  // static const _currencies = ['EUR', 'USD', 'GBP', 'MAD', 'Other'];

  // Baseline of all user-editable fields, captured once the form is populated.
  // Compared against the live values to detect unsaved edits before leaving.
  List<Object?>? _initialSnapshot;

  @override
  void initState() {
    super.initState();
    loadCurrencies();
    if (widget.mode == ItineraryFormMode.edit) {
      // postFrameCallback: setState can't be called during initState itself.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initFromProvider());
    } else {
      _initialSnapshot = _snapshot();
    }
  }

  // _currencies is the dropdown source list, not user input — excluded here.
  List<Object?> _snapshot() => [
        _titleController.text,
        _descriptionController.text,
        _currency,
        _visibility,
        _pendingImageBytes != null,
        _removeExistingImage,
      ];

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
      icon: Icons.logout,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
  }

  void _initFromProvider() {
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId!)).value;
    if (itinerary == null || _initialized) return;
    setState(() {
      _titleController.text = itinerary.title;
      _descriptionController.text = itinerary.description ?? '';
      _currency = _currencies.contains(itinerary.currency)
          ? itinerary.currency
          : 'Other';
      _visibility = itinerary.visibility;
      _initialized = true;
    });
    // Capture baseline after fields are populated, so opening to edit and
    // leaving without changes does not trigger the discard dialog.
    _initialSnapshot = _snapshot();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  // The R2 storage key never changes between uploads (always itineraries/{id}.jpg),
  // so CachedNetworkImage's disk cache would keep serving the old bytes.
  // evictFromCache clears both the on-disk file (DefaultCacheManager) and the
  // in-memory ImageCache entry, forcing the next render to refetch.
  Future<void> _evictCoverImageCache() async {
    final url = ref
        .read(itineraryDetailProvider(widget.itineraryId!))
        .value
        ?.coverImageUrl;
    if (url == null) return;
    final absUrl = url.startsWith('/') ? '$kApiBaseUrl$url' : url;
    await CachedNetworkImage.evictFromCache(
      absUrl,
      cacheManager: NtripiImageCacheManager(),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
        // 'Other' is a UI-only placeholder; fall back to EUR for the API.
        'currency': _currency == 'Other' ? 'EUR' : _currency,
        'visibility': _visibilityToString[_visibility],
      };

      final repo = ref.read(itineraryRepositoryProvider);

      if (widget.mode == ItineraryFormMode.create) {
        // Step 1: create itinerary to obtain the ID.
        final itinerary =
            await ref.read(myItinerariesProvider.notifier).addItinerary(data);

        // Step 2: upload cover image if one was selected.
        // If this fails we show a warning but still navigate — the itinerary
        // was created successfully and the image can be added later from the
        // edit screen.
        if (_pendingImageBytes != null && mounted) {
          try {
            await repo.uploadCoverImage(
              itineraryId: itinerary.id,
              bytes: _pendingImageBytes!,
              filename: _pendingImageFilename ?? 'cover.jpg',
            );
          } on Exception {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      AppLocalizations.of(context)!.imageSaveButUploadFailed),
                ),
              );
            }
          }
        }

        if (!mounted) return;
        // justCreated → detail screen auto-shows the "tap Edit to add stops" hint once.
        context.go('/itineraries/${itinerary.id}', extra: {'justCreated': true});
      } else {
        // Edit flow: image changes are applied BEFORE the header PATCH.
        // Order matters: updateHeader (below) does a partial copyWith on the
        // cached provider state. Mutating the image first means the provider
        // already holds the correct cover_image_url when the PATCH response
        // arrives, so no extra refresh is needed.
        if (_removeExistingImage) {
          // User tapped "Remove" — delete the file from R2.
          await repo.deleteCoverImage(widget.itineraryId!);
          await _evictCoverImageCache();
        } else if (_pendingImageBytes != null) {
          // User picked a new image — replace the file in R2.
          // _evictCoverImageCache() clears CachedNetworkImage's disk + memory
          // cache so the next render fetches the fresh file instead of the
          // stale cached bytes (the R2 key is always itineraries/{id}.jpg and
          // never changes).
          await repo.uploadCoverImage(
            itineraryId: widget.itineraryId!,
            bytes: _pendingImageBytes!,
            filename: _pendingImageFilename ?? 'cover.jpg',
          );
          await _evictCoverImageCache();
        }

        await ref
            .read(itineraryDetailProvider(widget.itineraryId!).notifier)
            .updateHeader(data);
        if (!mounted) return;
        context.pop();
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItinerary() async {
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId!)).value;
    final title = itinerary?.title ?? 'this itinerary';
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmTypedDestructiveAction(
      context: context,
      title: l10n.deleteItineraryFormTitle,
      message: l10n.deleteItineraryFormMessage(title),
      requiredText: title,
      hintText: title,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(myItinerariesProvider.notifier)
          .removeItinerary(widget.itineraryId!);
      if (!mounted) return;
      router.go('/itineraries');
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  // ── Picker helpers ──────────────────────────────────────────────────────────

  Future<void> _showCurrencyPicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CurrencyPickerSheet(
        currencies: _currencies,
        selected: _currency,
      ),
    );
    if (picked != null && mounted) setState(() => _currency = picked);
  }

  Future<void> _showVisibilityPicker() async {
    final picked = await Navigator.push<ItineraryVisibility>(
      context,
      MaterialPageRoute(
        builder: (_) => VisibilityScreen(
          initial: _visibility,
          itineraryId: widget.itineraryId, // null in create mode
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _visibility = picked);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visLabel = _visibilityLabel(_visibility, l10n);
    final visIcon = _visibilityIcon(_visibility);
    final visColor = _visibilityColor(_visibility);
    // Only the title is mandatory at creation — hide the rest behind a toggle
    // so first-time users can save fast. Edit mode always shows everything.
    final bool collapseOptional =
        widget.mode == ItineraryFormMode.create && !_showOptional;

    return PopScope(
      // Block the back gesture/button while there are unsaved edits; the
      // callback then offers a discard confirmation. The save flow uses
      // context.go/pop directly, so it is unaffected by this guard.
      canPop: !_isDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: kSand,
      appBar: AppBar(
        backgroundColor: kSand,
        title: Text(widget.mode == ItineraryFormMode.create
            ? l10n.newItinerary
            : l10n.editItinerary),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: NTripiRingLoader(size: 20),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                l10n.save,
                style: const TextStyle(
                  color: kForest,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ── Title  ───────────────────────────────────────────
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  // Title field — opaque GestureDetector so taps on the label
                  // and empty space in the padded column also focus the input.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _titleFocusNode.requestFocus,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.itineraryTitleLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kText2,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _titleController,
                            focusNode: _titleFocusNode,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: l10n.itineraryTitleHint,
                              hintStyle: const TextStyle(
                                  color: kText3, fontWeight: FontWeight.w500),
                            ),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: kBark,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l10n.itineraryTitleRequired
                                : null,
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // ── Optional fields toggle (create mode only) ─────────────────
              if (widget.mode == ItineraryFormMode.create)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.center,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _showOptional = !_showOptional),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showOptional
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: kForest,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showOptional
                                  ? l10n.hideOptionalFields
                                  : l10n.showOptionalFields,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kForest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!collapseOptional) ...[
                // ── Cover image slot ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: CoverImageField(
                    initialUrl: widget.mode == ItineraryFormMode.edit
                        ? ref
                            .read(itineraryDetailProvider(widget.itineraryId!))
                            .value
                            ?.coverImageUrl
                        : null,
                    onImageSelected: (bytes, filename) => setState(() {
                      _pendingImageBytes = bytes;
                      _pendingImageFilename = filename;
                      _removeExistingImage = false;
                    }),
                    onImageRemoved: () => setState(() {
                      _pendingImageBytes = null;
                      _pendingImageFilename = null;
                      _removeExistingImage = true;
                    }),
                  ),
                ),

                // ── Basics ──────────────────────────────────────────────────
                _SectionLabel(text: l10n.formSectionBasics),
                _SectionCard(
                  children: [
                    _PickerRow(
                      icon: Icons.payments_rounded,
                      label: l10n.formLabelCurrency,
                      value: _currency ?? 'EUR',
                      onTap: _showCurrencyPicker,
                    ),
                    const _FieldDivider(),
                    _PickerRow(
                      icon: visIcon,
                      label: l10n.formLabelWhoCanSee,
                      value: visLabel,
                      iconColor: visColor,
                      onTap: _showVisibilityPicker,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 48),
              // ── Danger zone (edit mode) ───────────────────────────────────
              if (widget.mode == ItineraryFormMode.edit) ...[
                _SectionLabel(text: l10n.formSectionDangerZone, tone: kRatingRed),
                _SectionCard(
                  children: [
                    _PickerRow(
                      icon: Icons.delete_outline_rounded,
                      label: l10n.formLabelDeleteItinerary,
                      value: l10n.formDeleteItineraryHint,
                      iconColor: kRatingRed,
                      onTap: _saving ? null : _deleteItinerary,
                    ),
                  ],
                ),
              ],

              //   const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Form-level private widgets ───────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color tone;

  const _SectionLabel({required this.text, this.tone = kText2});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tone,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 1, color: kBorder, margin: const EdgeInsets.only(left: 16));
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = iconColor ?? kForest;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kMist,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kBark,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: kText3),
          ],
        ),
      ),
    );
  }
}

// ─── Currency picker bottom sheet ────────────────────────────────────────────
class _CurrencyPickerSheet extends StatefulWidget {
  final List<Currency> currencies;
  final String? selected;

  const _CurrencyPickerSheet(
      {required this.currencies, required this.selected});

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.currencies
        .where((c) =>
            c.code.toLowerCase().contains(_query.toLowerCase()) ||
            c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kText3.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.currencySearchHint,
                prefixIcon: const Icon(Icons.search_rounded, color: kForest),
                filled: true,
                fillColor: kSand,
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
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                final selected = c.code == widget.selected;
                return ListTile(
                  title: Text(
                    c.code,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? kForest : kBark,
                    ),
                  ),
                  subtitle: Text(c.name,
                      style: const TextStyle(color: kText2, fontSize: 12)),
                  trailing: selected
                      ? const Icon(Icons.check_rounded,
                          color: kForest, size: 18)
                      : null,
                  onTap: () => Navigator.pop(context, c.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Visibility helpers ───────────────────────────────────────────────────────

String _visibilityLabel(ItineraryVisibility v, AppLocalizations l10n) =>
    switch (v) {
      ItineraryVisibility.public => l10n.visibilityPublic,
      ItineraryVisibility.followers => l10n.visibilityFollowers,
      ItineraryVisibility.restricted => l10n.visibilityRestricted,
      ItineraryVisibility.onlyMe => l10n.visibilityOnlyMe,
    };

IconData _visibilityIcon(ItineraryVisibility v) => switch (v) {
      ItineraryVisibility.public => Icons.public_rounded,
      ItineraryVisibility.followers => Icons.group_rounded,
      ItineraryVisibility.restricted => Icons.key_rounded,
      ItineraryVisibility.onlyMe => Icons.lock_rounded,
    };

Color _visibilityColor(ItineraryVisibility v) => switch (v) {
      ItineraryVisibility.public => kCanopy,
      ItineraryVisibility.followers => kText2,
      ItineraryVisibility.restricted => kRatingOrange,
      ItineraryVisibility.onlyMe => kText3,
    };
