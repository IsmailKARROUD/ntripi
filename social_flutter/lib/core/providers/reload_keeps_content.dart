// core/providers/reload_keeps_content.dart — the one way a notifier fetches
// again what a screen already shows: pull-to-refresh, Retry, and the reloads
// the app starts itself.
//
// Riverpod 3 merges the previous value into every AsyncLoading and AsyncError
// a notifier writes, and AsyncValue.when() still renders those as the loader
// and the error view unless told otherwise. A reload written as
// `state = const AsyncLoading()` therefore unmounted the content until the new
// copy arrived — every opened "view more" with it — and a failed one replaced
// a copy that had been fine a second earlier with the error view. The two
// hand-written guards that kept content during the load still got the failure
// wrong, so the rules live here and nowhere else;
// test/reload_keeps_content_guard_test.dart keeps it that way.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';

/// A reload that failed and left the content on screen as it was. The screen
/// that started the reload shows it (`reportReloads`, in
/// shared/widgets/reload_report.dart); a reload the app started itself drops it.
class ReloadFailure {
  const ReloadFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// Gives an [AsyncNotifier] [reloadKeepingContent].
mixin ReloadKeepsContent<T> on AsyncNotifier<T> {
  /// Fetches the state again with [fetch], keeping what is on screen:
  ///
  /// - **Nothing on screen** (no value yet, or the error view): the loader,
  ///   then the answer or the error — a first load, and Retry, as ever.
  /// - **Content on screen**: it stays mounted throughout. An answer replaces
  ///   it in place, after [onApply] (paging bookkeeping) — unless something
  ///   else wrote the state while the reload was in flight: a save, a
  ///   dismissal or a removal answered after this GET was sent, so the GET may
  ///   predate it, and the newer state stands. A refusal ([refusesContent]:
  ///   gone, or no longer this account's to see) replaces the content with the
  ///   error. Any other failure leaves the content alone and is returned.
  ///
  /// Never throws: its result is what a screen reports.
  @protected
  Future<ReloadFailure?> reloadKeepingContent(
    Future<T> Function() fetch, {
    void Function(T value)? onApply,
  }) async {
    final started = state;
    final hadContent = _showsContent(started);
    if (!hadContent) state = AsyncLoading<T>();
    try {
      final value = await fetch();
      if (!ref.mounted) return null; // disposed mid-request (logout)
      if (hadContent && !identical(state, started)) return null;
      onApply?.call(value);
      state = AsyncData(value);
      return null;
    } catch (error, stackTrace) {
      if (!ref.mounted) return null; // disposed mid-request (logout)
      // A build() can land first and put content back; that stays like any.
      if (refusesContent(error) || !_showsContent(state)) {
        state = AsyncError(error, stackTrace);
        return null;
      }
      return ReloadFailure(error, stackTrace);
    }
  }
}

/// What AsyncValue.when() draws as data: a value, and no error over it.
bool _showsContent(AsyncValue<Object?> value) =>
    value.hasValue && !value.hasError;
