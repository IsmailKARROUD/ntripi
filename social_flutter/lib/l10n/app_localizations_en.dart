// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get required => 'Required';

  @override
  String get retry => 'Retry';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get seeAll => 'See all';

  @override
  String get back => 'Back';

  @override
  String get navSearch => 'Search';

  @override
  String get navProfile => 'Profile';

  @override
  String get navItineraries => 'Itineraries';

  @override
  String get navFeed => 'Feed';

  @override
  String get feedComingSoon => 'Feed coming soon!';

  @override
  String get offlineBanner =>
      'You\'re Offline! Some features may be unavailable.';

  @override
  String get downloadBanner =>
      'For a better experience, download the Ntripi app.';

  @override
  String get downloadBannerButton => 'Download';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to continue your journey';

  @override
  String get loginEmailLabel => 'Email or username';

  @override
  String get loginEmailHelp =>
      'Sign in with the email you registered with, or your @username handle.';

  @override
  String get loginEmailHint => 'you@example.com or @username';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHelp =>
      'Your account password. Tap the eye icon to show or hide it.';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get loginNoAccount => 'Don\'t have an account? ';

  @override
  String get loginSignUp => 'Sign up';

  @override
  String get loginOrContinueWith => 'or continue with';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerSubtitle => 'Join thousands of explorers sharing routes';

  @override
  String get registerDisplayName => 'Display Name';

  @override
  String get registerDisplayNameHelp =>
      'How your name appears to others. Up to 50 characters, any language and emoji. Falls back to @username if blank.';

  @override
  String get registerDisplayNameHint => 'Your name';

  @override
  String get registerUsername => 'Username *';

  @override
  String get registerUsernameHelp =>
      'Your unique @handle. Lowercase letters, digits, and underscores only. This cannot be changed later.';

  @override
  String get registerUsernameHint => 'yourhandle';

  @override
  String get registerEmail => 'Email *';

  @override
  String get registerEmailHelp =>
      'Used to sign in and recover your account. We never display it publicly.';

  @override
  String get registerEmailHint => 'you@example.com';

  @override
  String get registerEmailRequired => 'Email is required.';

  @override
  String get registerEmailInvalid => 'Please enter a valid email.';

  @override
  String get registerPassword => 'Password *';

  @override
  String get registerPasswordHelp =>
      'At least 8 characters with at least one digit.';

  @override
  String get registerPasswordHint => 'Min. 8 characters';

  @override
  String get registerPasswordRequired => 'Password is required.';

  @override
  String get registerPasswordTooShort => 'Must be at least 8 characters.';

  @override
  String get registerPasswordNoDigit => 'Must contain at least one digit.';

  @override
  String get registerConfirmPassword => 'Confirm Password *';

  @override
  String get registerConfirmPasswordHelp =>
      'Type your password again to make sure it matches.';

  @override
  String get registerConfirmRequired => 'Please confirm your password.';

  @override
  String get registerConfirmMismatch => 'Passwords do not match.';

  @override
  String get registerTosAgree => 'I agree to the ';

  @override
  String get registerTos => 'Terms of Service';

  @override
  String get registerTosAnd => ' and ';

  @override
  String get registerPrivacyPolicy => 'Privacy Policy';

  @override
  String get registerTosHelp =>
      'You must agree to the Terms of Service and Privacy Policy to create an account. Tap the underlined links to read them.';

  @override
  String get registerTosRequired => 'You must accept the Terms of Service.';

  @override
  String get registerTosTitle => 'Terms of Service';

  @override
  String get registerTosLoading => 'Loading…';

  @override
  String get registerCreateAccount => 'Create Account';

  @override
  String get registerAlreadyHaveAccount => 'Already have an account? ';

  @override
  String get registerSignIn => 'Sign in';

  @override
  String get followers => 'Followers';

  @override
  String get following => 'Following';

  @override
  String get latestTrip => 'LATEST TRIP';

  @override
  String get whereIveBeen => 'WHERE I\'VE BEEN';

  @override
  String get noStopsYet => 'No stops yet';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '$count stop',
    );
    return '$_temp0';
  }

  @override
  String get expand => 'Expand';

  @override
  String followRequestsBannerTitle(int count) {
    return 'Follow Requests ($count)';
  }

  @override
  String get tapToReview => 'Tap to review';

  @override
  String get editProfileTooltip => 'Edit profile';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get shareProfileTooltip => 'Share profile';

  @override
  String get couldNotLoadItineraries => 'Could not load itineraries.';

  @override
  String get editProfileTitle => 'Edit profile';

  @override
  String get uploadPhoto => 'Upload photo';

  @override
  String get identitySection => 'Identity';

  @override
  String get displayNameLabel => 'Display name';

  @override
  String get usernameLabel => 'Username';

  @override
  String get bioLabel => 'BIO';

  @override
  String get bioHelpMessage =>
      'A short description. Supports **bold** markdown and emoji.';

  @override
  String get avatarUrlLabel => 'Avatar URL';

  @override
  String get travelIdentitySection => 'Travel identity';

  @override
  String get passportLabel => 'Passport';

  @override
  String get livesInLabel => 'Lives in';

  @override
  String get languagesLabel => 'Languages';

  @override
  String get privacySection => 'Privacy';

  @override
  String get privateAccountLabel => 'Private account';

  @override
  String get privateAccountSubtitle =>
      'People must request to follow you to see your itineraries.';

  @override
  String get switchToPublicTitle => 'Switch to public?';

  @override
  String switchToPublicMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You have $count pending follow requests. Switching to public will automatically accept all of them. Continue?',
      one:
          'You have 1 pending follow request. Switching to public will automatically accept it. Continue?',
    );
    return '$_temp0';
  }

  @override
  String get switchToPublicButton => 'Switch to public';

  @override
  String get planFirstJourney => 'Plan your first journey';

  @override
  String get planFirstJourneyHint =>
      'Add stops, transit segments and notes. Share it with friends or keep it private.';

  @override
  String get createItinerary => 'Create itinerary';

  @override
  String get needInspiration => 'Need inspiration?';

  @override
  String get browseForIdeas => 'Browse your itineraries for ideas.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsOn => 'On';

  @override
  String get settingsNotificationsOff => 'Off';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsHelpCenter => 'Help center';

  @override
  String get settingsAbout => 'About Ntripi';

  @override
  String get settingsTerms => 'Terms & Privacy';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get logoutConfirmTitle => 'Log out';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to log out?';

  @override
  String get logoutConfirmButton => 'Log out';

  @override
  String get languagePickerTitle => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get followRequestsTitle => 'Follow Requests';

  @override
  String get noRequests => 'No pending requests';

  @override
  String requestsCountLabel(int count) {
    return 'Requests · $count';
  }

  @override
  String get acceptButton => 'Accept';

  @override
  String get rejectButton => 'Reject';

  @override
  String followersTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Followers',
      zero: 'Followers',
    );
    return '$_temp0';
  }

  @override
  String followingTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Following',
      zero: 'Following',
    );
    return '$_temp0';
  }

  @override
  String followRequestsSectionLabel(int count) {
    return 'Follow requests · $count';
  }

  @override
  String get allFollowersSection => 'All followers';

  @override
  String get noFollowersYet => 'No followers yet.';

  @override
  String get notFollowingAnyone => 'Not following anyone yet.';

  @override
  String get peopleYouFollow => 'People you follow';

  @override
  String get confirmButton => 'Confirm';

  @override
  String get searchPeoplePlaceholder => 'Search people…';

  @override
  String get searchForPeople => 'Search for people to follow';

  @override
  String get noUsersFound => 'No users found.';

  @override
  String searchResultsCount(int count) {
    return 'Results · $count';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count followers',
      one: '$count follower',
    );
    return '$_temp0';
  }

  @override
  String get searchUsersHelp =>
      'Find people by their @username or by their display name. Tap a result to view their profile.';

  @override
  String get myItineraries => 'My Itineraries';

  @override
  String get noItinerariesYet => 'No itineraries yet.';

  @override
  String get tapToCreateFirst => 'Tap + to create your first trip.';

  @override
  String get deleteItineraryTitle => 'Delete this itinerary?';

  @override
  String get deleteItineraryMessage =>
      'All stops, annotations, segments, ratings, and shared links will be permanently destroyed. This cannot be undone.';

  @override
  String get deleteItineraryButton => 'Delete itinerary';

  @override
  String get newItinerary => 'New Itinerary';

  @override
  String get editItinerary => 'Edit Itinerary';

  @override
  String get coverImageLabel => 'Cover image';

  @override
  String get coverImageHelp =>
      'A 1200×630 image shown on the itinerary card and link previews. Drag inside the crop box to reposition.';

  @override
  String get itineraryTitleLabel => 'Title *';

  @override
  String get itineraryTitleHelp =>
      'A short, clear name for this trip. Shown on the itinerary card and share previews.';

  @override
  String get itineraryTitleRequired => 'Title is required';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get descriptionHelp =>
      'Optional. A summary of the trip. Use the toolbar to make text bold or italic, add headings, and create bullet or numbered lists. Switch to the Preview tab to see how it will look to readers.';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get currencyHelp =>
      'Default currency for all stop costs and transport costs in this itinerary.';

  @override
  String get visibilityLabel => 'Visibility';

  @override
  String get visibilityHelp =>
      'Public: anyone can view. Followers: only people who follow you. Restricted: only the users you allowlist below. Only me: private to you.';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityFollowers => 'Followers';

  @override
  String get visibilityRestricted => 'Restricted';

  @override
  String get visibilityOnlyMe => 'Only me';

  @override
  String get imageSaveButUploadFailed =>
      'Itinerary saved, but image upload failed. Try again from the edit screen.';

  @override
  String get deleteItineraryFormTitle => 'Delete itinerary';

  @override
  String deleteItineraryFormMessage(String title) {
    return 'This will permanently delete \"$title\" and all its stops. Type the title to confirm.';
  }

  @override
  String get followButton => 'Follow';

  @override
  String get followingButton => 'Following';

  @override
  String get requestedButton => 'Requested';

  @override
  String unfollowedSnackbar(String username) {
    return 'Unfollowed @$username';
  }

  @override
  String get cancelRequestTitle => 'Cancel request?';

  @override
  String cancelRequestMessage(String username) {
    return 'Cancel your follow request to @$username?';
  }

  @override
  String get cancelRequestConfirm => 'Cancel request';

  @override
  String get cancelRequestKeep => 'Keep';

  @override
  String get undoButton => 'UNDO';

  @override
  String couldNotUndo(String error) {
    return 'Could not undo: $error';
  }

  @override
  String get loadingLabel => 'Loading…';

  @override
  String get usernameRequired => 'Username is required';

  @override
  String get usernameTooShort => 'Username must be at least 4 characters';

  @override
  String get usernameTooLong => 'Username cannot exceed 30 characters';

  @override
  String get usernameInvalidFormat =>
      'Letters, numbers, periods and underscores only. Must start with a letter, end with a letter or number.';

  @override
  String get usernameConsecutiveSpecial =>
      'Cannot have consecutive periods or underscores';

  @override
  String get displayNameTooLong => 'Display name cannot exceed 50 characters';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get speaksLabel => 'Speaks';

  @override
  String get removeButton => 'Remove';

  @override
  String get doneTooltip => 'Done';

  @override
  String get addButton => 'Add';

  @override
  String get deleteButton => 'Delete';

  @override
  String get deleteAccountTitle => 'Delete Account';

  @override
  String get deleteAccountConfirmTitle => 'Delete your account?';

  @override
  String get deleteAccountConfirmMessage =>
      'Your account, itineraries, follows, and ratings will be anonymized or deleted per our privacy policy. You will be signed out immediately. This cannot be undone.';

  @override
  String get deleteAccountRequiredText => 'DELETE MY ACCOUNT';

  @override
  String get deleteAccountConfirmLabel => 'Delete my account';

  @override
  String get deleteAccountPasswordError =>
      'Incorrect password. Please try again.';

  @override
  String get deleteAccountGenericError =>
      'Something went wrong. Please try again.';

  @override
  String get deleteAccountCannotUndo => 'This cannot be undone';

  @override
  String get deleteAccountWillRemove =>
      'Deleting your account will permanently remove:';

  @override
  String get deleteAccountBullet1 => 'Your profile and all personal data';

  @override
  String get deleteAccountBullet2 => 'All your itineraries and stops';

  @override
  String get deleteAccountBullet3 => 'Your follow relationships';

  @override
  String get deleteAccountNote =>
      'Ratings you gave to other itineraries will be kept anonymously as community data.';

  @override
  String get deleteAccountEnterPassword => 'Enter your password to confirm';

  @override
  String get deleteAccountPasswordLabel => 'Password';

  @override
  String get deleteAccountPasswordHelpTitle => 'Confirm password';

  @override
  String get deleteAccountPasswordHelpMessage =>
      'Re-enter your password to confirm deletion. Account deletion is permanent and cannot be undone.';

  @override
  String get deleteAccountButton => 'Delete My Account';

  @override
  String get deleteAnnotationTitle => 'Delete annotation?';

  @override
  String get deleteAnnotationMessage =>
      'This will permanently remove this annotation from the itinerary.';

  @override
  String get deleteAnnotationStopMessage =>
      'This annotation will be permanently removed.';

  @override
  String get removeTransitTitle => 'Remove transit between stops?';

  @override
  String get removeTransitMessage =>
      'The connection between these two stops will be cleared. You can add a new one later.';

  @override
  String get reorderTracksTitle => 'Reorder tracks';

  @override
  String get shareTooltip => 'Share';

  @override
  String get editDetailsTooltip => 'Edit details & image';

  @override
  String get descriptionSection => 'Description';

  @override
  String get annotationsSection => 'Annotations';

  @override
  String get addAnnotationButton => 'Add annotation';

  @override
  String get noAnnotationsYet => 'No annotations yet.';

  @override
  String get stopsList => 'Stop list';

  @override
  String get editStopsButton => 'Edit stops';

  @override
  String get addStopTooltip => 'Add stop';

  @override
  String get reorderTracksTooltip => 'Reorder tracks';

  @override
  String get mapSection => 'Map';

  @override
  String get openStreetMapContributors => 'OpenStreetMap contributors';

  @override
  String get poweredByOSM => 'Powered by OpenStreetMap';

  @override
  String get noStopsYetTapPlus => 'No stops yet. Tap + to add one.';

  @override
  String get communityRating => 'Community';

  @override
  String ratingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
    );
    return '$_temp0';
  }

  @override
  String get yourRating => 'Your rating';

  @override
  String get rateIt => 'Rate it';

  @override
  String deleteOrphanSegmentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete transit segments?',
      one: 'Delete transit segment?',
    );
    return '$_temp0';
  }

  @override
  String deleteOrphanSegmentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'There are $count transit segments connecting these two stops. Adding a stop between them will hide them because the stops will no longer be adjacent. Delete the segments and continue?',
      one:
          'There is 1 transit segment connecting these two stops. Adding a stop between them will hide it because the stops will no longer be adjacent. Delete the segment and continue?',
    );
    return '$_temp0';
  }

  @override
  String get deleteAndContinue => 'Delete & continue';

  @override
  String get notSet => 'Not set';

  @override
  String get stopDetailsView => 'Stop Details';

  @override
  String get editStopTitle => 'Edit Stop';

  @override
  String get addStopTitle => 'Add Stop';

  @override
  String get editStopTooltip => 'Edit stop';

  @override
  String get duplicateStopTitle => 'Duplicate stop';

  @override
  String duplicateStopMessage(String name) {
    return '$name is already in this itinerary. Add it again anyway?';
  }

  @override
  String get addAnyway => 'Add anyway';

  @override
  String get itineraryUpdatedTitle => 'Itinerary updated elsewhere';

  @override
  String get itineraryUpdatedMessage =>
      'This itinerary was edited from another device. Go back and reload to see the latest version.';

  @override
  String get goBack => 'Go back';

  @override
  String get deleteStopTitle => 'Delete this stop?';

  @override
  String get deleteStopMessage =>
      'This will remove the stop, its annotations, and any transit segments connected to it. This cannot be undone.';

  @override
  String get viewOnlyTitle => 'View only';

  @override
  String get viewOnlyMessage => 'Tap the Edit button to make changes.';

  @override
  String get searchForPlaceLabel => 'Search for a place';

  @override
  String get searchAPlaceHelpTitle => 'Search a place';

  @override
  String get searchAPlaceHelpMessage =>
      'Type a place, restaurant, or landmark name. Pick a result to autofill the place name, address, and coordinates below.';

  @override
  String get searchPlaceHintText => 'e.g. Eiffel Tower, Paris';

  @override
  String get stopDetailsSectionLabel => 'Stop details';

  @override
  String get placeNameLabel => 'Place name';

  @override
  String get placeNameHelp =>
      'Name of the place, restaurant, landmark, or stop.';

  @override
  String get placeNameRequired => 'Place name is required';

  @override
  String get addressLabel => 'Address';

  @override
  String get addressHelp => 'Street address or area description. Optional.';

  @override
  String get coordinatesHelp =>
      'The map location for this stop. Tap \"Pick on map\" to set or adjust it.';

  @override
  String get pickOnMap => 'Pick on map';

  @override
  String get placeTypeLabel => 'Place type';

  @override
  String get placeTypeHelp =>
      'What kind of place this is (e.g. eat & drink, sleep, sight). Used for filtering and the map icon.';

  @override
  String get selectPlaceType => 'Select place type';

  @override
  String get recommendedTimeLabel => 'Recommended time to spend';

  @override
  String get timeToSpendHelp =>
      'Roughly how long you expect to stay here. Tap to set days, hours, and minutes.';

  @override
  String get stopIsFree => 'This stop is free';

  @override
  String get freeHelp => 'Toggle on if visiting this place costs nothing.';

  @override
  String get costLabel => 'Cost';

  @override
  String get costHelp =>
      'Approximate cost per person, in the itinerary\'s currency.';

  @override
  String get enterValidNumber => 'Enter a valid number';

  @override
  String get thoughtsLabel => 'Thoughts';

  @override
  String get thoughtsHelp =>
      'Your personal take on this stop — what to expect, what you loved, things to skip, opening tips. Use the toolbar to add bold, italic, headings, or bullet lists.';

  @override
  String get annotationsLabel => 'Annotations';

  @override
  String get annotationsHelp =>
      'Short tagged notes (advice, caution, avoid, info) attached to this stop. Useful for warnings or tips.';

  @override
  String get saveChangesButton => 'Save Changes';

  @override
  String get addStopButton => 'Add Stop';

  @override
  String get deleteStopButton => 'Delete Stop';

  @override
  String get timeToSpendModalTitle => 'Time to spend';

  @override
  String get editTransitTitle => 'Edit Transit';

  @override
  String get addTransitTitle => 'Add Transit';

  @override
  String get updateTransitButton => 'Update Transit';

  @override
  String get transportModeLabel => 'Mode';

  @override
  String get transportModeHelp =>
      'How you travel on this leg (walk, bus, train, ferry, etc.). Some modes reveal extra fields for line and direction.';

  @override
  String get transitLineLabel => 'Line (optional)';

  @override
  String get transitLineHelp =>
      'Optional. The line number or name (e.g. \"Bus 42\", \"M1\").';

  @override
  String get transitDirectionLabel => 'Direction (optional)';

  @override
  String get transitDirectionHelp =>
      'Optional. Where the line is headed (e.g. \"Northbound\", \"Châtelet\").';

  @override
  String get durationLabel => 'Duration';

  @override
  String get durationHelp => 'How long this leg takes in hours and minutes.';

  @override
  String get legCostHelp =>
      'Approximate cost in the itinerary\'s currency. Disabled when \"Free\" is on.';

  @override
  String get hoursLabel => 'h';

  @override
  String get minutesLabel => 'min';

  @override
  String get freeLegLabel => 'Free';

  @override
  String get freeLegHelp =>
      'Toggle on if this leg costs nothing (walking, included transfer, etc.).';

  @override
  String get legThoughtsLabel => 'Thoughts (optional)';

  @override
  String get legThoughtsHelp =>
      'Optional. Anything useful to know about this leg — booking tips, transfer instructions, where to sit, ticket cost surprises.';

  @override
  String get annotationTypeLabel => 'Type';

  @override
  String get annotationTypeHelp =>
      'Advice: a helpful tip. Caution: be careful. Avoid: don\'t go. Info: a neutral note.';

  @override
  String get annotationAdvice => 'Advice';

  @override
  String get annotationCaution => 'Caution';

  @override
  String get annotationAvoid => 'Avoid';

  @override
  String get annotationInfo => 'Info';

  @override
  String get annotationContentLabel => 'Content *';

  @override
  String get annotationContentHelp =>
      'Describe your advice, caution, warning, or note in one or two sentences.';

  @override
  String get annotationContentRequired => 'Content is required';

  @override
  String get editAnnotationTitle => 'Edit annotation';

  @override
  String get addAnnotationDialogTitle => 'Add annotation';

  @override
  String get saveButton => 'Save';

  @override
  String get moveStopTitle => 'Move stop';

  @override
  String moveStopDescription(int max) {
    return 'Choose an existing track, a gap to create a new track, or extract into its own track. Tracks at the $max-stop maximum are disabled.';
  }

  @override
  String get extractIntoOwnTrack => 'Extract into its own new track';

  @override
  String get moveButton => 'Move';

  @override
  String moveStopMoved(String destination) {
    return 'Moved to $destination';
  }

  @override
  String get itineraryChangedElsewhere =>
      'Itinerary changed elsewhere — close and reopen to see the latest order.';

  @override
  String get moveStopOrphan1 =>
      'This is the last stop in its track — the track will be removed from the itinerary.';

  @override
  String moveStopOrphanSegments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count transit segments will be deleted because their stops will no longer be in adjacent tracks.',
      one:
          '1 transit segment will be deleted because its stops will no longer be in adjacent tracks.',
    );
    return '$_temp0';
  }

  @override
  String get moveStopNewTrack => 'New track';

  @override
  String moveStopNewTrackBefore(int n) {
    return 'New track before Track $n';
  }

  @override
  String moveStopNewTrackAfter(int n) {
    return 'New track after Track $n';
  }

  @override
  String moveStopNewTrackBetween(int a, int b) {
    return 'New track between Track $a and Track $b';
  }

  @override
  String get moveStopCurrentSuffix => '  •  current';

  @override
  String moveStopFull(int max) {
    return 'Full $max/$max';
  }

  @override
  String extractSubtitle(String trackName) {
    return 'Splits this stop out of \"$trackName\" — new track lands right after.';
  }

  @override
  String get removeRatingTitle => 'Remove your rating?';

  @override
  String get removeRatingMessage =>
      'Your rating will be deleted and the average will update for everyone viewing this itinerary.';

  @override
  String get rateItineraryTitle => 'Rate this itinerary';

  @override
  String get overallRatingLabel => 'Overall *';

  @override
  String get overallRatingHelp =>
      'Required. Your overall rating of this itinerary, from 1 to 5 stars.';

  @override
  String get ratingThanksMessage => 'Thanks! Your rating helps others.';

  @override
  String get yourImpressionLabel => 'Your impression (optional)';

  @override
  String get yourImpressionHelp =>
      'Optional. Share what stood out — highlights, regrets, who you\'d recommend it to. Use the toolbar to add bold, italic, headings, or bullet lists.';

  @override
  String get removeMyRatingTooltip => 'Remove my rating';

  @override
  String get wantToShareMore => 'Want to share more? (optional)';

  @override
  String get safetyLabel => 'Safety';

  @override
  String get safetyHelp => 'Optional. How safe you felt during this trip.';

  @override
  String get experienceLabel => 'Experience';

  @override
  String get experienceHelp =>
      'Optional. How enjoyable and memorable the trip was.';

  @override
  String get accessibilityLabel => 'Accessibility';

  @override
  String get accessibilityHelp =>
      'Optional. How accessible the itinerary is (mobility, language, signage).';

  @override
  String get familyFriendlyLabel => 'Family-friendly';

  @override
  String get familyFriendlyHelp =>
      'Optional. How suitable the trip is for families with children.';
}
