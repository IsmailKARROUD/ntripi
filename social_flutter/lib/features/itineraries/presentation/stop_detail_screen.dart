// presentation/stop_detail_screen.dart — Detail view for one stop.
//
// Shows the stop's hero header, time/cost/rating stats, notes, annotations
// (with full message bodies), inbound/outbound transit with each leg's
// thoughts, and photos grid.
// Navigation: tapping a stop row in the detail view pushes this screen.
//
// No edit mode of its own — it follows the trip's, which is this device holding
// the edit claim. Editing from here claims the trip first, so the trip page is
// in edit mode when the user goes back; a trip somebody else holds answers with
// a pop-up naming them, and offers the takeover when the server allows one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/router/navigation_ext.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/confirm_dialog.dart';
import 'package:social_flutter/features/itineraries/data/link_preview_service.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/annotation_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_lock_banner.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_thoughts.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/link_preview_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/long_press_to_edit.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/open_in_maps_sheet.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/report_content_sheet.dart';
import 'package:social_flutter/features/translation/presentation/translatable_text.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/utils/duration_format.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class StopDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;
  final String stopId;

  const StopDetailScreen({
    super.key,
    required this.itineraryId,
    required this.stopId,
  });

  @override
  ConsumerState<StopDetailScreen> createState() => _StopDetailScreenState();
}

class _StopDetailScreenState extends ConsumerState<StopDetailScreen> {
  // Editing from here can start the trip's editing session, so the claim has
  // to follow this screen as it follows the trip page — opened from a link with
  // no trip page underneath, nothing else would ever hand it back. A field
  // because dispose() must not touch ref (see CLAUDE.md).
  EditLockNotifier? _lockNotifier;

  @override
  void initState() {
    super.initState();
    final lockNotifier = ref.read(editLockProvider(widget.itineraryId).notifier);
    _lockNotifier = lockNotifier;
    lockNotifier.attach();
  }

  @override
  void dispose() {
    // Not a release: going back to the trip page keeps the session the user
    // started here; detach() hands it back only once no screen is left on it.
    _lockNotifier?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itineraryId = widget.itineraryId;
    final stopId = widget.stopId;
    // An invalidation (sign-out) builds a fresh notifier; attach to that one so
    // dispose() detaches from the instance that is actually alive.
    final lockNotifier = ref.watch(editLockProvider(itineraryId).notifier);
    if (!identical(lockNotifier, _lockNotifier)) {
      _lockNotifier = lockNotifier..attach();
    }
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(itineraryId));
    final currentUserId = ref.watch(myProfileProvider).value?.id;
    // The trip's edit mode, wherever it was entered: this device holds the claim.
    final editing = ref.watch(editLockProvider(itineraryId)).holdsClaim;

    return itineraryAsync.when(
      loading: () => const Scaffold(
        body: Center(child: NTripiRouteLoader()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
            child: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      ),
      data: (itinerary) {
        // Locate this stop across all tracks.
        Stop? stop;
        int stopNumber = 0;
        for (var t = 0; t < itinerary.tracks.length; t++) {
          final idx = itinerary.tracks[t].stops
              .indexWhere((s) => s.id == stopId);
          if (idx >= 0) {
            stop = itinerary.tracks[t].stops[idx];
            stopNumber = t + 1; // track index == stop number
            break;
          }
        }

        if (stop == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(AppLocalizations.of(context)!.stopNotFound)),
          );
        }

        final totalStops = itinerary.tracks.length;
        final inbound = itinerary.segments
            .where((s) => s.toStopId == stop!.id)
            .firstOrNull;
        final outbound = itinerary.segments
            .where((s) => s.fromStopId == stop!.id)
            .firstOrNull;
        final isOwner =
            currentUserId != null && itinerary.userId == currentUserId;

        return _StopDetailView(
          stop: stop,
          stopNumber: stopNumber,
          totalStops: totalStops,
          currency: itinerary.currency,
          itineraryId: itineraryId,
          isOwner: isOwner,
          // Owner OR granted editor — the same mayEdit the detail screen uses.
          // Owner-only here handed an editor the report flag instead of the
          // pencil, breaking the can-edit vs report invariant.
          mayEdit: isOwner || itinerary.canEdit,
          editing: editing,
          inboundSegment: inbound,
          outboundSegment: outbound,
          allStops: itinerary.stops,
          // A trip under takedown is never translated, even for its owner.
          translatable: !itinerary.hidden,
        );
      },
    );
  }
}

class _StopDetailView extends ConsumerWidget {
  final Stop stop;
  final int stopNumber;
  final int totalStops;
  final String currency;
  final String itineraryId;
  final bool isOwner;

  /// Owner or granted editor — may edit at all, whatever mode the trip is in.
  final bool mayEdit;

  /// The trip is in edit mode: this device holds its claim.
  final bool editing;
  final TransitSegment? inboundSegment;
  final TransitSegment? outboundSegment;
  final List<Stop> allStops;
  final bool translatable;

  const _StopDetailView({
    required this.stop,
    required this.stopNumber,
    required this.totalStops,
    required this.currency,
    required this.itineraryId,
    required this.isOwner,
    required this.mayEdit,
    required this.editing,
    this.inboundSegment,
    this.outboundSegment,
    required this.allStops,
    required this.translatable,
  });

  /// Run [edit] with the trip in edit mode, claiming it first unless this
  /// device already holds the claim.
  ///
  /// Every write from this page needs X-Edit-Lock and no editor claims one for
  /// itself, so the claim comes before the push. It is kept afterwards: editing
  /// from here enters the trip's edit mode, exactly as a long-press on the trip
  /// page does, and the user leaves it with ✓ there.
  Future<void> _inEditMode(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() edit,
  ) async {
    if (!ref.read(editLockProvider(itineraryId)).holdsClaim) {
      final l10n = AppLocalizations.of(context)!;
      final messenger = ScaffoldMessenger.of(context);
      final bool claimed;
      try {
        claimed =
            await ref.read(editLockProvider(itineraryId).notifier).acquire();
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text(extractErrorMessage(e, l10n))));
        return;
      }
      // ref and context both die with the page.
      if (!context.mounted) return;
      if (!claimed) {
        await _offerTakeOver(context, ref);
        return;
      }
    }
    await edit();
  }

  /// Somebody else holds the trip — or this user, on another device. Say who,
  /// in the banner's words, and offer the takeover the trip page's banner
  /// would: an owner always, your own other device always, an editor once the
  /// server calls the claim takeable. Confirming is the deliberate step; it
  /// only claims the trip, and the user then taps Edit.
  Future<void> _offerTakeOver(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.read(editLockProvider(itineraryId));
    final holder = session.lock;
    if (holder == null) {
      await ConfirmDialog.inform(
        context,
        icon: Icons.lock_outline_rounded,
        title: l10n.apiErrorItineraryLocked,
      );
      return;
    }
    final (:headline, :subline) = editLockCopy(holder, l10n, isOwner: isOwner);
    if (!isOwner && !session.canTakeOverNow) {
      await ConfirmDialog.inform(
        context,
        icon: Icons.lock_outline_rounded,
        title: headline,
        message: subline,
      );
      return;
    }
    final confirmed = await ConfirmDialog.show(
      context,
      icon: Icons.lock_outline_rounded,
      title: headline,
      message: holder.isYou ? l10n.editLockMoveHereMessage : subline,
      confirmLabel: holder.isYou ? l10n.editLockMoveHere : l10n.editLockTakeOver,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final claimed = await ref
          .read(editLockProvider(itineraryId).notifier)
          .acquire(takeover: true);
      if (claimed || !context.mounted) return;
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, l10n))));
      return;
    }
    // Refused after all: the server's answer moved while the pop-up was open.
    final current = ref.read(editLockProvider(itineraryId)).lock;
    messenger.showSnackBar(SnackBar(
      content: Text(current == null
          ? l10n.apiErrorItineraryLocked
          : editLockCopy(current, l10n, isOwner: isOwner).headline),
    ));
  }

  Future<void> _openStopForm(BuildContext context, WidgetRef ref) =>
      _inEditMode(
        context,
        ref,
        () => context.push<void>('/itineraries/$itineraryId/stops/${stop.id}/edit'),
      );

  // Mirrors _editAnnotation in itinerary_detail_screen — a note has no button
  // of its own here, so the long-press is the only way into one.
  Future<void> _editAnnotation(
    BuildContext context,
    WidgetRef ref,
    Annotation annotation,
  ) =>
      _inEditMode(context, ref, () => showAnnotationScreen(
        context,
        isEdit: true,
        initialContent: annotation.content,
        initialType: annotation.type,
        stopName:
            stop.placeName ?? AppLocalizations.of(context)!.stopFallbackName,
        stopSubtitle: stop.placeAddress,
        onSaveAsync: (result) => ref
            .read(itineraryDetailProvider(itineraryId).notifier)
            .updateAnnotation(stop.id, annotation.id,
                content: result.content, type: result.type),
      ));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final hasNotes = stop.notes != null && stop.notes!.trim().isNotEmpty;
    final hasAnnotations = stop.annotations.isNotEmpty;
    final hasTransit = inboundSegment != null || outboundSegment != null;
    // A saved Google link previews the exact place; a coordinate-only stop
    // previews its lat/lng. Prefer the link when both exist (richer place).
    final hasMapLink = stop.mapUrl != null && isGoogleMapsUrl(stop.mapUrl!);
    final hasCoords = stop.lat != null && stop.lng != null;
    final showMapPreview = hasMapLink || hasCoords;
    // One toggle swaps the notes, every annotation and the thoughts on the
    // transport in and out. Place names are never translated: nothing records
    // whether the author typed or imported one.
    final TranslationAnchor translationAnchor =
        (contentType: 'stop', contentId: stop.id);
    final translationMembers = [
      TranslationMember(
        contentType: 'stop',
        contentId: stop.id,
        sourceLang: stop.sourceLang,
        fields: {'notes': stop.notes},
      ),
      for (final a in stop.annotations)
        TranslationMember(
          contentType: 'stop_annotation',
          contentId: a.id,
          sourceLang: a.sourceLang,
          fields: {'content': a.content},
        ),
      ...legThoughtsMembers([
        ...?inboundSegment?.legs,
        ...?outboundSegment?.legs,
      ]),
    ];

    return Scaffold(
      backgroundColor: nt.surface,
      body: CustomScrollView(
        slivers: [
          // ── Stop hero ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StopHero(
              stop: stop,
              stopNumber: stopNumber,
              totalStops: totalStops,
              // A shared/deep link can open this page as the only route.
              onBack: () => context.popOr('/itineraries/$itineraryId'),
              // In either mode: from read mode it claims the trip first.
              onEdit: mayEdit ? () => _openStopForm(context, ref) : null,
              // Wire-reported as the parent itinerary; the stop id rides in
              // the report notes (hiding is itinerary-level).
              onReport: mayEdit
                  ? null
                  : () => showReportContentSheet(
                        context,
                        ref,
                        ReportTarget.stop(itineraryId, stop.id),
                      ),
              // A saved Google Maps link opens straight in Google Maps (no
              // app picker); a coordinate-only stop still offers the full
              // installed-apps sheet.
              onOpenInMaps: stop.mapUrl != null
                  ? () => ref
                      .read(mapsLauncherServiceProvider)
                      .openUrl(stop.mapUrl!)
                  : (stop.lat != null && stop.lng != null
                      ? () => showOpenInMapsSheet(
                            context: context,
                            lat: stop.lat!,
                            lng: stop.lng!,
                            label: stop.placeName,
                          )
                      : null),
            ),
          ),

          // ── Map preview ────────────────────────────────────────────────────
          // Sits under the hero so the map is right beside the place it names.
          // LinkPreviewCard is self-contained (own providers/key/padding) and
          // degrades to an "Opens in Google Maps" row when no embed is possible.
          if (showMapPreview) ...[
            SliverToBoxAdapter(
              child: _SectionLabel(
                  icon: Icons.map_rounded, label: l10n.mapSection),
            ),
            SliverToBoxAdapter(
              child: hasMapLink
                  // Pass stored coords too: on web (no unfurl) they're the
                  // fallback embed query when the saved link carries none.
                  ? LinkPreviewCard(
                      url: stop.mapUrl!, lat: stop.lat, lng: stop.lng)
                  : LinkPreviewCard.coordinates(
                      lat: stop.lat!, lng: stop.lng!, label: stop.placeName),
            ),
          ],

          // ── Stats row: time · cost ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _StopStat(
                    icon: Icons.schedule_rounded,
                    label: l10n.timeLabel,
                    value: stop.formattedDuration(l10n),
                  ),
                  const SizedBox(width: 8),
                  _StopStat(
                    icon: Icons.payments_rounded,
                    label: l10n.costLabel,
                    value: stop.isFree
                        ? l10n.freeLegLabel
                        : stop.cost > 0
                            ? formatMoney(stop.cost, currency)
                            : '—',
                  ),
                ],
              ),
            ),
          ),

          // ── See translation ────────────────────────────────────────────────
          // Above the annotations and notes it covers, so it is seen before
          // the text rather than after scrolling past it. Read mode only, as
          // on the trip page: whoever is editing reads what they are changing.
          if (translatable && !editing)
            SliverToBoxAdapter(
              child: TranslationToggle(
                anchor: translationAnchor,
                members: translationMembers,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              ),
            ),

          // ── Annotations ────────────────────────────────────────────────────
          if (hasAnnotations) ...[
            SliverToBoxAdapter(
              child: _SectionLabel(
                icon: Icons.bookmark_rounded,
                label: '${l10n.annotationsLabel} · ${stop.annotations.length}',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  children: stop.annotations
                      .map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _AnnotationFullRow(
                              annotation: a,
                              translationAnchor: translationAnchor,
                              translate: !editing,
                              onReport: mayEdit
                                  ? null
                                  : () => showReportContentSheet(
                                        context,
                                        ref,
                                        ReportTarget.stopAnnotation(
                                            itineraryId, stop.id, a.id),
                                      ),
                              onLongPressEdit: mayEdit
                                  ? () => _editAnnotation(context, ref, a)
                                  : null,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],

          // ── Transit ────────────────────────────────────────────────────────
          if (hasTransit) ...[
            SliverToBoxAdapter(
              child: _SectionLabel(
                  icon: Icons.alt_route_rounded, label: l10n.transitLabel),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                child: Column(
                  children: [
                    if (inboundSegment != null)
                      _TransitFullRow(
                        segment: inboundSegment!,
                        direction: _TransitDirection.inbound,
                        currency: currency,
                        allStops: allStops,
                        translationAnchor: translationAnchor,
                        translate: !editing,
                        onEditLeg: mayEdit
                            ? (i) => _inEditMode(
                                  context,
                                  ref,
                                  () => LegEditor(
                                    ref: ref,
                                    itineraryId: itineraryId,
                                    segment: inboundSegment!,
                                  ).editLeg(context, i),
                                )
                            : null,
                      ),
                    if (inboundSegment != null && outboundSegment != null)
                      const Divider(height: 1),
                    if (outboundSegment != null)
                      _TransitFullRow(
                        segment: outboundSegment!,
                        direction: _TransitDirection.outbound,
                        currency: currency,
                        allStops: allStops,
                        translationAnchor: translationAnchor,
                        translate: !editing,
                        onEditLeg: mayEdit
                            ? (i) => _inEditMode(
                                  context,
                                  ref,
                                  () => LegEditor(
                                    ref: ref,
                                    itineraryId: itineraryId,
                                    segment: outboundSegment!,
                                  ).editLeg(context, i),
                                )
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
          
          // ── Notes ──────────────────────────────────────────────────────────
          if (hasNotes) ...[
            SliverToBoxAdapter(
              child: _SectionLabel(
                  icon: Icons.description_rounded, label: l10n.notesLabel),
            ),
            SliverToBoxAdapter(
              child: LongPressToEdit(
                // Notes live on the stop itself, so the shortcut is the stop
                // form rather than a dedicated notes editor.
                onEdit: mayEdit ? () => _openStopForm(context, ref) : null,
                child: _SectionCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: TranslatableText(
                      anchor: translationAnchor,
                      contentType: 'stop',
                      contentId: stop.id,
                      field: 'notes',
                      original: stop.notes!,
                      enabled: !editing,
                      builder: (context, notes) =>
                          InertMarkdownBody(data: notes),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────────
class _StopHero extends StatelessWidget {
  final Stop stop;
  final int stopNumber;
  final int totalStops;
  final VoidCallback onBack;
  final VoidCallback? onEdit; // null for anyone who can't edit the trip
  final VoidCallback? onReport; // null for owner/editors — you can't report yourself
  final VoidCallback? onOpenInMaps; // null when the stop has no coordinates

  const _StopHero({
    required this.stop,
    required this.stopNumber,
    required this.totalStops,
    required this.onBack,
    this.onEdit,
    this.onReport,
    this.onOpenInMaps,
  });

  // Prefer the human address; fall back to raw coordinates so a map-picked
  // stop (lat/lng but no address text) still shows its location.
  String? get _locationText {
    if (stop.placeAddress != null && stop.placeAddress!.trim().isNotEmpty) {
      return stop.placeAddress!.trim();
    }
    if (stop.lat != null && stop.lng != null) {
      return '${stop.lat!.toStringAsFixed(5)}, ${stop.lng!.toStringAsFixed(5)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    // Long-press anywhere on the hero is a shortcut to the same stop form the
    // pencil opens; onEdit is already gated on edit rights, so no extra gate.
    return LongPressToEdit(
      onEdit: onEdit,
      child: Container(
      color: nt.mist,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: nt.bark,
              ),
              const Spacer(),
              if (onOpenInMaps != null) ...[
                _OpenInMapsButton(onTap: onOpenInMaps!),
                const SizedBox(width: 8),
              ],
              if (onReport != null) _ReportButton(onTap: onReport!),
              if (onEdit != null) EditPencilButton(onTap: onEdit!, iconSize: 20),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large number badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: nt.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: nt.forest.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$stopNumber',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: nt.forest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!
                          .stopNumberOfTotal(stopNumber, totalStops),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: nt.forest,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // Tapping the name or location also opens the map app;
                    // onTap is null (inert) when the stop has no coordinates.
                    InkWell(
                      onTap: onOpenInMaps,
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.placeName ??
                                AppLocalizations.of(context)!
                                    .stopWithNumber(stopNumber),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: nt.bark,
                              letterSpacing: -0.3,
                              height: 1.1,
                            ),
                          ),
                          if (_locationText != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 13, color: nt.text2),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _locationText!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: nt.text2,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (stop.placeType != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _PlaceTypeChip(placeType: stop.placeType!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Open-in-maps button ──────────────────────────────────────────────────────
// Forest-tinted pill matching the itinerary route button — opens this stop's
// location in an external map app. Not offline-gated: handing off to another
// app doesn't require a connection here (nt.editBlue stays reserved for Edit).
class _OpenInMapsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenInMapsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Tooltip(
      message: AppLocalizations.of(context)!.openInMaps,
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

// ─── Report button ────────────────────────────────────────────────────────────
// Same pill geometry as _OpenInMapsButton but in neutral text tint, so it reads
// as secondary next to the forest-tinted Directions action.
class _ReportButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ReportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Tooltip(
      message: AppLocalizations.of(context)!.reportItineraryTooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: nt.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: nt.border),
            ),
            child: Icon(Icons.flag_outlined, size: 20, color: nt.text2),
          ),
        ),
      ),
    );
  }
}

// ─── Place type chip ──────────────────────────────────────────────────────────
class _PlaceTypeChip extends StatelessWidget {
  final PlaceType placeType;
  const _PlaceTypeChip({required this.placeType});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: placeType.color(nt).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(placeType.icon, size: 14, color: placeType.color(nt)),
          const SizedBox(width: 5),
          Text(
            placeType.label(l10n),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: placeType.color(nt),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stop stat tile ───────────────────────────────────────────────────────────
class _StopStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StopStat(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: nt.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: nt.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: nt.forest),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: nt.text2,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: nt.bark,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Full annotation row (with message body) ──────────────────────────────────
class _AnnotationFullRow extends StatelessWidget {
  final Annotation annotation;

  /// The stop's translation group, which this note's text follows.
  final TranslationAnchor translationAnchor;

  /// False while the trip is in edit mode — whoever edits reads the original.
  final bool translate;

  /// Long-press to report. No visible affordance on purpose — the row has no
  /// menu and a flag glyph on every note would drown the content.
  final VoidCallback? onReport;

  /// Owner's long-press instead opens the editor. Mutually exclusive with
  /// [onReport] — an author never reports their own note.
  final VoidCallback? onLongPressEdit;

  const _AnnotationFullRow({
    required this.annotation,
    required this.translationAnchor,
    this.translate = true,
    this.onReport,
    this.onLongPressEdit,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final t = annotation.type;

    return LongPressToEdit(
      onEdit: onLongPressEdit,
      child: GestureDetector(
      onLongPress: onReport,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: t.bg(nt),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.fg(nt).withValues(alpha: 0.13)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: t.fg(nt).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(t.icon, size: 15, color: t.fg(nt)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.label(AppLocalizations.of(context)!).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.fg(nt),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TranslatableText(
                    anchor: translationAnchor,
                    contentType: 'stop_annotation',
                    contentId: annotation.id,
                    field: 'content',
                    original: annotation.content,
                    enabled: translate,
                    builder: (context, content) => Text(
                      content,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: nt.bark,
                        height: 1.5,
                      ),
                    ),
                  ),
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

// ─── Transit row (in/outbound) ────────────────────────────────────────────────
enum _TransitDirection { inbound, outbound }

class _TransitFullRow extends StatelessWidget {
  final TransitSegment segment;
  final _TransitDirection direction;
  final String currency;
  final List<Stop> allStops;

  /// The stop's translation group, which the legs' thoughts follow.
  final TranslationAnchor translationAnchor;

  /// False while the trip is being edited — whoever edits reads the original.
  final bool translate;

  /// Owner shortcut: long-press a leg row to open its form. Null for viewers.
  final void Function(int legIndex)? onEditLeg;

  const _TransitFullRow({
    required this.segment,
    required this.direction,
    required this.currency,
    required this.allStops,
    required this.translationAnchor,
    required this.translate,
    this.onEditLeg,
  });


  String _stopName(String id) =>
      allStops.firstWhere((s) => s.id == id,
          orElse: () => allStops.first).placeName ??
      '—';

  String _fmtLegCost(double cost, bool isFree, AppLocalizations l10n) {
    if (isFree || cost <= 0) return l10n.freeLegLabel;
    return formatMoney(cost, currency);
  }

  String _totalCost(AppLocalizations l10n) {
    if (segment.totalCost <= 0) return l10n.freeLegLabel;
    return formatMoney(segment.totalCost, currency);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final isInbound = direction == _TransitDirection.inbound;
    final otherName = isInbound
        ? _stopName(segment.fromStopId)
        : _stopName(segment.toStopId);
    final legs = segment.legs;
    final multiLeg = legs.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Direction header ────────────────────────────────────────────
          Row(
            children: [
              Icon(
                isInbound
                    ? Icons.south_east_rounded
                    : Icons.north_east_rounded,
                size: 12,
                color: nt.text3,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isInbound
                      ? l10n.fromStopName(otherName)
                      : l10n.toStopName(otherName),
                  style: TextStyle(
                    fontSize: 11,
                    color: nt.text2,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── One row per leg ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: nt.transitBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: nt.transitBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < legs.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1, color: nt.transitBorder, indent: 12),
                  LongPressToEdit(
                    // The thoughts sit inside it too: a long-press on them
                    // opens the same leg form.
                    onEdit:
                        onEditLeg != null ? () => onEditLeg!(i) : null,
                    child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(
                      children: [
                        // Mode icon badge
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: nt.transitIcon.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(legs[i].mode.icon,
                              size: 16, color: nt.transitIcon),
                        ),
                        const SizedBox(width: 10),
                        // Mode label + optional line
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                legs[i].mode.label(l10n),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: nt.bark,
                                ),
                              ),
                              if (legs[i].line != null &&
                                  legs[i].line!.isNotEmpty)
                                Text(
                                  legs[i].line!,
                                  style: TextStyle(
                                      fontSize: 11, color: nt.text2),
                                ),
                            ],
                          ),
                        ),
                        // Per-leg duration + cost
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (legs[i].durationMin != null &&
                                legs[i].durationMin! > 0)
                              Text(
                                formatDuration(legs[i].durationMin, l10n),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: nt.bark),
                              ),
                            Text(
                              _fmtLegCost(
                                  legs[i].cost, legs[i].isFree, l10n),
                              style: TextStyle(
                                  fontSize: 11, color: nt.text2),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (legs[i].hasNotes)
                      Padding(
                        // Under the mode label: 32 badge + 10 gap.
                        padding: const EdgeInsetsDirectional.only(
                            start: 42, top: 6),
                        child: LegThoughts(
                          leg: legs[i],
                          anchor: translationAnchor,
                          translate: translate,
                        ),
                      ),
                      ],
                    ),
                  ),
                  ),
                ],

                // ── Total row (multi-leg only) ──────────────────────────
                if (multiLeg) ...[
                  Divider(height: 1, color: nt.transitBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                    child: Row(
                      children: [
                        Icon(Icons.summarize_rounded,
                            size: 13, color: nt.transitIcon),
                        const SizedBox(width: 6),
                        Text(
                          l10n.totalLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: nt.transitIcon,
                          ),
                        ),
                        const Spacer(),
                        if (segment.totalDurationMin > 0) ...[
                          Text(
                            formatDuration(segment.totalDurationMin, l10n),
                            style: TextStyle(
                                fontSize: 11, color: nt.transitIcon),
                          ),
                          Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: 5),
                            child: Text('·',
                                style: TextStyle(
                                    fontSize: 11, color: nt.transitIcon)),
                          ),
                        ],
                        Text(
                          _totalCost(l10n),
                          style: TextStyle(
                              fontSize: 11, color: nt.transitIcon),
                        ),
                      ],
                    ),
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


// ─── Shared section widgets ───────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: nt.text2),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: nt.text2,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

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
      child: child,
    );
  }
}
