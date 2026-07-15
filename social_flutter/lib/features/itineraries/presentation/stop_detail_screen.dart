// presentation/stop_detail_screen.dart — Read-only detail view for one stop.
//
// Shows the stop's hero header, time/cost/rating stats, notes, annotations
// (with full message bodies), inbound/outbound transit, and photos grid.
// Navigation: tapping a stop row in the detail view pushes this screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/open_in_maps_sheet.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/utils/duration_format.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class StopDetailScreen extends ConsumerWidget {
  final String itineraryId;
  final String stopId;

  const StopDetailScreen({
    super.key,
    required this.itineraryId,
    required this.stopId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(itineraryId));

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

        return _StopDetailView(
          stop: stop,
          stopNumber: stopNumber,
          totalStops: totalStops,
          currency: itinerary.currency,
          itineraryId: itineraryId,
          inboundSegment: inbound,
          outboundSegment: outbound,
          allStops: itinerary.stops,
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
  final TransitSegment? inboundSegment;
  final TransitSegment? outboundSegment;
  final List<Stop> allStops;

  const _StopDetailView({
    required this.stop,
    required this.stopNumber,
    required this.totalStops,
    required this.currency,
    required this.itineraryId,
    this.inboundSegment,
    this.outboundSegment,
    required this.allStops,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final hasNotes = stop.notes != null && stop.notes!.trim().isNotEmpty;
    final hasAnnotations = stop.annotations.isNotEmpty;
    final hasTransit = inboundSegment != null || outboundSegment != null;

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
              onBack: () => context.pop(),
              onEdit: () => context.push(
                '/itineraries/$itineraryId/stops/${stop.id}/edit',
              ),
              onOpenInMaps: stop.lat != null && stop.lng != null
                  ? () => showOpenInMapsSheet(
                        context: context,
                        lat: stop.lat!,
                        lng: stop.lng!,
                        label: stop.placeName,
                      )
                  : null,
            ),
          ),

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
                            child: _AnnotationFullRow(annotation: a),
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
                      ),
                    if (inboundSegment != null && outboundSegment != null)
                      const Divider(height: 1),
                    if (outboundSegment != null)
                      _TransitFullRow(
                        segment: outboundSegment!,
                        direction: _TransitDirection.outbound,
                        currency: currency,
                        allStops: allStops,
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
              child: _SectionCard(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: InertMarkdownBody(data: stop.notes!),
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
  final VoidCallback onEdit;
  final VoidCallback? onOpenInMaps; // null when the stop has no coordinates

  const _StopHero({
    required this.stop,
    required this.stopNumber,
    required this.totalStops,
    required this.onBack,
    required this.onEdit,
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
    return Container(
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
              EditPencilButton(onTap: onEdit, iconSize: 20),
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
  const _AnnotationFullRow({required this.annotation});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final t = annotation.type;

    return Container(
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
                Text(
                  annotation.content,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: nt.bark,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
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

  const _TransitFullRow({
    required this.segment,
    required this.direction,
    required this.currency,
    required this.allStops,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
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
