// presentation/itinerary_form_screen.dart — Create or edit an itinerary header.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

/// Whether this form is creating a new itinerary or editing an existing one.
enum ItineraryFormMode { create, edit }

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
  bool _isPublic = false;
  bool _saving = false;
  bool _initialized = false;

  static const _currencies = ['EUR', 'USD', 'GBP', 'MAD', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.mode == ItineraryFormMode.edit) {
      // Pre-fill fields once the provider has loaded the itinerary.
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
      _isPublic = itinerary.isPublic;
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
        'is_public': _isPublic,
      };

      if (widget.mode == ItineraryFormMode.create) {
        final itinerary =
            await ref.read(myItinerariesProvider.notifier).addItinerary(data);
        if (!mounted) return;
        // Navigate to the detail screen of the newly created itinerary.
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
                        // Tap the same star again to clear the rating.
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
              const SizedBox(height: 8),

              // Is public toggle
              SwitchListTile(
                title: const Text('Public itinerary'),
                subtitle: const Text(
                  'Anyone can view this itinerary when public.',
                ),
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
                contentPadding: EdgeInsets.zero,
              ),
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

