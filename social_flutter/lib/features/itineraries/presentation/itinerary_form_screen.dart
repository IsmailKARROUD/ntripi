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
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
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
  List<Currency> _currencies = [];

  String? _currency = 'EUR';

  ItineraryVisibility _visibility = ItineraryVisibility.onlyMe;
  bool _saving = false;
  // Guards _initFromProvider so rebuilds don't overwrite the user's edits.
  bool _initialized = false;

  // Cover image state — deferred upload on create, immediate on edit.
  Uint8List? _pendingImageBytes;
  String? _pendingImageFilename;
  bool _removeExistingImage = false;

Future<void> loadCurrencies() async {
  try {
    // 1. Load the string
    final String response = await rootBundle.loadString('assets/data/currencies.json');

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
      if (_currencies.isNotEmpty) {
        _currency = _currencies.first.code;
      }
    });

  } catch (e) {
    // Handle the error gracefully
    print('Failed to load currencies: $e');
    // Optional: setState to show an error message in the UI
  }
}

  // static const _currencies = ['EUR', 'USD', 'GBP', 'MAD', 'Other'];

  @override
  void initState() {
    super.initState();
    loadCurrencies();
    if (widget.mode == ItineraryFormMode.edit) {
      // postFrameCallback: setState can't be called during initState itself.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initFromProvider());
    }
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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // The R2 storage key never changes between uploads (always itineraries/{id}.jpg),
  // so CachedNetworkImage's disk cache would keep serving the old bytes.
  // evictFromCache clears both the on-disk file (DefaultCacheManager) and the
  // in-memory ImageCache entry, forcing the next render to refetch.
  Future<void> _evictCoverImageCache() async {
    final url = ref
        .read(itineraryDetailProvider(widget.itineraryId!))
        .valueOrNull
        ?.coverImageUrl;
    if (url == null) return;
    final absUrl = url.startsWith('/') ? '$kApiBaseUrl$url' : url;
    await CachedNetworkImage.evictFromCache(absUrl);
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
                  content: Text(AppLocalizations.of(context)!.imageSaveButUploadFailed),
                ),
              );
            }
          }
        }

        if (!mounted) return;
        context.go('/itineraries/${itinerary.id}');
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItinerary() async {
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId!)).valueOrNull;
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSand,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: kSand,
        title: Text(widget.mode == ItineraryFormMode.create
            ? AppLocalizations.of(context)!.newItinerary
            : AppLocalizations.of(context)!.editItinerary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover image — deferred upload on create, immediate on edit
                LabelWithHelp(
                  label: AppLocalizations.of(context)!.coverImageLabel,
                  helpTitle: AppLocalizations.of(context)!.coverImageLabel,
                  helpMessage: AppLocalizations.of(context)!.coverImageHelp,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                CoverImageField(
                  initialUrl: widget.mode == ItineraryFormMode.edit
                      ? ref
                          .read(itineraryDetailProvider(widget.itineraryId!))
                          .valueOrNull
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
                const SizedBox(height: 16),

                // Title
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.itineraryTitleLabel,
                    suffixIcon: FieldHelpIcon(
                      helpTitle: AppLocalizations.of(context)!.itineraryTitleLabel,
                      helpMessage: AppLocalizations.of(context)!.itineraryTitleHelp,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? AppLocalizations.of(context)!.itineraryTitleRequired
                      : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // Description — Markdown source with toolbar.
                MarkdownNotesEditor(
                  controller: _descriptionController,
                  readOnly: false,
                  label: AppLocalizations.of(context)!.descriptionLabel,
                  helpTitle: AppLocalizations.of(context)!.descriptionLabel,
                  helpMessage: AppLocalizations.of(context)!.descriptionHelp,
                ),
                const SizedBox(height: 16),

                // Currency
                DropdownButtonFormField<String>(
                  value: _currency,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.currencyLabel,
                    suffixIcon: FieldHelpIcon(
                      helpTitle: AppLocalizations.of(context)!.currencyLabel,
                      helpMessage: AppLocalizations.of(context)!.currencyHelp,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  items: _currencies.map((currency) {
                    return DropdownMenuItem<String>(
                      value: currency.code,
                      child: Text(
                        '${currency.code} - ${currency.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _currency = v;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Visibility picker
                LabelWithHelp(
                  label: AppLocalizations.of(context)!.visibilityLabel,
                  helpTitle: AppLocalizations.of(context)!.visibilityLabel,
                  helpMessage: AppLocalizations.of(context)!.visibilityHelp,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ItineraryVisibility>(
                    segments: [
                      ButtonSegment(
                        value: ItineraryVisibility.public,
                        label: Text(AppLocalizations.of(context)!.visibilityPublic),
                        icon: const Icon(Icons.public),
                      ),
                      ButtonSegment(
                        value: ItineraryVisibility.followers,
                        label: Text(AppLocalizations.of(context)!.visibilityFollowers),
                        icon: const Icon(Icons.people),
                      ),
                      ButtonSegment(
                        value: ItineraryVisibility.restricted,
                        label: Text(AppLocalizations.of(context)!.visibilityRestricted),
                        icon: const Icon(Icons.lock_outline),
                      ),
                      ButtonSegment(
                        value: ItineraryVisibility.onlyMe,
                        label: Text(AppLocalizations.of(context)!.visibilityOnlyMe),
                        icon: const Icon(Icons.lock),
                      ),
                    ],
                    selected: {_visibility},
                    onSelectionChanged: (selection) =>
                        setState(() => _visibility = selection.first),
                  ),
                ),

                // Restricted allowlist section — edit mode only.
                if (widget.mode == ItineraryFormMode.edit &&
                    _visibility == ItineraryVisibility.restricted) ...[
                  const SizedBox(height: 16),
                  _AllowlistSection(itineraryId: widget.itineraryId!),
                ],

                const SizedBox(height: 24),

                // Save button
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.mode == ItineraryFormMode.create
                          ? AppLocalizations.of(context)!.createItinerary
                          : AppLocalizations.of(context)!.save),
                ),

                if (widget.mode == ItineraryFormMode.edit) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Danger zone',
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(color:kRatingRed,fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Permanently delete this itinerary and all its stops. '
                    'This cannot be undone.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _deleteItinerary,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(AppLocalizations.of(context)!.deleteItineraryButton),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRatingRed,
                      side: const BorderSide(color: kRatingRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AllowlistSection — shown in edit mode when visibility == restricted
// ---------------------------------------------------------------------------

class _AllowlistSection extends ConsumerWidget {
  final String itineraryId;

  const _AllowlistSection({required this.itineraryId});

  Future<void> _showAddPersonDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddPersonDialog(itineraryId: itineraryId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowedAsync = ref.watch(allowedUsersProvider(itineraryId));

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LabelWithHelp(
                label: 'People with access',
                helpTitle: 'Allowlist',
                helpMessage:
                    'Users who can view this restricted itinerary. Search by @username to add or remove people.',
                labelStyle: Theme.of(context).textTheme.titleSmall,
              ),
              TextButton.icon(
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add person'),
                onPressed: () => _showAddPersonDialog(context),
              ),
            ],
          ),
          allowedAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(extractErrorMessage(e)),
            ),
            data: (users) {
              if (users.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No one has access yet. Tap "Add person" to grant access.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: users
                    .map(
                      (user) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(
                            (user.displayName ?? user.username)
                                .substring(0, 1)
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(user.displayName ?? user.username),
                        subtitle: Text('@${user.username}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove access',
                          onPressed: () async {
                            try {
                              await ref
                                  .read(allowedUsersProvider(itineraryId)
                                      .notifier)
                                  .removeUser(user.userId);
                            } on Exception catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      extractErrorMessage(e as dynamic),
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            if (!context.mounted) return;
                            final displayLabel =
                                user.displayName ?? user.username;
                            showUndoableActionSnackbar(
                              context: context,
                              duration: const Duration(seconds: 5),
                              message: 'Removed $displayLabel from allowlist',
                              onUndo: () async {
                                await ref
                                    .read(allowedUsersProvider(itineraryId)
                                        .notifier)
                                    .addUser(user.userId);
                              },
                            );
                          },
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AddPersonDialog — search for a user and add them to the allowlist
// ---------------------------------------------------------------------------

class _AddPersonDialog extends ConsumerStatefulWidget {
  final String itineraryId;

  const _AddPersonDialog({required this.itineraryId});

  @override
  ConsumerState<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends ConsumerState<_AddPersonDialog> {
  final _searchController = TextEditingController();
  final List<User> _results = [];
  Timer? _debounce;
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results.clear());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final response = await dio.get<List<dynamic>>(
          kSearchUsersEndpoint,
          queryParameters: {'q': value.trim()},
        );
        final users = (response.data ?? [])
            .cast<Map<String, dynamic>>()
            .map(User.fromJson)
            .toList();
        if (mounted) {
          setState(() {
            _results
              ..clear()
              ..addAll(users);
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _addUser(User user) async {
    try {
      await ref
          .read(allowedUsersProvider(widget.itineraryId).notifier)
          .addUser(user.id);
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e as dynamic))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add person'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_results.isEmpty && _searchController.text.isNotEmpty)
              const Expanded(
                child: Center(child: Text('No users found.')),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (user.displayName ?? user.username)
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(user.displayName ?? user.username),
                      subtitle: Text('@${user.username}'),
                      onTap: () => _addUser(user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
