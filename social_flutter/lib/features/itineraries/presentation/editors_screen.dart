// presentation/editors_screen.dart — "Who can edit this?"
//
// The owner's list of people who may change the trip. Mirrors the restricted
// allowlist in visibility_screen.dart on purpose: to the owner these are two
// lists of people with two different powers, and they should not need two
// mental models to manage them.
//
// The one thing that is genuinely different is the grant conflict. Editing sits
// on top of viewing, so granting edit rights to someone who cannot see the trip
// is refused server-side. That refusal is a question, not an error: the owner is
// asked whether to widen view access as well, and only their yes sends the
// second request. The server never widens visibility on its own — switching a
// followers-only trip to restricted would cut off every follower, and that is
// not a side effect anyone should discover afterwards.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/confirm_dialog.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class EditorsScreen extends ConsumerWidget {
  const EditorsScreen({super.key, required this.itineraryId});

  final String itineraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final editorsAsync = ref.watch(editorsProvider(itineraryId));

    return Scaffold(
      backgroundColor: nt.surface,
      appBar: AppBar(title: Text(l10n.editorsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            l10n.editorsSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: nt.text2),
          ),
          const SizedBox(height: 20),
          editorsAsync.when(
            loading: () => const Center(child: NTripiRingLoader(size: 28)),
            error: (error, _) => Text(
              extractErrorMessage(error, l10n),
              style: TextStyle(color: nt.danger),
            ),
            data: (editors) => _EditorList(
              itineraryId: itineraryId,
              editors: editors,
            ),
          ),
          const SizedBox(height: 12),
          OfflineGate(
            builder: (online) => InkWell(
              onTap: online ? () => _openAddDialog(context, ref) : null,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: nt.text3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_note_rounded, size: 18, color: nt.forest),
                    const SizedBox(width: 6),
                    Text(
                      l10n.editorsAdd,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: nt.forest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddEditorDialog(itineraryId: itineraryId),
    );
  }
}

class _EditorList extends ConsumerWidget {
  const _EditorList({required this.itineraryId, required this.editors});

  final String itineraryId;
  final List<ItineraryEditor> editors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    if (editors.isEmpty) {
      return Text(
        l10n.editorsEmpty,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: nt.text3),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < editors.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            ListTile(
              leading: UserAvatar(avatarUrl: editors[i].avatarUrl, radius: 18),
              title: Text(editors[i].label),
              subtitle: Text('@${editors[i].username}'),
              trailing: IconButton(
                icon: Icon(Icons.close_rounded, color: nt.text3),
                onPressed: () => _remove(context, ref, editors[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ItineraryEditor editor,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    // Tier 2: revoking is not undoable in one tap the way a delete is — the
    // person may be mid-edit, and their claim is released with the grant.
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.editorsRemoveTitle,
      message: l10n.editorsRemoveMessage(editor.label),
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref
          .read(editorsProvider(itineraryId).notifier)
          .removeEditor(editor.userId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, l10n))),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.editorsRemoved(editor.label))),
    );
  }
}

class _AddEditorDialog extends ConsumerStatefulWidget {
  const _AddEditorDialog({required this.itineraryId});

  final String itineraryId;

  @override
  ConsumerState<_AddEditorDialog> createState() => _AddEditorDialogState();
}

class _AddEditorDialogState extends ConsumerState<_AddEditorDialog> {
  final _searchController = TextEditingController();
  final List<User> _results = [];
  Timer? _debounce;
  bool _searching = false;
  bool _submitting = false;

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
    // Same 400 ms as the allowlist picker — one keystroke is not a query.
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
        if (!mounted) return;
        setState(() {
          _results
            ..clear()
            ..addAll(users);
          _searching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _add(User user, {bool grantView = false}) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(editorsProvider(widget.itineraryId).notifier)
          .addEditor(user.id, grantView: grantView);
      if (mounted) Navigator.pop(context);
    } on EditorCannotViewException catch (e) {
      // Not a failure — a question. Ask, then re-send with the owner's answer.
      if (!mounted) return;
      setState(() => _submitting = false);
      await _askAboutViewAccess(user, e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractErrorMessage(e, AppLocalizations.of(context)!)),
        ),
      );
    }
  }

  Future<void> _askAboutViewAccess(
    User user,
    EditorCannotViewException reason,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final label = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : '@${user.username}';

    if (!reason.canFixWithAllowlist) {
      // only_me / followers: the fix is a visibility change, which is the
      // owner's decision to make deliberately on its own screen — doing it
      // here would quietly change who else can see the trip.
      await ConfirmDialog.show(
        context,
        title: l10n.editorsGrantViewTitle,
        message: l10n.editorsChangeVisibilityMessage(label),
        confirmLabel: l10n.editorsOpenVisibility,
      );
      return;
    }

    final agreed = await ConfirmDialog.show(
      context,
      title: l10n.editorsGrantViewTitle,
      message: l10n.editorsGrantViewMessage(label),
      confirmLabel: l10n.editorsGrantViewConfirm,
    );
    if (agreed == true && mounted) await _add(user, grantView: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    return AlertDialog(
      title: Text(l10n.editorsAdd),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l10n.editorsSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(12),
                child: NTripiRingLoader(size: 22),
              )
            else
              OfflineGate(
                builder: (online) => Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (_, index) {
                      final user = _results[index];
                      return ListTile(
                        enabled: online && !_submitting,
                        leading:
                            UserAvatar(avatarUrl: user.avatarUrl, radius: 16),
                        title: Text(user.displayName ?? '@${user.username}'),
                        subtitle: Text('@${user.username}',
                            style: TextStyle(color: nt.text3)),
                        onTap: () => _add(user),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
