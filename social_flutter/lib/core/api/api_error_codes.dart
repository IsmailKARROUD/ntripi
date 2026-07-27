// core/api/api_error_codes.dart — maps backend ApiError `code` values to
// localized messages. Returns null for unknown codes so the caller can fall
// back to the server-provided `detail` string, then a generic message.

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
      _ => null,
    };
}
