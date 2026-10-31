// presentation/widgets/place_search_box.dart — the stop form's place search.
//
// OpenStreetMap first, always. An OSM search runs when the user submits it —
// the keyboard's Search key or the arrow — never as they type: Nominatim's
// usage policy forbids search-as-you-type and caps the whole app at one
// request a second.
//
// In the Google Maps segment ([googleFallback]) Google Places is the fallback:
// a "Search on Google Maps" row under the OSM results, and a switch of its own
// when a submitted OSM search finds nothing. Once on Google the suggestions
// follow the typing (GooglePlaceSearchNotifier: a pause, 3+ characters, each
// request billed); clearing the field goes back to OSM. Each list carries its
// source's attribution, and Google's never sits on an OSM map — the form shows
// Google places only through Google's own embed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/domain/search_bias.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';

class PlaceSearchBox extends ConsumerStatefulWidget {
  final TextEditingController controller;

  /// The Google Maps segment: offer Google when OSM does not have the place.
  final bool googleFallback;

  /// The app language, for both searches' results.
  final String language;

  /// Where to look first (search_bias.dart), read when a search is sent.
  final BiasPoint? Function() bias;

  final ValueChanged<PlaceSuggestion> onOsmPick;

  /// [searchText] is what the user typed — the only text a Google place keeps.
  final void Function(GoogleSuggestion suggestion, String searchText)
      onGooglePick;

  const PlaceSearchBox({
    super.key,
    required this.controller,
    required this.googleFallback,
    required this.language,
    required this.bias,
    required this.onOsmPick,
    required this.onGooglePick,
  });

  @override
  ConsumerState<PlaceSearchBox> createState() => _PlaceSearchBoxState();
}

class _PlaceSearchBoxState extends ConsumerState<PlaceSearchBox> {
  bool _onGoogle = false;

  // The OSM query last submitted: "no results" and the switch to Google are
  // about it, not about text typed since.
  String _submitted = '';

  String get _text => widget.controller.text.trim();

  LatLng? _near() {
    final bias = widget.bias();
    return bias == null ? null : LatLng(bias.lat, bias.lng);
  }

  void _submit() {
    if (_text.isEmpty) return;
    if (_onGoogle) {
      ref.read(googlePlaceSearchProvider.notifier).searchNow(_text,
          language: widget.language, bias: widget.bias());
      return;
    }
    setState(() => _submitted = _text);
    ref.read(placeSearchProvider.notifier).search(_text, near: _near());
  }

  void _switchToGoogle() {
    setState(() => _onGoogle = true);
    ref.read(googlePlaceSearchProvider.notifier).searchNow(_text,
        language: widget.language, bias: widget.bias());
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty) {
      _reset();
      return;
    }
    if (_onGoogle) {
      ref.read(googlePlaceSearchProvider.notifier).typed(value,
          language: widget.language, bias: widget.bias());
    }
    setState(() {}); // the clear and search buttons follow the text
  }

  void _reset() {
    setState(() {
      _onGoogle = false;
      _submitted = '';
    });
    ref.read(placeSearchProvider.notifier).clear();
    if (widget.googleFallback) {
      ref.read(googlePlaceSearchProvider.notifier).clear();
    }
  }

  void _clear() {
    widget.controller.clear();
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final googleEnabled = widget.googleFallback &&
        (ref.watch(placesConfigProvider).value?.googleSearch ?? false);
    // autoDispose: watched for the whole Google segment, so a question asked
    // in the same frame as the switch is not disposed before it is sent.
    if (googleEnabled) ref.watch(googlePlaceSearchProvider);

    // A submitted OSM search that comes back empty asks Google by itself.
    ref.listen(placeSearchProvider, (_, next) {
      if (!googleEnabled || _onGoogle || _submitted.isEmpty) return;
      if (next.isLoading || next.hasError) return;
      if ((next.value ?? const []).isEmpty && _submitted == _text) {
        _switchToGoogle();
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: l10n.searchPlaceHintText,
            filled: true,
            fillColor: nt.surface,
            prefixIcon: Icon(Icons.search_rounded, color: nt.forest),
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: l10n.mapLinkClear,
                        onPressed: _clear,
                      ),
                      IconButton(
                        icon: Icon(Icons.arrow_forward_rounded,
                            size: 20, color: nt.forest),
                        tooltip: l10n.placeSearchButton,
                        onPressed: _submit,
                      ),
                    ],
                  ),
            border: _border(nt.border),
            enabledBorder: _border(nt.border),
            focusedBorder: _border(nt.forest, width: 1.5),
          ),
        ),
        if (_onGoogle)
          _googleResults(nt, l10n)
        else
          _osmResults(nt, l10n, googleEnabled),
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(NtripiRadius.field),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _osmResults(
      NtripiColors nt, AppLocalizations l10n, bool googleEnabled) {
    final async = ref.watch(placeSearchProvider);
    final askGoogle = googleEnabled
        ? _ActionRow(
            icon: Icons.travel_explore_rounded,
            label: l10n.searchOnGoogleMaps,
            onTap: _switchToGoogle,
          )
        : null;
    if (async.isLoading) return const _Progress();
    if (async.hasError) return askGoogle ?? const SizedBox.shrink();
    final suggestions = async.value ?? const <PlaceSuggestion>[];
    if (suggestions.isEmpty) {
      final searchedThis = _submitted.isNotEmpty && _submitted == _text;
      if (!searchedThis) return const SizedBox.shrink();
      // With Google on, the listener above is already switching to it.
      if (googleEnabled) return const _Progress();
      return _Notice(text: l10n.placeSearchNoResults);
    }
    return _ResultsCard(
      attribution: '© OpenStreetMap contributors',
      footer: askGoogle,
      tiles: [
        for (final suggestion in suggestions)
          _ResultTile(
            title: suggestion.displayName,
            // Full address, unabbreviated — it's what disambiguates
            // same-named places.
            subtitle: suggestion.address,
            onTap: () => widget.onOsmPick(suggestion),
          ),
      ],
    );
  }

  Widget _googleResults(NtripiColors nt, AppLocalizations l10n) {
    final async = ref.watch(googlePlaceSearchProvider);
    final suggestions = async.value ?? const <GoogleSuggestion>[];
    // While the next answer is on its way the last one stays, under a bar:
    // typing must not blank the list between pauses.
    if (async.isLoading && suggestions.isEmpty) return const _Progress();
    if (async.hasError && !async.isLoading) {
      return _Notice(text: extractErrorMessage(async.error, l10n), error: true);
    }
    if (suggestions.isEmpty) {
      return _text.length < GooglePlaceSearchNotifier.minimumLength
          ? const SizedBox.shrink()
          : _Notice(text: l10n.mapSearchNoResults);
    }
    final card = _ResultsCard(
      // Google's policy for predictions shown without a Google map.
      attribution: 'Google Maps',
      tiles: [
        for (final suggestion in suggestions)
          _ResultTile(
            title: suggestion.mainText,
            subtitle: suggestion.secondaryText,
            onTap: () => widget.onGooglePick(suggestion, _text),
          ),
      ],
    );
    return async.isLoading
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const _Progress(), card],
          )
        : card;
  }
}

class _ResultsCard extends StatelessWidget {
  final List<Widget> tiles;
  final String attribution;
  final Widget? footer;

  const _ResultsCard(
      {required this.tiles, required this.attribution, this.footer});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    // Tiles live in a Material (not a color-decorated Container) so ListTile
    // background/ink paint on it — a colored intermediate box would hide them.
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: nt.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NtripiRadius.tile),
          side: BorderSide(color: nt.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 52),
              tiles[i],
            ],
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 8),
              child: Text(
                attribution,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, color: nt.text2),
              ),
            ),
            if (footer != null) ...[
              Divider(height: 1, color: nt.border),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ResultTile({required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: nt.sand,
          borderRadius: BorderRadius.circular(NtripiRadius.icon),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.location_on_rounded, size: 18, color: nt.forest),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: nt.bark,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(fontSize: 11, color: nt.text2)),
      trailing: Icon(Icons.add_rounded, size: 20, color: nt.forest),
      onTap: onTap,
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: nt.forest),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: nt.forest,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: nt.forest),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool error;

  const _Notice({required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: error ? nt.danger : nt.text2),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
}
