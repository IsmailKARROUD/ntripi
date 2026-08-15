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
//             Owner-only: every setting on this screen — cover, visibility, the
//             editor list, delete — is owner-gated server-side, so a granted
//             editor here could only collect 403s. The route is directly
//             addressable (web URL, deep link), which is why the gate is on the
//             screen and not only on the button that opens it.
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
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/recommended_period_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/visibility_screen.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';
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
  final _titleFocusNode = FocusNode();
  List<Currency> _currencies = [];

  String? _currency = 'EUR';

  ItineraryVisibility _visibility = ItineraryVisibility.public;
  RecommendedPeriod? _recommendedPeriod;
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
        _currency,
        _visibility,
        // Compared by value — RecommendedPeriod/PeriodWindow implement ==.
        _recommendedPeriod,
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
      _currency = _currencies.contains(itinerary.currency)
          ? itinerary.currency
          : 'Other';
      _visibility = itinerary.visibility;
      _recommendedPeriod = itinerary.recommendedPeriod;
      _initialized = true;
    });
    // Capture baseline after fields are populated, so opening to edit and
    // leaving without changes does not trigger the discard dialog.
    _initialSnapshot = _snapshot();
  }

  @override
  void dispose() {
    _titleController.dispose();
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

    // Edit mode with an untouched form: the PATCH would write nothing, so
    // sending it can only fail (lost edit lock, stale ETag) and strand the user
    // on a screen with no changes to save — and it would bump updated_at, 412ing
    // every other open client over a no-op. Requires a captured baseline: with
    // _initialSnapshot still null the form was never populated and _isDirty
    // reads false even for text the user typed.
    if (widget.mode == ItineraryFormMode.edit &&
        _initialSnapshot != null &&
        !_isDirty) {
      context.pop();
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleController.text.trim(),
        // Description is edited on its own screen (the shared markdown editor) —
        // the form must not send it, or it would clobber it with a stale value.
        // 'Other' is a UI-only placeholder; fall back to EUR for the API.
        'currency': _currency == 'Other' ? 'EUR' : _currency,
        'visibility': _visibilityToString[_visibility],
        // Unlike the description, the period IS edited in this form, so sending
        // it is correct. toPayload always emits all three keys, so clearing a
        // part reaches the server as an explicit null rather than "don't touch".
        ...(_recommendedPeriod ?? const RecommendedPeriod()).toPayload(),
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
          } on Exception catch (e) {
            if (mounted) {
              final l10n = AppLocalizations.of(context)!;
              // A moderation rejection is actionable — surface the real backend
              // (AWS) reason via the same extractErrorMessage path used
              // elsewhere, not the generic "saved but upload failed", so the
              // user knows *why* the cover was refused.
              final message = apiErrorCode(e) == 'image_moderation_rejected'
                  ? extractErrorMessage(e, l10n)
                  : l10n.imageSaveButUploadFailed;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          }
        }

        if (!mounted) return;
        // justCreated → detail screen opens the first-stop form on top of itself once.
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
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Captured with the others: this screen unmounts on success, so the widget
    // ref must not be read after the await.
    final sfx = ref.read(sfxServiceProvider);

    final l10n = AppLocalizations.of(context)!;
    final title = itinerary?.title ?? l10n.thisItineraryFallback;
    final confirmed = await confirmTypedDestructiveAction(
      context: context,
      title: l10n.deleteItineraryFormTitle,
      message: l10n.deleteItineraryFormMessage(title),
      requiredText: title,
      hintText: title,
    );
    if (!confirmed || !mounted) return;
    // Drive the existing SavingOverlay so the loader blocks the screen until
    // the network delete resolves. Left true on success — the screen unmounts.
    setState(() => _saving = true);
    try {
      await ref
          .read(myItinerariesProvider.notifier)
          .removeItinerary(widget.itineraryId!);
      // After the network call, never on confirm — a failed delete must not
      // sound like a successful one. Not awaited: the cue outlives the route.
      unawaited(sfx.play(Sfx.deleteItinerary));
      if (!mounted) return;
      router.go('/itineraries');
    } on Exception catch (e) {
      if (mounted) setState(() => _saving = false);
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

  Future<void> _showRecommendedPeriodPicker() async {
    final picked = await Navigator.push<RecommendedPeriod>(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendedPeriodScreen(initial: _recommendedPeriod),
      ),
    );
    if (picked == null || !mounted) return;
    // An all-empty result means the user cleared it — keep null as the single
    // "unset" representation so the dirty check and the payload agree.
    setState(() => _recommendedPeriod = picked.isEmpty ? null : picked);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  /// True only on evidence: an itinerary that has loaded and whose owner is
  /// somebody else. A profile or a detail still loading falls through to the
  /// form — refusing on a value we have not read yet would lock the owner out
  /// of their own trip on a cold deep link.
  bool get _blockedNonOwner {
    if (widget.mode != ItineraryFormMode.edit) return false;
    final currentUserId = ref.watch(myProfileProvider).value?.id;
    final itinerary =
        ref.watch(itineraryDetailProvider(widget.itineraryId!)).value;
    if (currentUserId == null || itinerary == null) return false;
    return itinerary.userId != currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    if (_blockedNonOwner) return const _OwnerOnlyNotice();
    final visLabel = _visibility.label(l10n);
    final visIcon = _visibilityIcon(_visibility);
    final visColor = _visibilityColor(_visibility, nt);
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
      child: SavingOverlay(
        saving: _saving,
        child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: nt.sand,
      appBar: AppBar(
        backgroundColor: nt.sand,
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
            OfflineGate(
              builder: (online) => TextButton(
                onPressed: online ? _save : null,
                child: Text(
                  l10n.save,
                  style: TextStyle(
                    color: online ? nt.forest : nt.text3,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: nt.text2,
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
                              hintStyle: TextStyle(
                                  color: nt.text3, fontWeight: FontWeight.w500),
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: nt.bark,
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
                              color: nt.forest,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showOptional
                                  ? l10n.hideOptionalFields
                                  : l10n.showOptionalFields,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: nt.forest,
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
                    // Re-seed the field from parent state so the preview
                    // persists across optional-fields collapse/expand.
                    initialBytes: _pendingImageBytes,
                    initialFilename: _pendingImageFilename,
                    initialRemoved: _removeExistingImage,
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
                      // 'Other' is an internal sentinel — show it localized.
                      value: _currency == 'Other'
                          ? l10n.otherOption
                          : (_currency ?? 'EUR'),
                      onTap: _showCurrencyPicker,
                    ),
                    const _FieldDivider(),
                    _PickerRow(
                      icon: Icons.event_available_rounded,
                      label: l10n.formLabelBestTime,
                      value: _recommendedPeriod
                              ?.shortLabel(l10n, l10n.localeName) ??
                          l10n.periodNotSet,
                      onTap: _showRecommendedPeriodPicker,
                    ),
                    const _FieldDivider(),
                    _PickerRow(
                      icon: visIcon,
                      label: l10n.formLabelWhoCanSee,
                      value: visLabel,
                      iconColor: visColor,
                      onTap: _showVisibilityPicker,
                    ),
                    // Edit mode only: granting edit rights needs an itinerary
                    // that exists, and the server rejects an editor who cannot
                    // yet see it — both of which are unanswerable during create.
                    if (widget.mode == ItineraryFormMode.edit) ...[
                      const _FieldDivider(),
                      _PickerRow(
                        icon: Icons.edit_note_rounded,
                        label: l10n.editorsTitle,
                        value: '',
                        onTap: () => context
                            .push('/itineraries/${widget.itineraryId}/editors'),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 48),
              // ── Danger zone (edit mode) ───────────────────────────────────
              if (widget.mode == ItineraryFormMode.edit) ...[
                _SectionLabel(text: l10n.formSectionDangerZone, tone: nt.ratingRed),
                _SectionCard(
                  children: [
                    OfflineGate(
                      builder: (online) => _PickerRow(
                        icon: Icons.delete_outline_rounded,
                        label: l10n.formLabelDeleteItinerary,
                        value: l10n.formDeleteItineraryHint,
                        iconColor: nt.ratingRed,
                        onTap: (_saving || !online) ? null : _deleteItinerary,
                      ),
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
      ),
    );
  }
}

// ─── Form-level private widgets ───────────────────────────────────────────────

/// Shown instead of the form when a non-owner reaches `/itineraries/{id}/edit`
/// directly. A plain refusal with a way back, not a silent pop: a screen that
/// vanishes on arrival reads as a crash.
class _OwnerOnlyNotice extends StatelessWidget {
  const _OwnerOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: nt.sand,
      appBar: AppBar(
        backgroundColor: nt.sand,
        title: Text(l10n.editItinerary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: nt.text3),
              const SizedBox(height: 12),
              Text(
                // Reuses the wording the API's own itinerary_not_owner refusal
                // already carries in all six locales.
                l10n.apiErrorItineraryNotOwner,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: nt.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  // Nullable: theme lookups aren't const, so the default resolves in build.
  final Color? tone;

  const _SectionLabel({required this.text, this.tone});

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
    final nt = context.nt;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
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
    final nt = context.nt;
    return Container(
        height: 1, color: nt.border, margin: const EdgeInsetsDirectional.only(start: 16));
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
    final nt = context.nt;
    final tint = iconColor ?? nt.forest;
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
                color: nt.mist,
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
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: nt.text2,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: nt.text3),
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
    final nt = context.nt;
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
                color: nt.text3.withValues(alpha: 0.5),
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
                prefixIcon: Icon(Icons.search_rounded, color: nt.forest),
                filled: true,
                fillColor: nt.sand,
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
                      color: selected ? nt.forest : nt.bark,
                    ),
                  ),
                  subtitle: Text(c.name,
                      style: TextStyle(color: nt.text2, fontSize: 12)),
                  trailing: selected
                      ? Icon(Icons.check_rounded,
                          color: nt.forest, size: 18)
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
// Labels come from ItineraryVisibility.label(l10n); the rounded icon variant
// below is specific to this screen's design.

IconData _visibilityIcon(ItineraryVisibility v) => switch (v) {
      ItineraryVisibility.public => Icons.public_rounded,
      ItineraryVisibility.followers => Icons.group_rounded,
      ItineraryVisibility.restricted => Icons.key_rounded,
      ItineraryVisibility.onlyMe => Icons.lock_rounded,
    };

Color _visibilityColor(ItineraryVisibility v, NtripiColors nt) => switch (v) {
      ItineraryVisibility.public => nt.canopy,
      ItineraryVisibility.followers => nt.text2,
      ItineraryVisibility.restricted => nt.ratingOrange,
      ItineraryVisibility.onlyMe => nt.text3,
    };
