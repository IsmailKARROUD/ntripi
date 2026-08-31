// presentation/itinerary_detail_screen.dart — Full itinerary view with map.
//
// Layout (CustomScrollView so pull-to-refresh works over the whole page):
//   Cover hero   — 240px full-bleed image + back / share / flag (non-owner) /
//                  edit-details / edit-pencil chrome; ✓ to leave edit mode
//   Owner row    — avatar, the viewer's own rating, community average
//   Meta chips   — duration, cost, stop count
//   Recommended period — best travel window + why note
//   Description  — optional free-text
//   Itinerary annotations — trip-wide notes as chips
//   List/Map toggle — reorder-tracks, bookmark and route buttons
//   Map section  — OSM map with stop markers and polyline (ODbL requires attribution)
//   Stop list    — interleaved stops + segments (read & edit mode)
//
// Edit-mode state machine:
//   _editMode = false → read-only view; the owner can still long-press any
//                       section to jump straight to its editor (LongPressToEdit)
//   _editMode = true  → interleaved list with inline edit/delete buttons and
//                       inline separators between stops
//
// Mutations are immediate — every stop/segment/annotation change PATCHes on
// save from its own form or sheet. Reordering is not deferred either: it runs
// through showTrackReorderSheet / showReorderParallelsSheet, so there is no
// save bar and no pending-changes state to guard.
//
// Back-button guard (PopScope):
//   While in edit mode the system back button exits edit mode instead of
//   navigating away. Nothing is unsaved at that point, so nothing is asked.
//
// OSM attribution is required by the ODbL license and is always visible.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/providers/long_press_hint_provider.dart';
import 'package:social_flutter/core/router/navigation_ext.dart';
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/confirm_dialog.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/maps_launcher_service.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/features/itineraries/presentation/annotation_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/recommended_period_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/long_press_to_edit.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/move_stop_to_track_sheet.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/report_content_sheet.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/parallel_stop_group.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/track_reorder_view.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/shared/widgets/markdown_edit_screen.dart';
import 'package:social_flutter/shared/widgets/appeal_sheet.dart';
import 'package:social_flutter/shared/widgets/moderation_hidden_banner.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/shadow_divider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_lock_banner.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/itinerary_cover_placeholder.dart';
import 'package:social_flutter/shared/widgets/visibility_badge.dart';

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;
  // Set only when navigated here right after creation → auto-show the add-stop hint once.
  final bool justCreated;

  const ItineraryDetailScreen({
    super.key,
    required this.itineraryId,
    this.justCreated = false,
  });

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends ConsumerState<ItineraryDetailScreen> {
  bool _editMode = false;
  // The best-time PATCH is the one inline save on this screen with no editor of
  // its own to spin in: the picker pops on Done and the write happens here, so
  // without this the row just sits on the old value until the response lands.
  bool _savingPeriod = false;
  // Active parallel-stop index per track (trackId → page index).
  final Map<String, int> _activeParallelByTrack = {};
  // GlobalKey per track widget so we can call Scrollable.ensureVisible after a
  // cross-track move to scroll the destination track into view.
  final Map<String, GlobalKey> _trackKeys = {};
  final GlobalKey _editDetailsButtonKey = GlobalKey();
  // Anchors the one-time long-press tip at the Edit pencil, the affordance the
  // gesture shortcuts past.
  final GlobalKey _enterEditButtonKey = GlobalKey();
  bool _longPressHintShown = false; // one-shot guard within this screen's life
  bool _firstStopFormOpened = false; // one-shot guard for the just-created auto-open
  bool _openSoundPlayed = false; // one-shot guard for the open-itinerary cue
  bool _closeCuePlayed = false; // one-shot guard: the two close paths overlap
  //start with map hidden on mobile to avoid unnecessary API calls and improve performance, since the map is less likely to be used on mobile and can be accessed via a button
  bool _mapVisible = false;
  // Polls who holds the edit claim. There is no push channel, so a banner that
  // never re-asks would show a person who finished editing ten minutes ago.
  Timer? _lockPoll;

  @override
  void initState() {
    super.initState();
    // Immediately, then on an interval: the first read is what makes the
    // banner correct on arrival, and the interval is only the worst case.
    unawaited(_pollLock());
    _lockPoll = Timer.periodic(
      kEditLockPollInterval,
      (_) => unawaited(_pollLock()),
    );
  }

  @override
  void dispose() {
    _lockPoll?.cancel();
    // The claim is NOT released here. dispose also runs when the stop form
    // pushes over this screen is torn down by a router.go(), and dropping the
    // claim on the way into an editor is exactly backwards. Leaving edit mode
    // releases it; otherwise the heartbeat stops and the TTL takes care of it.
    super.dispose();
  }

  /// Ask the server who holds the claim. Silent on failure — a banner that
  /// could not refresh is better than an error over something nobody asked for.
  Future<void> _pollLock() async {
    if (!mounted) return;
    // Our own heartbeat is fresher than any poll while we hold it.
    if (ref.read(editLockProvider(widget.itineraryId)).holdsClaim) return;
    await ref.read(editLockProvider(widget.itineraryId).notifier).peek();
  }

  static Map<StopType, Color> _markerColors(NtripiColors nt) => {
        StopType.origin: nt.forest,
        StopType.waypoint: nt.canopy,
        StopType.arrival: nt.ratingRed,
      };

  /// Enter edit mode — which means claiming the server-side edit lock first.
  ///
  /// Nothing local decides this. If somebody else holds the claim the server
  /// says so and the banner appears instead; the screen stays in read mode,
  /// which is the honest state when no write would be accepted.
  Future<void> _enterEditMode({bool takeover = false}) async {
    final notifier = ref.read(editLockProvider(widget.itineraryId).notifier);
    bool claimed;
    try {
      claimed = await notifier.acquire(takeover: takeover);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractErrorMessage(e, AppLocalizations.of(context)!)),
        ),
      );
      return;
    }
    if (!mounted || !claimed) return;
    setState(() => _editMode = true);
  }

  /// Ask before displacing a live claim. Takeover is never silent: the other
  /// device loses the ability to save without being told, so the person doing
  /// it should at least know that is what they are doing.
  Future<void> _confirmTakeOver(EditLock holder) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await ConfirmDialog.show(
      context,
      title: holder.isYou ? l10n.editLockYouElsewhere : l10n.editLockTakeOver,
      message: holder.isYou
          ? l10n.editLockMoveHereMessage
          : l10n.editLockLostMessage(holder.displayLabel),
      confirmLabel:
          holder.isYou ? l10n.editLockMoveHere : l10n.editLockTakeOver,
    );
    if (confirmed == true && mounted) await _enterEditMode(takeover: true);
  }

  // Opens the shared markdown editor for the description. It persists inline via
  // onSave (showing a spinner and surfacing errors itself), so it only returns
  // after a successful save. updateHeader mutates the provider in place, so the
  // row here rebuilds with the new text — no explicit refresh needed.
  Future<void> _editDescription(String? current) async {
    final l10n = AppLocalizations.of(context)!;
    await editMarkdownField(
      context,
      initialText: current ?? '',
      title: l10n.descriptionLabel,
      helpTitle: l10n.descriptionLabel,
      helpMessage: l10n.descriptionHelp,
      onSave: (value) => ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateHeader({'description': value.isEmpty ? null : value}),
    );
  }

  // The PATCH below needs X-Edit-Lock and the picker never claims one itself,
  // so the round trip has to happen before it opens — same rule as
  // _openStopForm. Reached from the read-mode long-press without this, the save
  // 428s after the user has already done the work.
  Future<void> _editRecommendedPeriod(RecommendedPeriod? current) async {
    if (!_editMode) await _enterEditMode();
    if (!mounted || !_editMode) return;
    final picked = await Navigator.push<RecommendedPeriod>(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendedPeriodScreen(initial: current),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _savingPeriod = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateHeader(picked.toPayload());
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    } finally {
      // finally, not the success path: every exit has to clear the spinner, and
      // `on Exception` does not catch an Error — one of those would otherwise
      // leave the row spinning at a value it is no longer saving.
      if (mounted) setState(() => _savingPeriod = false);
    }
  }

  // Opens the add-stop form — but claims the edit lock first, because the form
  // never claims one itself. Pushed without a claim it looks editable and then
  // 428s on save, so the round trip has to happen here; if the claim is refused
  // the banner is the honest answer and no form opens at all.
  Future<void> _openStopForm() async {
    if (!_editMode) await _enterEditMode();
    if (!mounted || !_editMode) return;
    context.push('/itineraries/${widget.itineraryId}/stops/new');
  }

  // Opens the Edit Itinerary form. Same reasoning as _openStopForm: the form
  // never claims a lock itself, and its PATCH needs one exactly as much as a
  // stop edit does, so the claim has to happen before the push or Save 428s.
  //
  // A `true` result means the user removed themselves as an editor in there —
  // the claim and the pencil are both gone, so leave edit mode and refetch so
  // can_edit stops saying otherwise.
  Future<void> _openDetailsForm() async {
    if (!_editMode) await _enterEditMode();
    if (!mounted || !_editMode) return;
    final left =
        await context.push<bool>('/itineraries/${widget.itineraryId}/edit');
    if (!mounted || left != true) return;
    _exitEditMode();
    await ref
        .read(itineraryDetailProvider(widget.itineraryId).notifier)
        .refresh();
  }

  // Owner tapped the placeholder cover: point them at the Edit details button
  // (which opens the form holding CoverImageField). Anchor is only laid out in
  // read mode — skip silently in edit mode, same as the add-stop hint.
  void _showAddCoverHint() {
    final ctx = _editDetailsButtonKey.currentContext;
    if (ctx == null) return;
    final l10n = AppLocalizations.of(context)!;
    showFieldHelp(
      ctx,
      title: l10n.addCoverImage,
      message: l10n.addCoverHintMessage,
      pointer: true, // draw a beak pointing up at the Edit details button
    );
  }

  // Long-press has no visible affordance, so owners get told about it once.
  // Anchor is only laid out in read mode — skip silently otherwise, same as
  // the add-cover hint.
  void _maybeShowLongPressHint() {
    if (_longPressHintShown || _editMode) return;
    if (ref.read(longPressHintSeenProvider)) return;
    final ctx = _enterEditButtonKey.currentContext;
    if (ctx == null) return;
    _longPressHintShown = true;
    final l10n = AppLocalizations.of(context)!;
    showFieldHelp(
      ctx,
      title: l10n.longPressEditHintTitle,
      message: l10n.longPressEditHintMessage,
      pointer: true, // draw a beak pointing up at the Edit pencil
    );
    ref.read(longPressHintSeenProvider.notifier).markSeen();
  }

  /// Leave edit mode and give the claim back, so the next editor does not wait
  /// out a timeout for a session that is over.
  void _exitEditMode() {
    setState(() => _editMode = false);
    unawaited(ref.read(editLockProvider(widget.itineraryId).notifier).release());
  }

  /// Closing cue — the mirror of the open cue above.
  ///
  /// Called from both ways out (the header back button and the PopScope), which
  /// overlap on the ordinary case: the button pops, and the pop then fires the
  /// PopScope. The latch is what makes that one cue instead of a stutter.
  ///
  /// Deliberately NOT in dispose(): the widget ref is backed by BuildContext and
  /// must not be touched there, and dispose also runs when a router.go() tears
  /// this screen down — which is exactly what deleting an itinerary does, so the
  /// fold would play over the delete cue.
  void _playCloseCue() {
    if (_closeCuePlayed) return;
    _closeCuePlayed = true;
    ref.read(sfxServiceProvider).play(Sfx.closeItinerary);
  }

  /// Scrolls the outer CustomScrollView so that the track with the given ID
  /// becomes visible near the top. The post-frame callback waits for the
  /// detail-provider refresh to rebuild the list before resolving the key's
  /// context, otherwise the destination track may not yet be laid out.
  void _scrollToTrack(String trackId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _trackKeys[trackId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  // Persist inline via onSaveAsync so the annotation screen shows its own save
  // spinner and stays open (text intact) on failure, instead of popping first
  // and persisting here — which used to discard the edit on a failed save.
  Future<void> _addItineraryAnnotation() async {
    await showAnnotationScreen(
      context,
      onSaveAsync: (result) => ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .addItineraryAnnotation({
        'content': result.content,
        'type': result.type.name,
      }),
    );
  }

  Future<void> _editItineraryAnnotation(ItineraryAnnotation annotation) async {
    await showAnnotationScreen(
      context,
      isEdit: true,
      initialContent: annotation.content,
      initialType: annotation.type,
      onSaveAsync: (result) => ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateItineraryAnnotation(annotation.id,
              content: result.content, type: result.type),
    );
  }

  Future<void> _deleteItineraryAnnotation(
      ItineraryAnnotation annotation) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteAnnotationTitle,
      message: l10n.deleteAnnotationMessage,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteItineraryAnnotation(annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  // stop is passed so the screen can show the stop context card.
  Future<void> _addAnnotation(Stop stop) async {
    await showAnnotationScreen(
      context,
      stopName:
          stop.placeName ?? AppLocalizations.of(context)!.stopFallbackName,
      stopSubtitle: stop.placeAddress,
      onSaveAsync: (result) => ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .addAnnotation(stop.id, {
        'content': result.content,
        'type': result.type.name,
      }),
    );
  }

  Future<void> _editAnnotation(Stop stop, Annotation annotation) async {
    await showAnnotationScreen(
      context,
      isEdit: true,
      initialContent: annotation.content,
      initialType: annotation.type,
      stopName:
          stop.placeName ?? AppLocalizations.of(context)!.stopFallbackName,
      stopSubtitle: stop.placeAddress,
      onSaveAsync: (result) => ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateAnnotation(stop.id, annotation.id,
              content: result.content, type: result.type),
    );
  }

  Future<void> _deleteAnnotation(String stopId, Annotation annotation) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteAnnotationTitle,
      message: l10n.deleteAnnotationMessage,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteAnnotation(stopId, annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _confirmDeleteSegment(TransitSegment segment) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.removeTransitTitle,
      message: l10n.removeTransitMessage,
      confirmLabel: l10n.removeButton,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteSegment(segment.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _addSegmentWithLeg(String fromStopId, String toStopId) async {
    final legData = await LegFormDialog.show(context);
    if (!mounted || legData == null) return;
    final data = <String, dynamic>{
      'from_stop_id': fromStopId,
      'to_stop_id': toStopId,
      'legs': [
        {...legData, 'position': 1},
      ],
    };
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .createSegment(data);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  // One point per track: stops within a track are parallel ALTERNATIVES, so
  // the route takes the user's active selection (fallback: first stop).
  List<LatLng> _routePoints(List<Track> tracks) {
    final points = <LatLng>[];
    for (final track in tracks) {
      if (track.stops.isEmpty) continue;
      final idx = (_activeParallelByTrack[track.id] ?? 0)
          .clamp(0, track.stops.length - 1);
      final stop = track.stops[idx];
      if (stop.lat != null && stop.lng != null) {
        points.add(LatLng(stop.lat!, stop.lng!));
      }
    }
    return points;
  }

  Future<void> _toggleSaved(Itinerary itinerary) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(savedItinerariesProvider.notifier);
    final wasSaved = ref.read(isItinerarySavedProvider(itinerary.id));
    try {
      if (wasSaved) {
        await notifier.unsave(itinerary.id);
      } else {
        await notifier.save(itinerary);
      }
    } catch (e) {
      // Notifier already reverted the optimistic state — just surface the error.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, l10n))),
        );
      }
    }
  }

  Future<void> _openRouteInGoogleMaps(List<LatLng> points) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final truncated =
        await ref.read(mapsLauncherServiceProvider).openRoute(points);
    if (truncated && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n
            .routeTruncated(MapsLauncherService.maxGoogleWaypoints + 1)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(widget.itineraryId));
    final currentUserId = ref.watch(myProfileProvider).value?.id;
    final isOwner = currentUserId != null &&
        itineraryAsync.value?.userId == currentUserId;
    // Owner OR a granted editor. `can_edit` is the server's answer; ownership
    // is OR-ed in because it is the one case the client can derive for itself,
    // and a payload without the key (a summary, or a backend older than this
    // feature) must not take the owner's own pencil away.
    //
    // A rendering hint either way — the server re-derives it on every write, so
    // a stale true costs a clean 403 rather than a bad save. isOwner survives
    // beside it for what editing does NOT include: deleting the trip, who can
    // see it, the cover, the editor list.
    final mayEdit = isOwner || (itineraryAsync.value?.canEdit ?? false);
    final lockSession = ref.watch(editLockProvider(widget.itineraryId));

    final ownerUserId = itineraryAsync.value?.userId ?? '';

    return PopScope(
      canPop: !_editMode,
      onPopInvokedWithResult: (didPop, _) {
        // didPop false means canPop refused it — an edit-mode exit or a
        // cancelled predictive-back swipe, neither of which is a close.
        if (didPop) {
          _playCloseCue();
          return;
        }
        _exitEditMode();
      },
      child: Scaffold(
        backgroundColor: nt.surface,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false, // cover hero extends behind status bar
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth:
                      isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
              child: itineraryAsync.when(
                loading: () => const Center(child: NTripiRouteLoader()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        extractErrorMessage(
                            error as dynamic, AppLocalizations.of(context)!),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref
                            .read(itineraryDetailProvider(widget.itineraryId)
                                .notifier)
                            .refresh(),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
                data: (itinerary) {
                  final allStops = itinerary.stops;
                  final tracks = itinerary.tracks;
                  final canEdit = mayEdit && _editMode;

                  // Freshly created + still empty → drop the owner straight into
                  // the first-stop form. Pushed from here rather than from the
                  // create form so this screen stays underneath: the stop form's
                  // save AND discard paths both pop back onto it, and the detail
                  // provider is already loaded, so addStop's If-Match is not ''.
                  if (widget.justCreated &&
                      isOwner &&
                      tracks.isEmpty &&
                      !_editMode &&
                      !_firstStopFormOpened) {
                    _firstStopFormOpened = true; // set now so we schedule exactly once
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_openStopForm());
                    });
                  }

                  // Opening cue. The screen always mounts with _editMode =
                  // false and the pencil that sets it needs a rendered screen,
                  // so the first successful load IS "opened in view mode" —
                  // there is no reachable edit-mode case to exclude here.
                  // Skipped for justCreated: that branch pushes the stop form
                  // on this same frame, over which a cue would be nonsense.
                  if (!_openSoundPlayed && !widget.justCreated) {
                    _openSoundPlayed = true; // set now so we schedule exactly once
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) ref.read(sfxServiceProvider).play(Sfx.openItinerary);
                    });
                  }

                  // Only teach the gesture once there is something to press —
                  // on an empty itinerary the tip would point at nothing, and
                  // it must not pre-empt the add-cover hint on a fresh trip.
                  final hasLongPressTarget = tracks.isNotEmpty ||
                      itinerary.annotations.isNotEmpty ||
                      itinerary.recommendedPeriod != null ||
                      (itinerary.description?.isNotEmpty ?? false) ||
                      (itinerary.coverImageUrl?.isNotEmpty ?? false);
                  // Wait a frame so the Edit pencil the tip points at exists.
                  if (mayEdit &&
                      !_editMode &&
                      !_longPressHintShown &&
                      hasLongPressTarget) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _maybeShowLongPressHint();
                    });
                  }

                  final segmentByFromStop = {
                    for (final seg in itinerary.segments) seg.fromStopId: seg,
                  };
                  // Keyed by toStopId so read mode can look up the inbound
                  // segment and show it before the destination stop.
                  final segmentByToStop = {
                    for (final seg in itinerary.segments) seg.toStopId: seg,
                  };
                  final mappableStops = allStops
                      .where((s) => s.lat != null && s.lng != null)
                      .toList();
                  final polylinePoints =
                      mappableStops.map((s) => LatLng(s.lat!, s.lng!)).toList();
                  final mapCenter = mappableStops.isNotEmpty
                      ? LatLng(
                          mappableStops.first.lat!, mappableStops.first.lng!)
                      : const LatLng(48.8566, 2.3522);
                  // Not mappableStops — that flattens parallel alternatives.
                  final routePoints = _routePoints(tracks);

                  // Build interleaved list from tracks (server already sorted by rank).
                  List<Widget> buildInterleavedList() {
                    final items = <Widget>[];
                    for (var i = 0; i < tracks.length; i++) {
                      final track = tracks[i];
                      final trackStops = track.stops;
                      if (trackStops.isEmpty) continue;
                      final hasNextTrack = i < tracks.length - 1;
                      final nextTrack = hasNextTrack ? tracks[i + 1] : null;
                      final trackIndex = i + 1;

                      // Divider between stop groups (not before the first).
                      if (items.isNotEmpty) {
                        items.add(const ShadowDivider(
                            height: 1, indent: 14, endIndent: 14));
                      }

                      // READ MODE: show the inbound transit BEFORE this stop
                      // (i.e. the segment that arrives at the active parallel).
                      // Edit mode keeps the transit below the origin stop (handled
                      // by getSegment inside ParallelStopGroup below).
                      if (!canEdit && i > 0) {
                        final activeIdx = _activeParallelByTrack[track.id] ?? 0;
                        final activeStop = trackStops.length > activeIdx
                            ? trackStops[activeIdx]
                            : trackStops.first;
                        final inbound = segmentByToStop[activeStop.id];
                        if (inbound != null) {
                          items.add(LongPressToEdit(
                            // Transit has no standalone form — leg rows only
                            // become tappable once the list is in edit mode.
                            onEdit: mayEdit ? _enterEditMode : null,
                            child: SegmentCard(
                              key: ValueKey('seg-in-${inbound.id}'),
                              segment: inbound,
                              currency: itinerary.currency,
                              itineraryId: widget.itineraryId,
                              // no onEdit/onDelete → renders as compact _TransitRow
                            ),
                          ));
                        }
                      }

                      items.add(ParallelStopGroup(
                        key:
                            _trackKeys.putIfAbsent(track.id, () => GlobalKey()),
                        stops: trackStops,
                        currency: itinerary.currency,
                        itineraryId: widget.itineraryId,
                        editMode: canEdit,
                        trackIndex: trackIndex,
                        // Only meaningful when there's somewhere to move to:
                        // another track exists, or this track has parallels to extract.
                        canMoveToTrack: canEdit &&
                            (tracks.length > 1 || trackStops.length > 1),
                        onMoveToTrack: canEdit
                            ? (activeStop) => showMoveStopToTrackSheet(
                                  context: context,
                                  itineraryId: widget.itineraryId,
                                  stop: activeStop,
                                  tracks: tracks,
                                  segments: itinerary.segments,
                                  onMoved: _scrollToTrack,
                                )
                            : null,
                        getSegment: (fromStopId) {
                          // Read mode: transit is rendered before the destination
                          // stop in buildInterleavedList, not inside the group.
                          if (!canEdit) return null;
                          final seg = segmentByFromStop[fromStopId];
                          if (seg == null) return null;
                          if (nextTrack != null) {
                            final nextIdx =
                                _activeParallelByTrack[nextTrack.id] ?? 0;
                            final nextStop = nextTrack.stops.length > nextIdx
                                ? nextTrack.stops[nextIdx]
                                : nextTrack.stops.first;
                            if (seg.toStopId != nextStop.id) return null;
                          }
                          return seg;
                        },
                        onViewStop: (stop) => context.push(
                          '/itineraries/${widget.itineraryId}/stops/${stop.id}',
                        ),
                        onAddParallel: canEdit
                            ? (trackId) => context.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {'trackId': trackId},
                                )
                            : null,
                        onEditStop: canEdit
                            ? (stop) => context.push(
                                  '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                                )
                            : null,
                        // Flip the list into edit mode first so returning from
                        // the form lands on the editable list, not read mode.
                        onLongPressEditStop: mayEdit && !_editMode
                            ? (stop) {
                                _enterEditMode();
                                context.push(
                                  '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                                );
                              }
                            : null,
                        onAddAnnotation:
                            canEdit ? (stop) => _addAnnotation(stop) : null,
                        onEditAnnotation: canEdit
                            ? (stop, a) => _editAnnotation(stop, a)
                            : null,
                        onDeleteAnnotation: canEdit
                            ? (stop, a) => _deleteAnnotation(stop.id, a)
                            : null,
                        onEditSegment: canEdit
                            ? (seg) => context.push(
                                  '/itineraries/${widget.itineraryId}/segments/${seg.id}/edit',
                                )
                            : null,
                        onDeleteSegment: canEdit ? _confirmDeleteSegment : null,
                        onAddTransit: canEdit && nextTrack != null
                            ? (fromStopId) {
                                final nextIdx =
                                    _activeParallelByTrack[nextTrack.id] ?? 0;
                                final toStop = nextTrack.stops.length > nextIdx
                                    ? nextTrack.stops[nextIdx]
                                    : nextTrack.stops.first;
                                return _addSegmentWithLeg(
                                    fromStopId, toStop.id);
                              }
                            : null,
                        onPageChanged: (idx) => setState(() {
                          _activeParallelByTrack[track.id] = idx;
                        }),
                        onAddStopBefore: canEdit && i == 0
                            ? () async {
                                context.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {'beforeTrackId': track.id},
                                );
                              }
                            : null,
                        onAddStopAfter: canEdit
                            ? () async {
                                final router = GoRouter.of(context);
                                // SEGMENT ORPHAN CHECK: inserting a new track
                                // between track[i] and track[i+1] hides any
                                // segment connecting their stops (it still
                                // exists but is no longer between adjacent
                                // tracks). Warn the user and offer deletion.
                                if (nextTrack != null) {
                                  final nextStopIds =
                                      nextTrack.stops.map((s) => s.id).toSet();
                                  final orphaned = trackStops
                                      .map((s) => segmentByFromStop[s.id])
                                      .whereType<TransitSegment>()
                                      .where((seg) =>
                                          nextStopIds.contains(seg.toStopId))
                                      .toList();

                                  if (orphaned.isNotEmpty) {
    final nt = context.nt;
                                    final n = orphaned.length;
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                            l10n.deleteOrphanSegmentsTitle(n)),
                                        content: Text(l10n
                                            .deleteOrphanSegmentsMessage(n)),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: Text(l10n.cancel),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: nt.ratingRed,
                                            ),
                                            child: Text(l10n.deleteAndContinue),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed != true || !mounted) return;

                                    final notifier = ref.read(
                                      itineraryDetailProvider(
                                              widget.itineraryId)
                                          .notifier,
                                    );
                                    for (final seg in orphaned) {
                                      await notifier.deleteSegment(seg.id);
                                    }
                                    if (!mounted) return;
                                  }
                                }

                                router.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {
                                    'afterTrackId': track.id,
                                    if (nextTrack != null)
                                      'beforeTrackId': nextTrack.id,
                                  },
                                );
                              }
                            : null,
                      ));
                    }
                    return items;
                  }

                  // Resolve absolute cover URL once.
                  final coverUrl = itinerary.coverImageUrl != null
                      ? (itinerary.coverImageUrl!.startsWith('/')
                          ? '$kApiBaseUrl${itinerary.coverImageUrl}'
                          : itinerary.coverImageUrl!)
                      : null;

                  return RefreshIndicator(
                    onRefresh: () async {
                      // Offline: skip entirely — evicting the cover would
                      // delete an image the device can't re-download.
                      if (!isOnlineNow(ref)) return;
                      // R2 reuses the same key on cover replacement, so the
                      // URL string never changes. Evict CachedNetworkImage's
                      // disk + memory entry for the current cover URL so a
                      // pull-to-refresh actually shows the new image when
                      // the owner has replaced it from another device.
                      if (coverUrl != null) {
                        await CachedNetworkImage.evictFromCache(
                          coverUrl,
                          cacheManager: NtripiImageCacheManager(),
                        );
                      }
                      await ref
                          .read(itineraryDetailProvider(widget.itineraryId)
                              .notifier)
                          .refresh();
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // ── Cover hero (240px full-bleed) ──────────────────
                        SliverToBoxAdapter(
                          child: _CoverHero(
                            coverUrl: coverUrl,
                            itinerary: itinerary,
                            canEdit: mayEdit,
                            editMode: _editMode,
                            editDetailsButtonKey: _editDetailsButtonKey,
                            enterEditButtonKey: _enterEditButtonKey,
                            onCoverTap: isOwner ? _showAddCoverHint : null,
                            // Reached via go() after create / stop-delete, so
                            // there may be nothing on the stack to pop — and
                            // popOr's go() branch never reaches the PopScope,
                            // which is why the cue is fired here too.
                            onBack: () {
                              _playCloseCue();
                              context.popOr('/itineraries');
                            },
                            onShare: itinerary.visibility !=
                                    ItineraryVisibility.onlyMe
                                ? () => ref
                                    .read(shareServiceProvider)
                                    .shareItinerary(itinerary, l10n)
                                : null,
                            onReport: mayEdit
                                ? null
                                : () => showReportContentSheet(
                                    context,
                                    ref,
                                    ReportTarget.itinerary(widget.itineraryId),
                                  ),
                            // mayEdit: the form behind this button renders a
                            // reduced set for an editor — title, currency and
                            // best time to visit, all of which the server
                            // already accepts from them — and hides every
                            // owner-only control rather than the whole screen.
                            onEditDetails: mayEdit ? _openDetailsForm : null,
                            onEnterEdit:
                                mayEdit && !_editMode ? _enterEditMode : null,
                            onExitEdit:
                                mayEdit && _editMode ? _exitEditMode : null,
                            // Long-press anywhere on the hero is a shortcut to
                            // the same screen the tune button opens — so it
                            // carries the same gate.
                            onLongPressEdit:
                                mayEdit && !_editMode ? _openDetailsForm : null,
                          ),
                        ),

                        // ── Someone else is editing ────────────────────────
                        // Shown to anyone who could edit but currently cannot,
                        // including this same person on another device. Absent
                        // while WE hold the claim — the banner is about being
                        // blocked, and blocking yourself is not information.
                        if (mayEdit &&
                            !lockSession.holdsClaim &&
                            lockSession.lock != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: EditLockBanner(
                                lock: lockSession.lock!,
                                // The owner never waits out the timeout.
                                canTakeOverNow:
                                    isOwner || lockSession.canTakeOverNow,
                                isOwner: isOwner,
                                busy: lockSession.busy,
                                onTakeOver: () =>
                                    _confirmTakeOver(lockSession.lock!),
                              ),
                            ),
                          ),

                        // ── Moderator-hidden notice (author only) ──────────
                        // The server only sends hidden=true to the owner, so
                        // the isOwner check is defense in depth.
                        if (isOwner && itinerary.hidden)
                          SliverToBoxAdapter(
                            child: ModerationHiddenBanner(
                              message: l10n.hiddenBannerMessage,
                              onAppeal: () => showAppealSheet(
                                context,
                                ref,
                                targetType: 'itinerary',
                                targetId: itinerary.id,
                              ),
                            ),
                          ),

                        // ── Owner row ──────────────────────────────────────
                        if (ownerUserId.isNotEmpty)
                          SliverToBoxAdapter(
                            child: ref
                                .watch(userProfileProvider(ownerUserId))
                                .when(
                                  loading: () => const OwnerRowSkeleton(),
                                  error: (_, __) => const SizedBox.shrink(),
                                  data: (owner) => _OwnerRow(
                                    owner: owner,
                                    itinerary: itinerary,
                                    itineraryId: widget.itineraryId,
                                  ),
                                ),
                          ),

                        // ── Meta chips ─────────────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _DetailMetaChip(
                                  icon: Icons.schedule_rounded,
                                  label: itinerary.formattedDuration(l10n),
                                ),
                                _DetailMetaChip(
                                  icon: Icons.payments_rounded,
                                  label: itinerary.formattedCost(l10n),
                                ),
                                _DetailMetaChip(
                                  icon: Icons.location_on_rounded,
                                  label: l10n.stopCount(allStops.length),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Recommended period ─────────────────────────────
                        // Own row rather than a 4th meta chip: the "why" note
                        // is the useful half and needs more than a pill.
                        if (canEdit)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _RecommendedPeriodEditRow(
                                period: itinerary.recommendedPeriod,
                                saving: _savingPeriod,
                                onTap: () => _editRecommendedPeriod(
                                    itinerary.recommendedPeriod),
                              ),
                            ),
                          )
                        else if (itinerary.recommendedPeriod != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: LongPressToEdit(
                                onEdit: mayEdit
                                    ? () => _editRecommendedPeriod(
                                        itinerary.recommendedPeriod)
                                    : null,
                                child: _RecommendedPeriodRow(
                                    period: itinerary.recommendedPeriod!),
                              ),
                            ),
                          ),

                        // ── Description ────────────────────────────────────
                        // In edit mode the description is a tappable row that
                        // opens the shared markdown editor.
                        if (canEdit)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _DescriptionEditRow(
                                description: itinerary.description,
                                onTap: () =>
                                    _editDescription(itinerary.description),
                              ),
                            ),
                          )
                        else if (itinerary.description != null &&
                            itinerary.description!.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: LongPressToEdit(
                                onEdit: mayEdit
                                    ? () =>
                                        _editDescription(itinerary.description)
                                    : null,
                                child: InertMarkdownBody(
                                    data: itinerary.description!),
                              ),
                            ),
                          ),

                        // ── Itinerary annotations ──────────────────────────
                        if (itinerary.annotations.isNotEmpty || canEdit)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        l10n.annotationsSection,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: nt.text2,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      if (canEdit) ...[
                                        const Spacer(),
                                        // Tinted pill matching the stop-card "Add note" affordance.
                                        OfflineGate(
                                          builder: (online) => GestureDetector(
                                          onTap: online
                                              ? _addItineraryAnnotation
                                              : null,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: nt.editBlueTint,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: nt.editBlue.withValues(
                                                      alpha: 0.13)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.add_rounded,
                                                    size: 13, color: nt.editBlue),
                                                const SizedBox(width: 3),
                                                Text(
                                                  l10n.addAnnotationButton,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: nt.editBlue),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (itinerary.annotations.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 4),
                                      child: Text(
                                        l10n.noAnnotationsYet,
                                        style: TextStyle(
                                            color: nt.text3, fontSize: 13),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: itinerary.annotations
                                            .map(
                                              (a) => AnnotationChip(
                                                annotation: Annotation(
                                                  id: a.id,
                                                  stopId: a.itineraryId,
                                                  type: a.type,
                                                  content: a.content,
                                                  createdAt: a.createdAt,
                                                  updatedAt: a.updatedAt,
                                                ),
                                                onEdit: canEdit
                                                    ? () =>
                                                        _editItineraryAnnotation(
                                                            a)
                                                    : null,
                                                onDelete: canEdit
                                                    ? () =>
                                                        _deleteItineraryAnnotation(
                                                            a)
                                                    : null,
                                                // Built from the outer `a`:
                                                // the adapted Annotation above
                                                // carries the itinerary id in
                                                // its stopId field.
                                                onReport: mayEdit
                                                    ? null
                                                    : () =>
                                                        showReportContentSheet(
                                                          context,
                                                          ref,
                                                          ReportTarget
                                                              .itineraryAnnotation(
                                                            widget.itineraryId,
                                                            a.id,
                                                          ),
                                                        ),
                                                onLongPressEdit: mayEdit &&
                                                        !_editMode
                                                    ? () =>
                                                        _editItineraryAnnotation(
                                                            a)
                                                    : null,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                        // ── List / Map toggle ──────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                            child: Row(
                              children: [
                                Text(
                                  _mapVisible
                                      ? l10n.mapSection
                                      : canEdit
                                          ? l10n.editStopsButton
                                          : l10n.stopsList,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: nt.text2,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const Spacer(),
                                // Edit mode controls
                                if (canEdit &&
                                    itineraryAsync.value != null &&
                                    itineraryAsync.value!.tracks.length >=
                                        2) ...[
                                  EditPencilButton(
                                    icon: Icons.reorder,
                                    iconSize: 20,
                                    tooltip: l10n.reorderTracksTooltip,
                                    onTap: () => showTrackReorderSheet(
                                      context: context,
                                      itineraryId: widget.itineraryId,
                                      tracks:
                                          itineraryAsync.value!.tracks,
                                      segments:
                                          itineraryAsync.value!.segments,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // Save (bookmark) — non-owners only, hidden in
                                // edit mode. currentUserId guard avoids the owner
                                // briefly seeing it while their profile loads.
                                if (!_editMode &&
                                    currentUserId != null &&
                                    !isOwner) ...[
                                  _BookmarkPillButton(
                                    saved: ref.watch(isItinerarySavedProvider(
                                        widget.itineraryId)),
                                    onTap: () => _toggleSaved(itinerary),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // Open the full trajet in Google Maps — the
                                // only map app with multi-stop deep links.
                                // Hidden in edit mode alongside the bookmark.
                                if (!_editMode && routePoints.length >= 2) ...[
                                  _RoutePillButton(
                                    tooltip: l10n.openRouteInMaps,
                                    onTap: () =>
                                        _openRouteInGoogleMaps(routePoints),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // List/Map pill toggle
                                _SegmentToggle(
                                  showMap: _mapVisible,
                                  onChanged: (showMap) =>
                                      setState(() => _mapVisible = showMap),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Map ────────────────────────────────────────────
                        if (_mapVisible)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  height: 200,
                                  child: Stack(
                                    children: [
                                      FlutterMap(
                                        options: MapOptions(
                                          initialCenter: mapCenter,
                                          initialZoom:
                                              mappableStops.isNotEmpty ? 12 : 5,
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate:
                                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            userAgentPackageName:
                                                'com.ntripi.app',
                                          ),
                                          if (polylinePoints.length >= 2)
                                            PolylineLayer(
                                              polylines: [
                                                Polyline(
                                                  points: polylinePoints,
                                                  color: nt.canopy.withValues(
                                                      alpha: 0.6),
                                                  strokeWidth: 3,
                                                ),
                                              ],
                                            ),
                                          MarkerLayer(
                                            markers: mappableStops.map((stop) {
                                              final color =
                                                  _markerColors(nt)[
                                                          stop.type] ??
                                                      nt.text2;
                                              return Marker(
                                                point: LatLng(
                                                    stop.lat!, stop.lng!),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(3),
                                                  decoration: BoxDecoration(
                                                    color: color,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: nt.overlayChrome,
                                                        width: 2),
                                                  ),
                                                  child: Icon(Icons.place,
                                                      color: nt.overlayChrome,
                                                      size: 10),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          RichAttributionWidget(
                                            attributions: [
                                              TextSourceAttribution(l10n
                                                  .openStreetMapContributors),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // ── Stop list or empty state ────────────────────────
                        if (tracks.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: _EmptyStopsPlaceholder(
                                text: l10n.noStopsYet,
                                // Owner in either mode gets the one-tap path;
                                // viewers get the placeholder alone.
                                actionLabel: l10n.addFirstStop,
                                onAction: mayEdit ? _openStopForm : null,
                              ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              decoration: BoxDecoration(
                                color: nt.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: nt.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: buildInterleavedList(),
                              ),
                            ),
                          ),

                        // ── Rate this trip CTA (read mode) ─────────────────
                        if (!canEdit && tracks.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: _RateCta(
                                itineraryId: widget.itineraryId,
                                itinerary: itinerary,
                                isOwner: isOwner,
                                onEdit: _enterEditMode,
                              ),
                            ),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Description edit row ────────────────────────────────────────────────────
// Shown only in edit mode. Mirrors MarkdownNotesEditor's bordered-header look
// but is a tappable summary that opens the shared markdown editor.
class _DescriptionEditRow extends StatelessWidget {
  final String? description;
  final VoidCallback onTap;

  const _DescriptionEditRow({required this.description, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final hasText = description != null && description!.trim().isNotEmpty;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(l10n.descriptionLabel, style: labelStyle),
                  const SizedBox(width: 2),
                  // Stays interactive inside the InkWell — its own tap wins.
                  FieldHelpIcon(
                    helpTitle: l10n.descriptionLabel,
                    helpMessage: l10n.descriptionHelp,
                    size: 16,
                  ),
                  const Spacer(),
                  Icon(Icons.edit_outlined, size: 18, color: nt.forest),
                ],
              ),
              const SizedBox(height: 6),
              // IgnorePointer so the markdown's selectable text doesn't swallow
              // the tap meant for the row's InkWell.
              if (hasText)
                IgnorePointer(child: InertMarkdownBody(data: description!))
              else
                Text(
                  l10n.addDescriptionLabel,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cover hero (240 px full-bleed) ──────────────────────────────────────────
// Back button top-left; share / edit / done top-right (glassmorphism).
// Visibility badge + title + location overlay at the bottom.
class _CoverHero extends StatefulWidget {
  final String? coverUrl;
  final Itinerary itinerary;
  // Whether to render the EDIT chrome (tune + pencil) instead of the viewer's
  // flag button. Ownership no longer answers this — an editor gets the pencil
  // and never the flag, which is what keeps the two roles disjoint.
  final bool canEdit;
  final bool editMode;
  // Attached to the Edit details button so the add-cover hint can point at it.
  final GlobalKey editDetailsButtonKey;
  // Attached to the Edit pencil so the long-press tip can point at it.
  final GlobalKey enterEditButtonKey;
  final VoidCallback onBack;
  final VoidCallback? onShare;
  // Viewer-only (non-owner) report action; null hides the flag button.
  final VoidCallback? onReport;
  // Owner-only: opens the settings form (cover, visibility, editors, delete).
  // Null for a granted editor, which is also what hides the tune button.
  final VoidCallback? onEditDetails;
  final VoidCallback? onEnterEdit;
  final VoidCallback? onExitEdit;
  // Owner-only tap on the placeholder cover (null makes it inert for viewers).
  final VoidCallback? onCoverTap;
  // Owner shortcut in read mode: long-press the hero to open the edit form.
  final VoidCallback? onLongPressEdit;

  const _CoverHero({
    required this.coverUrl,
    required this.itinerary,
    required this.canEdit,
    required this.editMode,
    required this.editDetailsButtonKey,
    required this.enterEditButtonKey,
    required this.onBack,
    this.onShare,
    this.onReport,
    this.onEditDetails,
    this.onEnterEdit,
    this.onExitEdit,
    this.onCoverTap,
    this.onLongPressEdit,
  });

  @override
  State<_CoverHero> createState() => _CoverHeroState();
}

class _CoverHeroState extends State<_CoverHero> {
  bool _imgError = false;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final itinerary = widget.itinerary;

    return LongPressToEdit(
      onEdit: widget.onLongPressEdit,
      child: SizedBox(
      height: 240 + topPad,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover image or branded trip-map placeholder
          if (widget.coverUrl != null &&
              widget.coverUrl!.isNotEmpty &&
              !_imgError)
            CachedNetworkImage(
              imageUrl: widget.coverUrl!,
              cacheManager: NtripiImageCacheManager(),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _imgError = true);
                });
                // pill mid-frame — clear of the glass buttons above and the
                // title/badge overlay below
                return const ItineraryCoverPlaceholder(
                    labelAlignment: Alignment(0, 0.1));
              },
            )
          else
            GestureDetector(
              // opaque: the trip-map CustomPaint doesn't hit-test, so without
              // this only the label pill would register the tap
              behavior: HitTestBehavior.opaque,
              onTap: widget.onCoverTap,
              child: const ItineraryCoverPlaceholder(
                  labelAlignment: Alignment(0, 0.1)),
            ),

          // Gradient overlay: dark at top + bottom, transparent in middle.
          // IgnorePointer: a BoxDecoration hit-tests as opaque, which would
          // swallow taps meant for the placeholder cover below.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.3, 0.6, 1.0],
                  colors: [
                    // constant ink scrim — always sits over the cover image
                    NtripiBrand.scrimInk.withValues(alpha: 0.4),
                    NtripiBrand.scrimInk.withValues(alpha: 0),
                    NtripiBrand.scrimInk.withValues(alpha: 0),
                    NtripiBrand.scrimInk.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
          ),

          // Top chrome: back button left, actions right
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                if (widget.editMode) ...[
                  // Leading edge — the opposite end from the pencil that turned
                  // edit mode on, so the two never land under the same thumb.
                  _GlassButton(
                    icon: Icons.check_rounded,
                    onTap: widget.onExitEdit,
                  ),
                  const Spacer(),
                ] else ...[
                  _GlassButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: widget.onBack,
                  ),
                  const Spacer(),
                  if (widget.onShare != null) ...[
                    _GlassButton(
                      icon: Icons.share_rounded,
                      onTap: widget.onShare,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (!widget.canEdit && widget.onReport != null) ...[
                    _GlassButton(
                      icon: Icons.flag_outlined,
                      onTap: widget.onReport,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (widget.canEdit) ...[
                    // Keyed off the callback, not canEdit: this widget renders
                    // what it is given and never infers who may open what.
                    if (widget.onEditDetails != null) ...[
                      _GlassButton(
                        key: widget.editDetailsButtonKey,
                        icon: Icons.tune_rounded,
                        onTap: widget.onEditDetails,
                      ),
                      const SizedBox(width: 6),
                    ],
                    EditPencilButton(
                      key: widget.enterEditButtonKey,
                      onTap: widget.onEnterEdit,
                      iconSize: 22,
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Bottom overlay: visibility badge + title + location
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                VisibilityBadge(visibility: itinerary.visibility, onDark: true),
                const SizedBox(height: 8),
                Text(
                  itinerary.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: NtripiBrand.chrome,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// Centered place-pin + caption shown when an itinerary has no stops.
// [onAction] adds the owner's call-to-action button; null keeps it inert for viewers.
class _EmptyStopsPlaceholder extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback? onAction;

  const _EmptyStopsPlaceholder({
    required this.text,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      children: [
        Icon(Icons.place_outlined, size: 48, color: nt.text3),
        const SizedBox(height: 12),
        Text(text),
        if (onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: Text(actionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: nt.forest,
              foregroundColor: nt.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }
}

// Small frosted-glass icon button for the hero overlay.
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GlassButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          // dark tint ensures visibility against any cover image, incl. white
          color: nt.buttonTransparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NtripiBrand.chrome.withValues(alpha: 0.2)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: NtripiBrand.chrome, size: 22),
      ),
    );
  }
}

// Visibility badge styled for the dark hero overlay.
// ─── Owner row ────────────────────────────────────────────────────────────────
// Owner avatar + name + personal rating (viewer) + community rating.
// Community rating (right) taps → ratings screen.
// Personal rating (middle) taps → rate dialog.
class _OwnerRow extends ConsumerWidget {
  final User owner;
  final Itinerary itinerary;
  final String itineraryId;

  const _OwnerRow({
    required this.owner,
    required this.itinerary,
    required this.itineraryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final avatarUrl = owner.avatarUrl != null
        ? (owner.avatarUrl!.startsWith('/')
            ? '$kApiBaseUrl${owner.avatarUrl}'
            : owner.avatarUrl!)
        : null;
    final ratingAvg = itinerary.ratingAvg;
    final myRating = ref.watch(myRatingProvider(itineraryId)).value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          // Owner avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: nt.mist,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(
                    avatarUrl,
                    cacheManager: NtripiImageCacheManager(),
                  )
                : null,
            child: avatarUrl == null
                ? Text(
                    owner.nameForDisplay.isNotEmpty
                        ? owner.nameForDisplay[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: nt.forest, fontWeight: FontWeight.w700),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  owner.nameForDisplay,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
                Text(
                  owner.handle,
                  style: TextStyle(fontSize: 11, color: nt.text2),
                ),
              ],
            ),
          ),

          // ── Viewer's personal rating ────────────────────────────────────
          OfflineGate(
            builder: (online) => GestureDetector(
            onTap: !online
                ? null
                : () => showRateItineraryDialog(
                      context,
                      ref,
                      itineraryId: itineraryId,
                      current: myRating,
                    ),
            child: myRating != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(
                          5,
                          (i) => Icon(
                                i < myRating.stars
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: i < myRating.stars
                                    ? nt.rating(myRating.stars.toDouble())
                                    : nt.text3,
                              )),
                      const SizedBox(width: 4),
                      Icon(Icons.person_rounded,
                          size: 11, color: nt.forest),
                    ],
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: nt.forest),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 13, color: nt.forest),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.rateIt,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: nt.forest),
                        ),
                      ],
                    ),
                  ),
            ),
          ),

          const SizedBox(width: 10),
          Container(width: 1.1, height: 8, color: nt.bark),
          const SizedBox(width: 10),
          // ── Community rating ────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push('/itineraries/$itineraryId/ratings'),
            child: ratingAvg != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_rounded,
                          size: 11, color: nt.forest),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded,
                          size: 13, color: nt.rating(ratingAvg)),
                      const SizedBox(width: 4),
                      Text(
                        ratingAvg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: nt.rating(ratingAvg),
                        ),
                      ),
                      Text(
                        ' (${itinerary.ratingCount})',
                        style: TextStyle(
                            fontSize: 11,
                            color: nt.text3,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded, size: 14, color: nt.text3),
                      SizedBox(width: 4),
                      Text('—', style: TextStyle(fontSize: 12, color: nt.text3)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Recommended period ───────────────────────────────────────────────────────
// The author's "best time to visit", between the meta chips and the description.
// Read-only variant; the owner sees _RecommendedPeriodEditRow instead.
class _RecommendedPeriodRow extends StatelessWidget {
  final RecommendedPeriod period;

  const _RecommendedPeriodRow({required this.period});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final localeName = l10n.localeName;
    final dates = period.dateLabel(localeName);
    final weekdays = period.weekdaysLabel(l10n, localeName);
    final note = period.note?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        // bark (ink), not shadow: a translucent fill must flip per theme, else
        // black-on-dark makes the block vanish against the dark surface.
        color: nt.bark.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: nt.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_available_rounded, size: 16, color: nt.forest),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bestTimeToVisit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: nt.text2,
                    letterSpacing: 0.4,
                  ),
                ),
                // Dates and weekdays are independent — an author may give only
                // one, so each line renders on its own terms.
                if (dates != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    dates,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ],
                if (weekdays != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    weekdays,
                    style: TextStyle(fontSize: 12.5, color: nt.text2),
                  ),
                ],
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: TextStyle(fontSize: 12.5, color: nt.text2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Edit-mode variant, styled after _DescriptionEditRow. Always rendered for the
// owner, even with nothing set — otherwise an empty period is invisible and the
// feature is undiscoverable outside the Edit details form.
class _RecommendedPeriodEditRow extends StatelessWidget {
  final RecommendedPeriod? period;
  final VoidCallback onTap;

  /// The PATCH behind [onTap] is still in flight. The row goes on showing the
  /// value the server holds — the edit is not saved yet, and swapping early
  /// would claim otherwise and then quietly swap back if the save failed.
  final bool saving;

  const _RecommendedPeriodEditRow({
    required this.period,
    required this.onTap,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final localeName = l10n.localeName;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        );
    final dates = period?.dateLabel(localeName);
    final weekdays = period?.weekdaysLabel(l10n, localeName);
    final note = period?.note?.trim();
    final hasAny = period != null && !period!.isEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Refused mid-save: a second picker would open on the value being
        // replaced, and its Done would race the PATCH already in flight.
        onTap: saving ? null : onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(l10n.bestTimeToVisit, style: labelStyle),
                  const Spacer(),
                  // Same 18px box as the pencil it stands in for, so the header
                  // does not reflow for the length of the save.
                  if (saving)
                    const NTripiRingLoader(size: 18)
                  else
                    Icon(Icons.edit_outlined, size: 18, color: nt.forest),
                ],
              ),
              const SizedBox(height: 6),
              // Dimmed rather than blanked: the old value is still the true one
              // until the PATCH answers, and an empty row would read as cleared.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: saving ? 0.4 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasAny)
                      Text(
                        l10n.addBestTimeToVisit,
                        style: TextStyle(color: Theme.of(context).hintColor),
                      )
                    else ...[
                      if (dates != null)
                        Text(
                          dates,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: nt.bark,
                          ),
                        ),
                      if (weekdays != null)
                        Text(weekdays,
                            style: TextStyle(fontSize: 12.5, color: nt.text2)),
                      if (note != null && note.isNotEmpty)
                        Text(note,
                            style: TextStyle(fontSize: 12.5, color: nt.text2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail meta chip ─────────────────────────────────────────────────────────
class _DetailMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // bark (ink), not shadow: a translucent fill must flip per theme, else
        // black-on-dark makes the pill vanish against the dark surface.
        color: nt.bark.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: nt.bark),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: nt.bark,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Route pill button ────────────────────────────────────────────────────────
// Forest-tinted sibling of EditPencilButton — nt.editBlue is reserved for Edit
// affordances, and opening an external map app must stay usable offline.
class _RoutePillButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const _RoutePillButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: nt.mist,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: nt.forest.withValues(alpha: 0.13)),
            ),
            child:
                Icon(Icons.directions_rounded, size: 20, color: nt.forest),
          ),
        ),
      ),
    );
  }
}

// ─── Bookmark pill button ─────────────────────────────────────────────────────
// Sibling of _RoutePillButton — forest/mist so the two adjacent buttons match.
// Gated by OfflineGate because saving is a mutation; filled ⇔ outlined tracks
// the saved state read from isItinerarySavedProvider.
class _BookmarkPillButton extends StatelessWidget {
  final bool saved;
  final VoidCallback onTap;

  const _BookmarkPillButton({required this.saved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return OfflineGate(
      builder: (online) => Tooltip(
        message: saved ? l10n.unsaveItineraryTooltip : l10n.saveItineraryTooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: online ? onTap : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: nt.mist,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: nt.forest.withValues(alpha: 0.13)),
              ),
              child: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                size: 20,
                color: nt.forest,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── List / Map pill toggle ───────────────────────────────────────────────────
class _SegmentToggle extends StatelessWidget {
  final bool showMap;
  final void Function(bool showMap) onChanged;

  const _SegmentToggle({required this.showMap, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: nt.mist,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(
              icon: Icons.list_rounded,
              active: !showMap,
              onTap: () => onChanged(false)),
          _Tab(
              icon: Icons.map_rounded,
              active: showMap,
              onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 28,
        decoration: BoxDecoration(
          color: active ? nt.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: nt.shadow.withValues(alpha: 0.08),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: active ? nt.forest : nt.text2,
        ),
      ),
    );
  }
}

// ─── Rate this trip CTA ───────────────────────────────────────────────────────
// Owners can't rate their own trip — they get the blue "edit" CTA instead.
class _RateCta extends ConsumerWidget {
  final String itineraryId;
  final Itinerary itinerary;
  final bool isOwner;
  final VoidCallback onEdit;

  const _RateCta({
    required this.itineraryId,
    required this.itinerary,
    required this.isOwner,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    if (isOwner) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: Text(AppLocalizations.of(context)!.editYourItinerary),
          style: FilledButton.styleFrom(
            backgroundColor: nt.editBlue,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }
    final myRating = ref.watch(myRatingProvider(itineraryId)).value;
    return SizedBox(
      width: double.infinity,
      child: OfflineGate(
        builder: (online) => FilledButton.icon(
          onPressed: !online
              ? null
              : () => showRateItineraryDialog(
                    context,
                    ref,
                    itineraryId: itineraryId,
                    current: myRating,
                  ),
          icon: const Icon(Icons.star_rounded, size: 18),
          label: Text(myRating != null
              ? AppLocalizations.of(context)!.updateYourRating
              : AppLocalizations.of(context)!.rateThisTrip),
          style: FilledButton.styleFrom(
            backgroundColor: nt.forest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}
