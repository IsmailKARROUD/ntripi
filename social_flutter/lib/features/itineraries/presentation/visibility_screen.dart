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
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/allowed_user.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

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
    final isRestricted = _selected == ItineraryVisibility.restricted;
    final hasItinerary = widget.itineraryId != null;

    return Scaffold(
      backgroundColor: kSand,
      appBar: AppBar(
        backgroundColor: kSand,
        title: Text(AppLocalizations.of(context)!.visibilityScreenTitle),
        actions: [
          TextButton(
            onPressed: _done,
            child: Text(
              AppLocalizations.of(context)!.doneTooltip,
              style: TextStyle(
                color: kForest,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
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
                  color: const Color(0xFFFFF8EC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF0E2C2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_rounded,
                        size: 16, color: Color(0xFFA06D1F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.saveItineraryFirstAllowlist,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF8A5A18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: active ? kMist : kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? kForest : kBorder,
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
                color: active ? kSurface : kMist,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(opt.icon, size: 18, color: kForest),
            ),
            const SizedBox(width: 12),
            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opt.value.label(AppLocalizations.of(context)!),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kBark,
                    ),
                  ),
                  Text(
                    opt.value.description(AppLocalizations.of(context)!),
                    style:
                        const TextStyle(fontSize: 11, color: kText2),
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
                color: active ? kForest : Colors.transparent,
                shape: BoxShape.circle,
                border: active
                    ? null
                    : Border.all(color: kText3, width: 1.5),
              ),
              alignment: Alignment.center,
              child: active
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
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
              const Icon(Icons.group_add_rounded, size: 13, color: kText2),
              const SizedBox(width: 6),
              Text(
                '${AppLocalizations.of(context)!.allowlistLabel.toUpperCase()}${allowed.isNotEmpty ? ' · ${AppLocalizations.of(context)!.personCount(allowed.length)}' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kText2,
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
              color: kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
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
        InkWell(
          onTap: submitting ? null : onAddPeople,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kText3, style: BorderStyle.solid),
            ),
            child: submitting
                ? const Center(child: NTripiRingLoader(size: 20))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_add_rounded,
                          size: 18, color: kForest),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)!.addPeople,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kBark,
                        ),
                      ),
                    ],
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
    final initials = ((user.displayName ?? user.username).isNotEmpty)
        ? (user.displayName ?? user.username)[0].toUpperCase()
        : '?';

    // Deterministic pastel bg from the username hash.
    const palettes = [
      (bg: Color(0xFFD0EBDA), fg: kForest),
      (bg: Color(0xFFFFE3CC), fg: Color(0xFFA05D1F)),
      (bg: Color(0xFFE0DAF0), fg: Color(0xFF5A3F8F)),
      (bg: Color(0xFFCDE0D6), fg: Color(0xFF3B6EA5)),
    ];
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
              color: palette.bg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.fg,
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                  ),
                ),
                Text(
                  '@${user.username}',
                  style: const TextStyle(fontSize: 11, color: kText2),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 20, color: kText3),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
    return AlertDialog(
      backgroundColor: kSand,
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
                    const Icon(Icons.search_rounded, color: kForest),
                filled: true,
                fillColor: kSurface,
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
                  borderSide:
                      const BorderSide(color: kForest, width: 1.5),
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
                        backgroundColor: kMist,
                        child: Text(
                          (user.displayName ?? user.username)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              color: kForest, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(user.displayName ?? user.username,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: kBark)),
                      subtitle: Text('@${user.username}',
                          style: const TextStyle(color: kText2)),
                      trailing: const Icon(Icons.add_rounded,
                          color: kForest, size: 20),
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
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
      ],
    );
  }
}
