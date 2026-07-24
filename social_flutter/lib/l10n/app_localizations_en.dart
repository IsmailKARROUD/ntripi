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
  String get navSaved => 'Saved';

  @override
  String get saveItineraryTooltip => 'Save itinerary';

  @override
  String get unsaveItineraryTooltip => 'Remove from saved';

  @override
  String get savedItinerariesTitle => 'Saved';

  @override
  String get noSavedItinerariesYet =>
      'No saved itineraries yet. Tap the bookmark on any itinerary to keep it here.';

  @override
  String get searchSavedHint => 'Search saved…';

  @override
  String get savedSearchNoResults => 'No saved itineraries match your search.';

  @override
  String get feedTitle => 'Discover';

  @override
  String get feedTabTop => 'Top';

  @override
  String get feedTabRecent => 'Recent';

  @override
  String get feedEmpty => 'No public itineraries yet. Check back soon!';

  @override
  String get feedTopEmpty => 'Not enough rated trips yet — check Recent.';

  @override
  String get offlineBanner =>
      'You\'re Offline! Some features may be unavailable.';

  @override
  String get offlineActionTitle => 'You\'re offline';

  @override
  String get offlineActionMessage =>
      'Changes can\'t be made without an internet connection. Reconnect and try again.';

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
  String get passwordTooLong =>
      'Password is too long — up to 72 characters (fewer with non-Latin letters).';

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
  String get addStopHintTitle => 'Add your stops';

  @override
  String get addStopHintMessage => 'To add stops, tap Edit ✎ at the top.';

  @override
  String get addCoverHintMessage =>
      'To add a cover image, tap this button at the top.';

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
  String get tapToSeeStops => 'Tap to see stops';

  @override
  String get coverImageSection => 'Cover image';

  @override
  String get coverImageUrlLabel => 'Cover image URL';

  @override
  String get uploadCoverImage => 'Upload cover image';

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
  String get whereTheyveBeen => 'WHERE THEY\'VE BEEN';

  @override
  String get itinerariesSectionHeader => 'ITINERARIES';

  @override
  String get noPublicItinerariesYet => 'No public itineraries yet.';

  @override
  String get accountIsPrivateTitle => 'This account is private';

  @override
  String get followRequestSentTitle => 'Request sent';

  @override
  String get followRequestPendingMessage =>
      'Once they accept your request, you\'ll see their itineraries, stops and travel map.';

  @override
  String followToSeeMessage(String handle) {
    return 'Follow $handle to see their itineraries, stops and travel map.';
  }

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
  String get addBioLabel => 'Add a bio';

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
  String get securitySection => 'Security';

  @override
  String get dangerZoneSection => 'Danger zone';

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
  String get browseForIdeas => 'Explore the community feed for ideas.';

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
  String get settingsTheme => 'Theme';

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
  String get languageArabic => 'العربية';

  @override
  String get themePickerTitle => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

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
  String get itineraryTitleHint => 'e.g. 10 days in Kyoto & Osaka';

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
  String get addDescriptionLabel => 'Add a description';

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
  String get formSectionBasics => 'BASICS';

  @override
  String get formLabelCurrency => 'CURRENCY';

  @override
  String get formLabelWhoCanSee => 'WHO CAN SEE THIS?';

  @override
  String get formSectionDangerZone => 'DANGER ZONE';

  @override
  String get formLabelDeleteItinerary => 'DELETE ITINERARY';

  @override
  String get formDeleteItineraryHint => 'Type the title to confirm';

  @override
  String get currencySearchHint => 'Search currency…';

  @override
  String currenciesLoadFailed(String error) {
    return 'Failed to load currencies: $error';
  }

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
  String get errorNoInternet =>
      'No internet connection. Please check your network and try again.';

  @override
  String get errorGenericRetry => 'An error occurred. Please try again.';

  @override
  String get errorGeneric => 'An error occurred.';

  @override
  String get fieldHelpTooltip => 'What is this?';

  @override
  String typeToConfirmInstruction(String text) {
    return 'Type \"$text\" to confirm:';
  }

  @override
  String get daysLabel => 'd';

  @override
  String get noneOption => 'None';

  @override
  String get discardButton => 'Discard';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesMessage => 'Your changes will not be saved.';

  @override
  String get keepEditingButton => 'Keep editing';

  @override
  String get orderSavedMessage => 'Order saved';

  @override
  String get segmentSelectBothStops => 'Select both a From and a To stop.';

  @override
  String get segmentStopsMustDiffer => 'From and To stops must differ.';

  @override
  String get segmentAddLegFirst => 'Add at least one leg before saving.';

  @override
  String get segmentAlreadyExistsTitle => 'Segment already exists';

  @override
  String get segmentAlreadyExistsMessage =>
      'A segment already connects these two stops. What do you want to do?';

  @override
  String get segmentJoin => 'Join';

  @override
  String get segmentReplace => 'Replace';

  @override
  String get segmentFromStopLabel => 'From Stop';

  @override
  String get segmentToStopLabel => 'To Stop';

  @override
  String get visibilityScreenTitle => 'Who can see this?';

  @override
  String get visibilityAddPerson => 'Add person';

  @override
  String get visibilitySearchByUsername => 'Search by username…';

  @override
  String get couldNotLoadRatings => 'Could not load ratings';

  @override
  String get stopNotFound => 'Stop not found.';

  @override
  String get mapPickLocationTitle => 'Pick Location';

  @override
  String get mapConfirmLocation => 'Confirm Location';

  @override
  String get stopCostHint => 'e.g. 20';

  @override
  String get ratingsTitle => 'Ratings';

  @override
  String get noRatingsYet => 'No ratings yet';

  @override
  String get ratingsOverallLabel => 'OVERALL';

  @override
  String get rateThisTrip => 'Rate this trip';

  @override
  String get deletedUser => 'Deleted User';

  @override
  String get annotationContentHint => 'What should travelers know?';

  @override
  String get countryPickerTitle => 'Select country';

  @override
  String get countrySearchHint => 'Search countries…';

  @override
  String get countryNoneClear => 'None / Clear';

  @override
  String get languageSearchHint => 'Search languages…';

  @override
  String get coverChangeButton => 'Change';

  @override
  String get coverEditCropButton => 'Edit crop';

  @override
  String get coverAdjustTitle => 'Adjust cover photo';

  @override
  String get mdBoldTooltip => 'Bold';

  @override
  String get mdItalicTooltip => 'Italic';

  @override
  String get mdHeading1Tooltip => 'Heading 1';

  @override
  String get mdHeading2Tooltip => 'Heading 2';

  @override
  String get mdBulletListTooltip => 'Bullet list';

  @override
  String get mdNumberedListTooltip => 'Numbered list';

  @override
  String get mdEditTab => 'Edit';

  @override
  String get mdPreviewTab => 'Preview';

  @override
  String get legCostHint => 'e.g. 12.50';

  @override
  String get addLegButton => 'Add leg';

  @override
  String get totalLabel => 'Total';

  @override
  String get reorderOrphanTitle => 'Save reorder?';

  @override
  String reorderOrphanMessage(int count, String segments) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count transit segments will be deleted because their stops will no longer be in adjacent tracks:\n\n$segments',
      one:
          '$count transit segment will be deleted because its stops will no longer be in adjacent tracks:\n\n$segments',
    );
    return '$_temp0';
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
  String get verifyEmailTitle => 'Verify your email';

  @override
  String get verifyEmailMessage =>
      'Verify your email to unlock creating trips, rating, and following people.';

  @override
  String get verifyEmailButton => 'Verify with Google';

  @override
  String get emailVerifiedSuccess => 'Email verified — you\'re all set!';

  @override
  String get resendVerificationButton => 'Resend verification email';

  @override
  String get verificationEmailSent =>
      'Verification email sent — check your inbox.';

  @override
  String get forgotPasswordTitle => 'Reset your password';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your account email and we\'ll send you a link to set a new password.';

  @override
  String get forgotPasswordEmailLabel => 'Email';

  @override
  String get forgotPasswordSubmit => 'Send reset link';

  @override
  String get forgotPasswordSentTitle => 'Check your email';

  @override
  String get forgotPasswordSentBody =>
      'If an account exists for that email, we\'ve sent a password reset link. Check your inbox and spam folder.';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get changePasswordSubtitle =>
      'Enter your current password, then choose a new one. Changing it signs out every other device.';

  @override
  String get changePasswordCurrentLabel => 'Current password';

  @override
  String get changePasswordNewLabel => 'New password';

  @override
  String get changePasswordConfirmLabel => 'Confirm new password';

  @override
  String get changePasswordMismatch => 'Passwords don\'t match.';

  @override
  String get changePasswordSameAsOld =>
      'New password must differ from the current one.';

  @override
  String get changePasswordSubmit => 'Change password';

  @override
  String get changePasswordConfirmMessage =>
      'This signs you out on all your other devices. Continue?';

  @override
  String get changePasswordSuccess =>
      'Password changed. Other devices were signed out.';

  @override
  String get backToSignIn => 'Back to sign in';

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
  String get deleteAccountGoogleExplain =>
      'This account uses Google Sign-In. Re-authenticate with Google to confirm deletion.';

  @override
  String get deleteAccountGoogleButton => 'Continue with Google';

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
  String get openInMaps => 'Open in maps';

  @override
  String get otherMapsApp => 'Other maps app';

  @override
  String get openRouteInMaps => 'Open route in Google Maps';

  @override
  String routeTruncated(int count) {
    return 'Google Maps can only show the first $count stops';
  }

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
  String get mapLinkLabel => 'Google Maps link';

  @override
  String get mapLinkHint => 'Paste a Google Maps link';

  @override
  String get mapLinkInvalid => 'Enter a valid Google Maps link';

  @override
  String get mapLinkPaste => 'Paste';

  @override
  String get mapLinkClear => 'Clear';

  @override
  String get locationModeCoordinates => 'Coordinates';

  @override
  String get locationModeMapLink => 'Google Maps link';

  @override
  String get linkPreviewOpensInMaps => 'Opens in Google Maps';

  @override
  String get linkPreviewLoading => 'Loading preview…';

  @override
  String get linkPreviewTitleCopied => 'Title copied';

  @override
  String get linkPreviewMapMobileOnly =>
      'Map preview available in the mobile app';

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
  String get placeTypeEatDrink => 'Eat & Drink';

  @override
  String get placeTypeSleep => 'Sleep';

  @override
  String get placeTypePray => 'Pray';

  @override
  String get placeTypeLearnSee => 'Learn & See';

  @override
  String get placeTypeBuy => 'Buy';

  @override
  String get placeTypePlayWatch => 'Play & Watch';

  @override
  String get placeTypeNature => 'Nature';

  @override
  String get placeTypeTransport => 'Transport';

  @override
  String get placeTypeHealBathe => 'Heal & Bathe';

  @override
  String get placeTypeEntertainment => 'Entertainment';

  @override
  String get placeTypeSight => 'Sight';

  @override
  String get placeTypeHintEatDrink =>
      'cafe, restaurant, bar, bakery, food truck';

  @override
  String get placeTypeHintSleep => 'hotel, hostel, campsite, inn, lodge';

  @override
  String get placeTypeHintPray => 'church, mosque, temple, synagogue, shrine';

  @override
  String get placeTypeHintLearnSee =>
      'museum, gallery, library, aquarium, observatory';

  @override
  String get placeTypeHintBuy => 'shop, market, mall, boutique, stall';

  @override
  String get placeTypeHintPlayWatch =>
      'stadium, gym, arena, court, bowling alley';

  @override
  String get placeTypeHintNature => 'beach, park, forest, mountain, waterfall';

  @override
  String get placeTypeHintTransport =>
      'airport, train station, bus stop, ferry terminal';

  @override
  String get placeTypeHintHealBathe =>
      'spa, hot spring, pool, sauna, bathhouse';

  @override
  String get placeTypeHintEntertainment =>
      'theater, cinema, concert hall, nightclub';

  @override
  String get placeTypeHintSight => 'monument, viewpoint, castle, square, ruin';

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

  @override
  String get crowdednessLabel => 'Uncrowded';

  @override
  String get crowdednessHelp =>
      'Optional. How uncrowded and spacious it felt — 5 = pleasantly uncrowded, 1 = overcrowded.';

  @override
  String get showOptionalFields => 'Show optional fields';

  @override
  String get hideOptionalFields => 'Hide optional fields';

  @override
  String get transportModeWalk => 'Walk';

  @override
  String get transportModeBus => 'Bus';

  @override
  String get transportModeTram => 'Tram';

  @override
  String get transportModeMetro => 'Metro';

  @override
  String get transportModeTrain => 'Train';

  @override
  String get transportModeTaxi => 'Taxi';

  @override
  String get transportModeUber => 'Uber';

  @override
  String get transportModeBike => 'Bike';

  @override
  String get transportModeFerry => 'Ferry';

  @override
  String get transportModeCar => 'Car';

  @override
  String get transportModeAirplane => 'Airplane';

  @override
  String get dimensionOverall => 'Overall';

  @override
  String get dimensionOverallDesc => 'General impression';

  @override
  String get dimensionSafetyDesc => 'How safe you felt throughout';

  @override
  String get dimensionExperienceDesc => 'Quality of the overall experience';

  @override
  String get dimensionAccessibilityDesc => 'Ease of access for all abilities';

  @override
  String get dimensionFamilyFriendlyDesc =>
      'Suitability for children and families';

  @override
  String get dimensionCrowdednessDesc => 'How uncrowded and spacious it felt';

  @override
  String dimensionRatingTitle(String label) {
    return '$label Rating';
  }

  @override
  String noRatingsYetFor(String label) {
    return 'No ratings yet for $label';
  }

  @override
  String basedOnRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Based on $count ratings',
      one: 'Based on $count rating',
    );
    return '$_temp0';
  }

  @override
  String get ratersLabel => 'Raters';

  @override
  String get annotationAdviceDesc => 'Something useful or pro-tip.';

  @override
  String get annotationCautionDesc => 'Pay attention — surprises possible.';

  @override
  String get annotationAvoidDesc => 'Don\'t do this. Save your time.';

  @override
  String get annotationInfoDesc => 'A neutral fact worth knowing.';

  @override
  String get unknownUser => 'Unknown';

  @override
  String timeAgoMonths(int count) {
    return '${count}mo ago';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}d ago';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h ago';
  }

  @override
  String timeAgoMinutes(int count) {
    return '${count}min ago';
  }

  @override
  String get timeJustNow => 'Just now';

  @override
  String get yearsAbbrev => 'y';

  @override
  String get timeLabel => 'Time';

  @override
  String get transitLabel => 'Transit';

  @override
  String get noLegsYetTapAdd => 'No legs yet. Tap ＋ to add.';

  @override
  String get segmentNeedsOneLeg =>
      'A segment needs at least one leg. Delete the segment instead.';

  @override
  String fromStopName(String name) {
    return 'From $name';
  }

  @override
  String toStopName(String name) {
    return 'To $name';
  }

  @override
  String get visibilityPublicDesc => 'Anyone with the link can view.';

  @override
  String get visibilityFollowersDesc => 'Only people who follow you.';

  @override
  String get visibilityRestrictedDesc => 'Only people you allow.';

  @override
  String get visibilityOnlyMeDesc => 'Just you.';

  @override
  String get saveItineraryFirstAllowlist =>
      'Save the itinerary first, then manage your allowlist from the edit screen.';

  @override
  String get allowlistLabel => 'Allowlist';

  @override
  String personCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '$count person',
    );
    return '$_temp0';
  }

  @override
  String removedFromAllowlist(String name) {
    return 'Removed $name from allowlist';
  }

  @override
  String get addPeople => 'Add people';

  @override
  String get otherOption => 'Other';

  @override
  String get thisItineraryFallback => 'this itinerary';

  @override
  String get discardReorderMessage => 'Your reorder will not be saved.';

  @override
  String get emptyTrackName => '(empty)';

  @override
  String get unnamedStop => '(unnamed)';

  @override
  String get unknownStop => '(unknown)';

  @override
  String get dragToChangeTrackOrder => 'Drag to change the track order';

  @override
  String transitSegmentsWillBeDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transit segments will be deleted',
      one: '1 transit segment will be deleted',
    );
    return '$_temp0';
  }

  @override
  String andMoreCount(int count) {
    return '… and $count more';
  }

  @override
  String altsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alts',
      one: '$count alt',
    );
    return '$_temp0';
  }

  @override
  String segmentToWillBeDeleted(String name) {
    return '→ $name  —  segment will be deleted';
  }

  @override
  String get reorderAlternativesTitle => 'Reorder alternatives';

  @override
  String get reorderAlternativesHint =>
      'Drag to change which option appears first. Tap Save to apply.';

  @override
  String get emptyTrackLabel => '(empty track)';

  @override
  String get moveStopToLabel => 'Move stop to';

  @override
  String get messageLabel => 'Message';

  @override
  String get annotationKeepShortHint =>
      'Keep it short — under 200 characters reads best on small screens.';

  @override
  String get transportModeSection => 'Transport mode';

  @override
  String get lineDirectionSection => 'Line & direction';

  @override
  String get durationCostSection => 'Duration & cost';

  @override
  String get allRatersLabel => 'All raters';

  @override
  String travelersRatedThis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count travelers rated this',
      one: '$count traveler rated this',
    );
    return '$_temp0';
  }

  @override
  String get byDimensionLabel => 'By dimension';

  @override
  String get notEnoughRatings => 'Not enough ratings';

  @override
  String get youRatedThis => 'You rated this';

  @override
  String get changeButton => 'Change';

  @override
  String get hideReview => 'Hide review';

  @override
  String get readReview => 'Read review';

  @override
  String get notesLabel => 'Notes';

  @override
  String get viewLess => 'view less';

  @override
  String get viewMore => '... view more';

  @override
  String get imageTooLarge => 'Image is too large (max 10 MB).';

  @override
  String get couldNotLoadImage => 'Could not load image. Please try another.';

  @override
  String get pinchToZoomHint => 'Pinch to zoom · Drag to reposition';

  @override
  String get addCoverImage => 'Add a cover image';

  @override
  String get coverOptionalMapFallback =>
      'Optional — the map will be used otherwise.';

  @override
  String get noCoverImage => 'No cover image';

  @override
  String get mapTapToPlacePin => 'Tap the map to place a pin';

  @override
  String get mapTapToMovePin =>
      'Tap elsewhere to move the pin, then tap Confirm';

  @override
  String get mapMyLocation => 'My location';

  @override
  String get mapUseMyLocation => 'Use my location';

  @override
  String get mapSearchNoResults => 'No places found.';

  @override
  String get mapSearchThisArea => 'Search this area';

  @override
  String get mapUnnamedPlace => 'Unnamed location';

  @override
  String get locationPermissionDenied => 'Location permission denied';

  @override
  String get locationServiceDisabled => 'Location services are disabled';

  @override
  String get locationUnavailable => 'Couldn\'t get your location';

  @override
  String get locationOpenSettings => 'Open settings';

  @override
  String get nothingToPreview => 'Nothing to preview yet.';

  @override
  String get rateOverallFirstHint =>
      'Rate your overall impression. Once you do, you can share more.';

  @override
  String get splashTagline =>
      'Discover & share travel itineraries\ncrafted by real explorers';

  @override
  String get splashMotto => 'Explore the world, one route at a time';

  @override
  String get tripsPillLabel => 'trips';

  @override
  String get stopsPillLabel => 'stops';

  @override
  String get travelledPillLabel => 'travelled';

  @override
  String get stopFallbackName => 'Stop';

  @override
  String stopWithNumber(int n) {
    return 'Stop $n';
  }

  @override
  String get undoLabel => 'Undo';

  @override
  String get updateYourRating => 'Update your rating';

  @override
  String get moveActionLabel => 'move';

  @override
  String get reorderActionLabel => 'reorder';

  @override
  String get aStopFallback => 'A stop';

  @override
  String get locationLabel => 'Location';

  @override
  String get noLocationSet => 'No location set';

  @override
  String get latitudeLabel => 'Latitude';

  @override
  String get longitudeLabel => 'Longitude';

  @override
  String get invalidLatitudeError =>
      'Latitude must be a number between -90 and 90';

  @override
  String get invalidLongitudeError =>
      'Longitude must be a number between -180 and 180';

  @override
  String get coordinatesPairRequiredError =>
      'Enter both latitude and longitude';

  @override
  String get detailsSection => 'Details';

  @override
  String get addLanguageTitle => 'Add language';

  @override
  String alreadyInItinerary(String name) {
    return '$name is already in this itinerary.';
  }

  @override
  String stopNumberOfTotal(int n, int total) {
    return 'Stop $n of $total';
  }

  @override
  String shareCaption(String title, String stops, String duration) {
    return 'Check out \"$title\" on Ntripi — $stops, $duration';
  }

  @override
  String get apiErrorNotAuthenticated => 'You are not signed in.';

  @override
  String get apiErrorAccountDeactivated => 'Your account has been deactivated.';

  @override
  String get apiErrorEmailUnverified =>
      'Verify your email via Google to do this.';

  @override
  String get apiErrorItineraryNotFound => 'Itinerary not found.';

  @override
  String get apiErrorItineraryNotOwner =>
      'You don\'t have permission to modify this itinerary.';

  @override
  String get apiErrorIfMatchRequired =>
      'This change could not be saved — please reload and try again.';

  @override
  String get apiErrorItineraryStale =>
      'The itinerary was modified — please reload.';

  @override
  String get apiErrorWaitlistContactRequired =>
      'Provide at least an email or a WhatsApp number.';

  @override
  String get apiErrorGoogleTokenInvalid => 'Invalid Google token.';

  @override
  String get apiErrorInvalidGrant =>
      'Your session expired. Please sign in again.';

  @override
  String get apiErrorStopNotFound => 'Stop not found.';

  @override
  String get apiErrorTrackNotFound =>
      'Track not found, or it doesn\'t belong to this itinerary.';

  @override
  String get apiErrorSegmentNotFound => 'Transit segment not found.';

  @override
  String get apiErrorLegNotFound => 'Transport leg not found.';

  @override
  String get apiErrorItineraryAccessDenied =>
      'You don\'t have access to this itinerary.';

  @override
  String get apiErrorAllowlistRestrictedOnly =>
      'The allowlist only applies to restricted itineraries.';

  @override
  String get apiErrorUserNotFound => 'User not found.';

  @override
  String get apiErrorAllowlistUserExists => 'This user already has access.';

  @override
  String get apiErrorAllowlistUserNotFound =>
      'User not found in the allowlist.';

  @override
  String get apiErrorRankCollision => 'Ordering conflict — please retry.';

  @override
  String get apiErrorAnnotationNotFound => 'Annotation not found.';

  @override
  String get apiErrorRatingNotFound => 'You haven\'t rated this itinerary.';

  @override
  String get apiErrorSegmentAlreadyExists =>
      'A segment already connects these two stops.';

  @override
  String get apiErrorIncorrectPassword => 'Incorrect password.';

  @override
  String get apiErrorLoginInvalid => 'Incorrect email/username or password.';

  @override
  String get apiErrorCannotFollowSelf => 'You cannot follow yourself.';

  @override
  String get apiErrorNotFollowing => 'You are not following this user.';

  @override
  String get apiErrorFollowRequestNotFound => 'Follow request not found.';

  @override
  String get apiErrorFollowRequestAlreadyAccepted =>
      'This follow request has already been accepted.';

  @override
  String get apiErrorCannotRejectRequest =>
      'You cannot reject this follow request.';

  @override
  String get apiErrorAccountPrivate => 'This account is private.';

  @override
  String get apiErrorTosRequired =>
      'You must accept the Terms of Service to register.';

  @override
  String get apiErrorUsernameTaken => 'This username is already taken.';

  @override
  String get apiErrorEmailTaken => 'An account with this email already exists.';
}
