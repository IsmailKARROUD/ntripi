// core/api/api_error_codes.dart — maps backend ApiError `code` values to
// localized messages. Returns null for unknown codes so the caller can fall
// back to the server-provided `detail` string, then a generic message.

import 'package:dio/dio.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

String? localizedApiError(String code, AppLocalizations l10n) {
  return switch (code) {
      'not_authenticated' => l10n.apiErrorNotAuthenticated,
      'account_deactivated' => l10n.apiErrorAccountDeactivated,
      'email_unverified' => l10n.apiErrorEmailUnverified,
      'itinerary_not_found' => l10n.apiErrorItineraryNotFound,
      'itinerary_not_owner' => l10n.apiErrorItineraryNotOwner,
      'if_match_required' => l10n.apiErrorIfMatchRequired,
      'itinerary_stale' => l10n.apiErrorItineraryStale,
      'waitlist_contact_required' => l10n.apiErrorWaitlistContactRequired,
      'google_token_invalid' => l10n.apiErrorGoogleTokenInvalid,
      'invalid_grant' => l10n.apiErrorInvalidGrant,
      'stop_not_found' => l10n.apiErrorStopNotFound,
      'track_not_found' => l10n.apiErrorTrackNotFound,
      'segment_not_found' => l10n.apiErrorSegmentNotFound,
      'leg_not_found' => l10n.apiErrorLegNotFound,
      'itinerary_access_denied' => l10n.apiErrorItineraryAccessDenied,
      'allowlist_restricted_only' => l10n.apiErrorAllowlistRestrictedOnly,
      'user_not_found' => l10n.apiErrorUserNotFound,
      'allowlist_user_exists' => l10n.apiErrorAllowlistUserExists,
      'allowlist_user_not_found' => l10n.apiErrorAllowlistUserNotFound,
      'rank_collision' => l10n.apiErrorRankCollision,
      'annotation_not_found' => l10n.apiErrorAnnotationNotFound,
      'rating_not_found' => l10n.apiErrorRatingNotFound,
      'segment_already_exists' => l10n.apiErrorSegmentAlreadyExists,
      'incorrect_password' => l10n.apiErrorIncorrectPassword,
      'login_invalid' => l10n.apiErrorLoginInvalid,
      'cannot_follow_self' => l10n.apiErrorCannotFollowSelf,
      'not_following' => l10n.apiErrorNotFollowing,
      'follow_request_not_found' => l10n.apiErrorFollowRequestNotFound,
      'follow_request_already_accepted' => l10n.apiErrorFollowRequestAlreadyAccepted,
      'cannot_reject_request' => l10n.apiErrorCannotRejectRequest,
      'account_private' => l10n.apiErrorAccountPrivate,
      'tos_required' => l10n.apiErrorTosRequired,
      'username_taken' => l10n.apiErrorUsernameTaken,
      'email_taken' => l10n.apiErrorEmailTaken,
      'report_own_content' => l10n.apiErrorReportOwnContent,
      'report_rate_limited' => l10n.apiErrorReportRateLimited,
      'image_moderation_rejected' => l10n.apiErrorImageModerationRejected,
      'appeal_already_pending' => l10n.apiErrorAppealPending,
      'appeal_cooldown' => l10n.apiErrorAppealCooldown,
      'appeal_target_not_found' => l10n.apiErrorAppealTargetNotFound,
      'text_moderation_rejected' => l10n.apiErrorTextModerationRejected,
      'cannot_block_self' => l10n.apiErrorCannotBlockSelf,
      'itinerary_locked' => l10n.apiErrorItineraryLocked,
      'edit_lock_required' => l10n.apiErrorEditLockRequired,
      'edit_lock_lost' => l10n.apiErrorEditLockLost,
      'editor_cannot_view' => l10n.apiErrorEditorCannotView,
      'editor_exists' => l10n.apiErrorEditorExists,
      'editor_not_found' => l10n.apiErrorEditorNotFound,
      'editor_is_owner' => l10n.apiErrorEditorIsOwner,
      _ => null,
    };
}

/// Plain-language reason for a moderation rejection.
///
/// The backend sends raw classifier category ids (`sexual/minors`,
/// `illicit/violent`). Showing those to the person who just wrote a sentence
/// would be both baffling and needlessly clinical, so each maps to a phrase.
/// Unknown ids — a newer backend, a new category — fall back to the generic
/// message rather than leaking an internal identifier.
String moderationRejectionMessage(
  List<String> categories,
  AppLocalizations l10n,
) {
  for (final category in categories) {
    final phrase = switch (category) {
      'sexual/minors' => l10n.moderationCategoryMinors,
      'sexual' => l10n.moderationCategorySexual,
      'hate' || 'hate/threatening' => l10n.moderationCategoryHate,
      'harassment' || 'harassment/threatening' => l10n.moderationCategoryHarassment,
      'violence' || 'violence/graphic' => l10n.moderationCategoryViolence,
      'self-harm' ||
      'self-harm/intent' ||
      'self-harm/instructions' =>
        l10n.moderationCategorySelfHarm,
      'illicit' || 'illicit/violent' => l10n.moderationCategoryIllicit,
      _ => null,
    };
    if (phrase != null) return l10n.moderationRejectedBecause(phrase);
  }
  return l10n.apiErrorTextModerationRejected;
}

/// The `categories` list from a moderation rejection body, or empty.
List<String> moderationCategories(dynamic error) {
  final data = _responseData(error);
  final raw = data is Map ? data['categories'] : null;
  if (raw is List) return raw.whereType<String>().toList();
  return const [];
}

/// True when the server said the thing is not there — 404 or 410.
///
/// Blocked, banned and deleted accounts all answer 404 with the same body on
/// purpose (see `_require_not_blocked` in the backend), so a caller can only
/// distinguish "gone" from "broken", never *why* it is gone. Retrying a gone
/// resource can never succeed, which is what makes this worth branching on.
bool isGoneError(Object? e) {
  if (e is! DioException) return false;
  final status = e.response?.statusCode;
  return status == 404 || status == 410;
}

dynamic _responseData(dynamic error) {
  try {
    return (error as dynamic).response?.data;
  } catch (_) {
    return null;
  }
}
