// presentation/itinerary_form_screen.dart — Create or edit an itinerary header.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/models/user.dart';

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

  String _currency = 'EUR';
  int? _safetyRating;
  ItineraryVisibility _visibility = ItineraryVisibility.onlyMe;
  bool _saving = false;
  bool _initialized = false;

  static const _currencies = ['EUR', 'USD', 'GBP', 'MAD', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.mode == ItineraryFormMode.edit) {
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
      _safetyRating = itinerary.safetyRating;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
        'currency': _currency == 'Other' ? 'EUR' : _currency,
        if (_safetyRating != null) 'safety_rating': _safetyRating,
        'visibility': _visibilityToString[_visibility],
      };

      if (widget.mode == ItineraryFormMode.create) {
        final itinerary =
            await ref.read(myItinerariesProvider.notifier).addItinerary(data);
        if (!mounted) return;
        context.go('/itineraries/${itinerary.id}');
      } else {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == ItineraryFormMode.create
            ? 'New Itinerary'
            : 'Edit Itinerary'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 16),

              // Currency
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: _currencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _currency = v ?? 'EUR'),
              ),
              const SizedBox(height: 16),

              // Safety rating
              Text(
                'Safety Rating (optional)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (int i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        i <= (_safetyRating ?? 0)
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () => setState(() {
                        _safetyRating = _safetyRating == i ? null : i;
                      }),
                    ),
                  if (_safetyRating != null)
                    TextButton(
                      onPressed: () => setState(() => _safetyRating = null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Visibility picker
              Text(
                'Visibility',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ItineraryVisibility>(
                  segments: const [
                    ButtonSegment(
                      value: ItineraryVisibility.public,
                      label: Text('Public'),
                      icon: Icon(Icons.public),
                    ),
                    ButtonSegment(
                      value: ItineraryVisibility.followers,
                      label: Text('Followers'),
                      icon: Icon(Icons.people),
                    ),
                    ButtonSegment(
                      value: ItineraryVisibility.restricted,
                      label: Text('Restricted'),
                      icon: Icon(Icons.lock_outline),
                    ),
                    ButtonSegment(
                      value: ItineraryVisibility.onlyMe,
                      label: Text('Only Me'),
                      icon: Icon(Icons.lock),
                    ),
                  ],
                  selected: {_visibility},
                  onSelectionChanged: (selection) =>
                      setState(() => _visibility = selection.first),
                ),
              ),

              // Restricted allowlist section — edit mode only.
              // In create mode, there is no itinerary ID yet, so allowlist
              // management is available after saving (via the edit flow).
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
                        ? 'Create Itinerary'
                        : 'Save Changes'),
              ),
            ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'People with access',
              style: Theme.of(context).textTheme.titleSmall,
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
            child: Text('Error loading allowlist: $e'),
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
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
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
