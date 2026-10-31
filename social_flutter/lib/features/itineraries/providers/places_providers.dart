// providers/places_providers.dart — Riverpod state for Google places.
//
// placesConfigProvider — whether Google search and Google maps are on. Off
//   signed out, or when it cannot be read: no Google row, no Google map.
//   Keep-alive and listed in auth_provider's _userScopedProviders.
// googlePlaceSearchProvider — the stop form's Google suggestions. autoDispose:
//   they belong to the form that asked and go with it; Google's answer is
//   never kept beyond the choosing.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/domain/search_bias.dart';

final placesConfigProvider = FutureProvider<PlacesConfig>((ref) async {
  // Both endpoints need a session; signed out, asking would only earn a 401.
  if (!await ref.watch(hasSessionProvider.future)) return PlacesConfig.disabled;
  try {
    return await ref.read(placesRepositoryProvider).getConfig();
  } catch (_) {
    if (!ref.mounted) return PlacesConfig.disabled;
    // Off for now, asked again on the next return to the foreground or the
    // network — the same recovery as translationConfigProvider.
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(lifecycle.dispose);
    ref.listen(isOnlineProvider, (previous, next) {
      if (previous?.value == false && next.value == true) ref.invalidateSelf();
    });
    return PlacesConfig.disabled;
  }
});

/// Google's suggestions while the form is on Google. Every request is billed,
/// so typing asks only after [typingPause] and from [minimumLength]
/// characters, and a newer question cancels the one still in flight.
class GooglePlaceSearchNotifier extends AsyncNotifier<List<GoogleSuggestion>> {
  static const typingPause = Duration(milliseconds: 500);
  static const minimumLength = 3;

  // Bumped by every question and every clear: a late answer to an older
  // question is dropped instead of replacing a newer one.
  int _epoch = 0;
  Timer? _pause;
  CancelToken? _inFlight;

  @override
  Future<List<GoogleSuggestion>> build() async {
    ref.onDispose(() {
      _pause?.cancel();
      _inFlight?.cancel();
    });
    return const [];
  }

  /// Asks now — the switch to Google (the tap, or an empty OSM answer).
  Future<void> searchNow(String text, {required String language, BiasPoint? bias}) async {
    _pause?.cancel();
    final input = text.trim();
    final epoch = ++_epoch;
    _inFlight?.cancel();
    if (input.length < minimumLength) {
      state = const AsyncData([]);
      return;
    }
    final token = _inFlight = CancelToken();
    state = const AsyncLoading();
    try {
      final suggestions = await ref.read(placesRepositoryProvider).autocomplete(
            input: input,
            language: language,
            bias: bias,
            cancelToken: token,
          );
      if (!ref.mounted || epoch != _epoch) return;
      state = AsyncData(suggestions);
    } catch (error, stackTrace) {
      if (!ref.mounted || epoch != _epoch) return;
      if (error is DioException && error.type == DioExceptionType.cancel) return;
      state = AsyncError(error, stackTrace);
    }
  }

  /// Typing while on Google: asks after a pause, never per keystroke.
  void typed(String text, {required String language, BiasPoint? bias}) {
    _pause?.cancel();
    if (text.trim().length < minimumLength) {
      clear();
      return;
    }
    _pause = Timer(
      typingPause,
      () => searchNow(text, language: language, bias: bias),
    );
  }

  void clear() {
    _epoch++;
    _pause?.cancel();
    _inFlight?.cancel();
    state = const AsyncData([]);
  }
}

final googlePlaceSearchProvider = AsyncNotifierProvider.autoDispose<
    GooglePlaceSearchNotifier, List<GoogleSuggestion>>(
  GooglePlaceSearchNotifier.new,
);
