// presentation/visibility_screen.dart — "Who can see this?" (Screen 16).
//
// Pushed via Navigator.push<ItineraryVisibility>. Pops with the selected
// visibility when the user taps Done.
//
// In edit mode (itineraryId != null) the allowlist section appears below the
// visibility cards whenever Restricted is selected, letting the user manage
// access in the same flow without navigating back to the form.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/allowed_user.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

class VisibilityScreen extends ConsumerStatefulWidget {
  /// Current visibility — used to pre-select the active card.
  final ItineraryVisibility initial;

  /// Null in create mode. When set, the allowlist section is shown for
  /// restricted visibility and mutations hit the real API.
  final String? itineraryId;

  const VisibilityScreen({
    super.key,
    required this.initial,
    this.itineraryId,
  });

  @override
  ConsumerState<VisibilityScreen> createState() => _VisibilityScreenState();
}

class _VisibilityScreenState extends ConsumerState<VisibilityScreen> {
  late ItineraryVisibility _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  void _done() => Navigator.pop(context, _selected);

  /// Saves visibility as 'restricted' if not yet committed, then opens the
  /// add-person dialog. The save is needed because the allowlist API rejects
  /// adds when the itinerary isn't actually restricted yet.
  Future<void> _handleAddPeople() async {
    final itineraryId = widget.itineraryId!;
    final savedVisibility =
        ref.read(itineraryDetailProvider(itineraryId)).value?.visibility;

    if (savedVisibility != ItineraryVisibility.restricted) {
      setState(() => _submitting = true);
      try {
        await ref
            .read(itineraryDetailProvider(itineraryId).notifier)
            .updateHeader({'visibility': 'restricted'});
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
          );
        }
        if (mounted) setState(() => _submitting = false);
        return;
      }
      if (mounted) setState(() => _submitting = false);
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddPersonDialog(itineraryId: itineraryId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final isRestricted = _selected == ItineraryVisibility.restricted;
    final hasItinerary = widget.itineraryId != null;

    return SavingOverlay(
      saving: _submitting,
      child: Scaffold(
      backgroundColor: nt.surface,
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: EditorialTopBar(
            title: AppLocalizations.of(context)!.visibilityScreenTitle,
            actions: [
              TextButton(
                onPressed: _done,
                child: Text(
                  AppLocalizations.of(context)!.doneTooltip,
                  style: TextStyle(
                    color: nt.forest,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const EditorialDivider(),
        Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Visibility option cards ──────────────────────────────────────
          ..._kOptions.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _VisCard(
                  opt: opt,
                  active: opt.value == _selected,
                  onTap: () => setState(() => _selected = opt.value),
                ),
              )),

          // ── Allowlist (restricted + edit mode only) ──────────────────────
          if (isRestricted && hasItinerary) ...[
            const SizedBox(height: 8),
            _AllowlistSection(
              itineraryId: widget.itineraryId!,
              submitting: _submitting,
              onAddPeople: _handleAddPeople,
            ),
          ],

          // Hint for create mode with restricted
          if (isRestricted && !hasItinerary)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: nt.transitBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: nt.transitBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded,
                        size: 16, color: nt.transitIcon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.saveItineraryFirstAllowlist,
                        style: TextStyle(
                            fontSize: 12, color: nt.transitText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      )),
      ]),
      ),
    );
  }
}

// ─── Visibility option data ───────────────────────────────────────────────────

// Labels/descriptions come from ItineraryVisibility.label/description; only
// the screen-specific rounded icon variant lives here.
typedef _VisOption = ({
  ItineraryVisibility value,
  IconData icon,
});

const _kOptions = <_VisOption>[
  (value: ItineraryVisibility.public, icon: Icons.public_rounded),
  (value: ItineraryVisibility.followers, icon: Icons.group_rounded),
  (value: ItineraryVisibility.restricted, icon: Icons.key_rounded),
  (value: ItineraryVisibility.onlyMe, icon: Icons.lock_rounded),
];

// ─── Visibility card ──────────────────────────────────────────────────────────

class _VisCard extends StatelessWidget {
  final _VisOption opt;
  final bool active;
  final VoidCallback onTap;

  const _VisCard(
      {required this.opt, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: active ? nt.mist : nt.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? nt.forest : nt.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active ? nt.surface : nt.mist,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(opt.icon, size: 18, color: nt.forest),
            ),
            const SizedBox(width: 12),
            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opt.value.label(AppLocalizations.of(context)!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: nt.bark,
                    ),
                  ),
                  Text(
                    opt.value.description(AppLocalizations.of(context)!),
                    style:
                        TextStyle(fontSize: 11, color: nt.text2),
                  ),
                ],
              ),
            ),
            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: active ? nt.forest : Colors.transparent,
                shape: BoxShape.circle,
                border: active
                    ? null
                    : Border.all(color: nt.text3, width: 1.5),
              ),
              alignment: Alignment.center,
              child: active
                  ? Icon(Icons.check_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Allowlist section ────────────────────────────────────────────────────────

class _AllowlistSection extends ConsumerWidget {
  final String itineraryId;
  final bool submitting;
  final VoidCallback onAddPeople;

  const _AllowlistSection({
    required this.itineraryId,
    required this.submitting,
    required this.onAddPeople,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final allowedAsync = ref.watch(allowedUsersProvider(itineraryId));
    final allowed = allowedAsync.value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(
            children: [
              Icon(Icons.group_add_rounded, size: 13, color: nt.text2),
              const SizedBox(width: 6),
              Text(
                '${AppLocalizations.of(context)!.allowlistLabel.toUpperCase()}${allowed.isNotEmpty ? ' · ${AppLocalizations.of(context)!.personCount(allowed.length)}' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: nt.text2,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),

        // User list
        if (allowed.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: nt.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: nt.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < allowed.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 60, endIndent: 0),
                  _AllowRow(
                    user: allowed[i],
                    onRemove: () async {
                      try {
                        await ref
                            .read(allowedUsersProvider(itineraryId)
                                .notifier)
                            .removeUser(allowed[i].userId);
                      } on Exception catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
                          );
                        }
                        return;
                      }
                      if (!context.mounted) return;
                      final label =
                          allowed[i].displayName ?? allowed[i].username;
                      showUndoableActionSnackbar(
                        context: context,
                        duration: const Duration(seconds: 30),
                        message: AppLocalizations.of(context)!
                            .removedFromAllowlist(label),
                        onUndo: () async {
                          await ref
                              .read(allowedUsersProvider(itineraryId)
                                  .notifier)
                              .addUser(allowed[i].userId);
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 8),

        // "Add people" dashed button — shows spinner while visibility is being saved
        OfflineGate(
          builder: (online) => InkWell(
          onTap: (submitting || !online) ? null : onAddPeople,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: nt.text3, style: BorderStyle.solid),
            ),
            child: submitting
                ? const Center(child: NTripiRingLoader(size: 20))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_rounded,
                          size: 18, color: nt.forest),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)!.addPeople,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: nt.bark,
                        ),
                      ),
                    ],
                  ),
          ),
          ),
        ),
      ],
    );
  }
}

// ─── Single allowed-user row ──────────────────────────────────────────────────

class _AllowRow extends StatelessWidget {
  final AllowedUser user;
  final VoidCallback onRemove;

  const _AllowRow({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final initials = ((user.displayName ?? user.username).isNotEmpty)
        ? (user.displayName ?? user.username)[0].toUpperCase()
        : '?';

    // Deterministic pastel bg from the username hash.
    final palettes = nt.avatarPairs;
    int h = 0;
    for (final c in user.username.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    final palette = palettes[h % palettes.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.$1,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.$2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? user.username,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
                Text(
                  '@${user.username}',
                  style: TextStyle(fontSize: 11, color: nt.text2),
                ),
              ],
            ),
          ),
          OfflineGate(
            builder: (online) => IconButton(
              icon: Icon(Icons.remove_circle_outline_rounded,
                  size: 20, color: nt.text3),
              onPressed: online ? onRemove : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add person dialog ────────────────────────────────────────────────────────

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
          SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    // watch (not read) so open dialogs react to connectivity changes live
    final online = ref.watch(isOnlineProvider).value ?? true;
    return AlertDialog(
      backgroundColor: nt.sand,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(AppLocalizations.of(context)!.visibilityAddPerson,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.visibilitySearchByUsername,
                prefixIcon:
                    Icon(Icons.search_rounded, color: nt.forest),
                filled: true,
                fillColor: nt.surface,
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
                  borderSide:
                      BorderSide(color: nt.forest, width: 1.5),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Expanded(child: Center(child: NTripiRingLoader()))
            else if (_results.isEmpty && _searchController.text.isNotEmpty)
              Expanded(
                  child: Center(child: Text(AppLocalizations.of(context)!.noUsersFound)))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, index) {
                    final user = _results[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: nt.mist,
                        child: Text(
                          (user.displayName ?? user.username)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(
                              color: nt.forest, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(user.displayName ?? user.username,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: nt.bark)),
                      subtitle: Text('@${user.username}',
                          style: TextStyle(color: nt.text2)),
                      trailing: Icon(Icons.add_rounded,
                          color: nt.forest, size: 20),
                      // Adding hits the allowlist API — no-op offline; the
                      // dialog sits above the shell banner that explains why.
                      onTap: online ? () => _addUser(user) : null,
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
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
      ],
    );
  }
}
