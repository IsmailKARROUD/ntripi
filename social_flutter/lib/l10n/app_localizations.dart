import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navItineraries.
  ///
  /// In en, this message translates to:
  /// **'Itineraries'**
  String get navItineraries;

  /// No description provided for @navFeed.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get navFeed;

  /// No description provided for @feedTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get feedTitle;

  /// No description provided for @feedTabTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get feedTabTop;

  /// No description provided for @feedTabRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get feedTabRecent;

  /// No description provided for @feedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No public itineraries yet. Check back soon!'**
  String get feedEmpty;

  /// No description provided for @feedTopEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not enough rated trips yet — check Recent.'**
  String get feedTopEmpty;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re Offline! Some features may be unavailable.'**
  String get offlineBanner;

  /// No description provided for @offlineActionTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineActionTitle;

  /// No description provided for @offlineActionMessage.
  ///
  /// In en, this message translates to:
  /// **'Changes can\'t be made without an internet connection. Reconnect and try again.'**
  String get offlineActionMessage;

  /// No description provided for @downloadBanner.
  ///
  /// In en, this message translates to:
  /// **'For a better experience, download the Ntripi app.'**
  String get downloadBanner;

  /// No description provided for @downloadBannerButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadBannerButton;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue your journey'**
  String get loginSubtitle;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get loginEmailLabel;

  /// No description provided for @loginEmailHelp.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the email you registered with, or your @username handle.'**
  String get loginEmailHelp;

  /// No description provided for @loginEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com or @username'**
  String get loginEmailHint;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Your account password. Tap the eye icon to show or hide it.'**
  String get loginPasswordHelp;

  /// No description provided for @loginForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get loginForgotPassword;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginSignIn;

  /// No description provided for @loginNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get loginNoAccount;

  /// No description provided for @loginSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get loginSignUp;

  /// No description provided for @loginOrContinueWith.
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get loginOrContinueWith;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join thousands of explorers sharing routes'**
  String get registerSubtitle;

  /// No description provided for @registerDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get registerDisplayName;

  /// No description provided for @registerDisplayNameHelp.
  ///
  /// In en, this message translates to:
  /// **'How your name appears to others. Up to 50 characters, any language and emoji. Falls back to @username if blank.'**
  String get registerDisplayNameHelp;

  /// No description provided for @registerDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get registerDisplayNameHint;

  /// No description provided for @registerUsername.
  ///
  /// In en, this message translates to:
  /// **'Username *'**
  String get registerUsername;

  /// No description provided for @registerUsernameHelp.
  ///
  /// In en, this message translates to:
  /// **'Your unique @handle. Lowercase letters, digits, and underscores only. This cannot be changed later.'**
  String get registerUsernameHelp;

  /// No description provided for @registerUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'yourhandle'**
  String get registerUsernameHint;

  /// No description provided for @registerEmail.
  ///
  /// In en, this message translates to:
  /// **'Email *'**
  String get registerEmail;

  /// No description provided for @registerEmailHelp.
  ///
  /// In en, this message translates to:
  /// **'Used to sign in and recover your account. We never display it publicly.'**
  String get registerEmailHelp;

  /// No description provided for @registerEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get registerEmailHint;

  /// No description provided for @registerEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required.'**
  String get registerEmailRequired;

  /// No description provided for @registerEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email.'**
  String get registerEmailInvalid;

  /// No description provided for @registerPassword.
  ///
  /// In en, this message translates to:
  /// **'Password *'**
  String get registerPassword;

  /// No description provided for @registerPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters with at least one digit.'**
  String get registerPasswordHelp;

  /// No description provided for @registerPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Min. 8 characters'**
  String get registerPasswordHint;

  /// No description provided for @registerPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required.'**
  String get registerPasswordRequired;

  /// No description provided for @registerPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Must be at least 8 characters.'**
  String get registerPasswordTooShort;

  /// No description provided for @registerPasswordNoDigit.
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one digit.'**
  String get registerPasswordNoDigit;

  /// No description provided for @passwordTooLong.
  ///
  /// In en, this message translates to:
  /// **'Password is too long — up to 72 characters (fewer with non-Latin letters).'**
  String get passwordTooLong;

  /// No description provided for @registerConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password *'**
  String get registerConfirmPassword;

  /// No description provided for @registerConfirmPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Type your password again to make sure it matches.'**
  String get registerConfirmPasswordHelp;

  /// No description provided for @registerConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password.'**
  String get registerConfirmRequired;

  /// No description provided for @registerConfirmMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get registerConfirmMismatch;

  /// No description provided for @registerTosAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get registerTosAgree;

  /// No description provided for @registerTos.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get registerTos;

  /// No description provided for @registerTosAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get registerTosAnd;

  /// No description provided for @registerPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get registerPrivacyPolicy;

  /// No description provided for @registerTosHelp.
  ///
  /// In en, this message translates to:
  /// **'You must agree to the Terms of Service and Privacy Policy to create an account. Tap the underlined links to read them.'**
  String get registerTosHelp;

  /// No description provided for @registerTosRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Terms of Service.'**
  String get registerTosRequired;

  /// No description provided for @registerTosTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get registerTosTitle;

  /// No description provided for @registerTosLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get registerTosLoading;

  /// No description provided for @registerCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerCreateAccount;

  /// No description provided for @registerAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get registerAlreadyHaveAccount;

  /// No description provided for @registerSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get registerSignIn;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @latestTrip.
  ///
  /// In en, this message translates to:
  /// **'LATEST TRIP'**
  String get latestTrip;

  /// No description provided for @whereIveBeen.
  ///
  /// In en, this message translates to:
  /// **'WHERE I\'VE BEEN'**
  String get whereIveBeen;

  /// No description provided for @noStopsYet.
  ///
  /// In en, this message translates to:
  /// **'No stops yet'**
  String get noStopsYet;

  /// No description provided for @addStopHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your stops'**
  String get addStopHintTitle;

  /// No description provided for @addStopHintMessage.
  ///
  /// In en, this message translates to:
  /// **'To add stops, tap Edit ✎ at the top.'**
  String get addStopHintMessage;

  /// No description provided for @addCoverHintMessage.
  ///
  /// In en, this message translates to:
  /// **'To add a cover image, tap this button at the top.'**
  String get addCoverHintMessage;

  /// No description provided for @stopCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} stop} other{{count} stops}}'**
  String stopCount(int count);

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @tapToSeeStops.
  ///
  /// In en, this message translates to:
  /// **'Tap to see stops'**
  String get tapToSeeStops;

  /// No description provided for @coverImageSection.
  ///
  /// In en, this message translates to:
  /// **'Cover image'**
  String get coverImageSection;

  /// No description provided for @coverImageUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Cover image URL'**
  String get coverImageUrlLabel;

  /// No description provided for @uploadCoverImage.
  ///
  /// In en, this message translates to:
  /// **'Upload cover image'**
  String get uploadCoverImage;

  /// No description provided for @followRequestsBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow Requests ({count})'**
  String followRequestsBannerTitle(int count);

  /// No description provided for @tapToReview.
  ///
  /// In en, this message translates to:
  /// **'Tap to review'**
  String get tapToReview;

  /// No description provided for @editProfileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileTooltip;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @shareProfileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share profile'**
  String get shareProfileTooltip;

  /// No description provided for @couldNotLoadItineraries.
  ///
  /// In en, this message translates to:
  /// **'Could not load itineraries.'**
  String get couldNotLoadItineraries;

  /// No description provided for @whereTheyveBeen.
  ///
  /// In en, this message translates to:
  /// **'WHERE THEY\'VE BEEN'**
  String get whereTheyveBeen;

  /// No description provided for @itinerariesSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'ITINERARIES'**
  String get itinerariesSectionHeader;

  /// No description provided for @noPublicItinerariesYet.
  ///
  /// In en, this message translates to:
  /// **'No public itineraries yet.'**
  String get noPublicItinerariesYet;

  /// No description provided for @accountIsPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'This account is private'**
  String get accountIsPrivateTitle;

  /// No description provided for @followRequestSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get followRequestSentTitle;

  /// No description provided for @followRequestPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Once they accept your request, you\'ll see their itineraries, stops and travel map.'**
  String get followRequestPendingMessage;

  /// No description provided for @followToSeeMessage.
  ///
  /// In en, this message translates to:
  /// **'Follow {handle} to see their itineraries, stops and travel map.'**
  String followToSeeMessage(String handle);

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileTitle;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload photo'**
  String get uploadPhoto;

  /// No description provided for @identitySection.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identitySection;

  /// No description provided for @displayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameLabel;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @bioLabel.
  ///
  /// In en, this message translates to:
  /// **'BIO'**
  String get bioLabel;

  /// No description provided for @bioHelpMessage.
  ///
  /// In en, this message translates to:
  /// **'A short description. Supports **bold** markdown and emoji.'**
  String get bioHelpMessage;

  /// No description provided for @addBioLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a bio'**
  String get addBioLabel;

  /// No description provided for @avatarUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Avatar URL'**
  String get avatarUrlLabel;

  /// No description provided for @travelIdentitySection.
  ///
  /// In en, this message translates to:
  /// **'Travel identity'**
  String get travelIdentitySection;

  /// No description provided for @passportLabel.
  ///
  /// In en, this message translates to:
  /// **'Passport'**
  String get passportLabel;

  /// No description provided for @livesInLabel.
  ///
  /// In en, this message translates to:
  /// **'Lives in'**
  String get livesInLabel;

  /// No description provided for @languagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languagesLabel;

  /// No description provided for @privacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacySection;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// No description provided for @dangerZoneSection.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZoneSection;

  /// No description provided for @privateAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Private account'**
  String get privateAccountLabel;

  /// No description provided for @privateAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People must request to follow you to see your itineraries.'**
  String get privateAccountSubtitle;

  /// No description provided for @switchToPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to public?'**
  String get switchToPublicTitle;

  /// No description provided for @switchToPublicMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{You have 1 pending follow request. Switching to public will automatically accept it. Continue?} other{You have {count} pending follow requests. Switching to public will automatically accept all of them. Continue?}}'**
  String switchToPublicMessage(int count);

  /// No description provided for @switchToPublicButton.
  ///
  /// In en, this message translates to:
  /// **'Switch to public'**
  String get switchToPublicButton;

  /// No description provided for @planFirstJourney.
  ///
  /// In en, this message translates to:
  /// **'Plan your first journey'**
  String get planFirstJourney;

  /// No description provided for @planFirstJourneyHint.
  ///
  /// In en, this message translates to:
  /// **'Add stops, transit segments and notes. Share it with friends or keep it private.'**
  String get planFirstJourneyHint;

  /// No description provided for @createItinerary.
  ///
  /// In en, this message translates to:
  /// **'Create itinerary'**
  String get createItinerary;

  /// No description provided for @needInspiration.
  ///
  /// In en, this message translates to:
  /// **'Need inspiration?'**
  String get needInspiration;

  /// No description provided for @browseForIdeas.
  ///
  /// In en, this message translates to:
  /// **'Explore the community feed for ideas.'**
  String get browseForIdeas;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsNotificationsOn;

  /// No description provided for @settingsNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsNotificationsOff;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get settingsHelpCenter;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About Ntripi'**
  String get settingsAbout;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Privacy'**
  String get settingsTerms;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogout;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirmMessage;

  /// No description provided for @logoutConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutConfirmButton;

  /// No description provided for @languagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languagePickerTitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @themePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themePickerTitle;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @followRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow Requests'**
  String get followRequestsTitle;

  /// No description provided for @noRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get noRequests;

  /// No description provided for @requestsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Requests · {count}'**
  String requestsCountLabel(int count);

  /// No description provided for @acceptButton.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptButton;

  /// No description provided for @rejectButton.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get rejectButton;

  /// No description provided for @followersTabLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Followers} other{{count} Followers}}'**
  String followersTabLabel(int count);

  /// No description provided for @followingTabLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Following} other{{count} Following}}'**
  String followingTabLabel(int count);

  /// No description provided for @followRequestsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Follow requests · {count}'**
  String followRequestsSectionLabel(int count);

  /// No description provided for @allFollowersSection.
  ///
  /// In en, this message translates to:
  /// **'All followers'**
  String get allFollowersSection;

  /// No description provided for @noFollowersYet.
  ///
  /// In en, this message translates to:
  /// **'No followers yet.'**
  String get noFollowersYet;

  /// No description provided for @notFollowingAnyone.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet.'**
  String get notFollowingAnyone;

  /// No description provided for @peopleYouFollow.
  ///
  /// In en, this message translates to:
  /// **'People you follow'**
  String get peopleYouFollow;

  /// No description provided for @confirmButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmButton;

  /// No description provided for @searchPeoplePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search people…'**
  String get searchPeoplePlaceholder;

  /// No description provided for @searchForPeople.
  ///
  /// In en, this message translates to:
  /// **'Search for people to follow'**
  String get searchForPeople;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found.'**
  String get noUsersFound;

  /// No description provided for @searchResultsCount.
  ///
  /// In en, this message translates to:
  /// **'Results · {count}'**
  String searchResultsCount(int count);

  /// No description provided for @followerCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} follower} other{{count} followers}}'**
  String followerCountLabel(int count);

  /// No description provided for @searchUsersHelp.
  ///
  /// In en, this message translates to:
  /// **'Find people by their @username or by their display name. Tap a result to view their profile.'**
  String get searchUsersHelp;

  /// No description provided for @myItineraries.
  ///
  /// In en, this message translates to:
  /// **'My Itineraries'**
  String get myItineraries;

  /// No description provided for @noItinerariesYet.
  ///
  /// In en, this message translates to:
  /// **'No itineraries yet.'**
  String get noItinerariesYet;

  /// No description provided for @tapToCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create your first trip.'**
  String get tapToCreateFirst;

  /// No description provided for @deleteItineraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this itinerary?'**
  String get deleteItineraryTitle;

  /// No description provided for @deleteItineraryMessage.
  ///
  /// In en, this message translates to:
  /// **'All stops, annotations, segments, ratings, and shared links will be permanently destroyed. This cannot be undone.'**
  String get deleteItineraryMessage;

  /// No description provided for @deleteItineraryButton.
  ///
  /// In en, this message translates to:
  /// **'Delete itinerary'**
  String get deleteItineraryButton;

  /// No description provided for @newItinerary.
  ///
  /// In en, this message translates to:
  /// **'New Itinerary'**
  String get newItinerary;

  /// No description provided for @editItinerary.
  ///
  /// In en, this message translates to:
  /// **'Edit Itinerary'**
  String get editItinerary;

  /// No description provided for @coverImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Cover image'**
  String get coverImageLabel;

  /// No description provided for @coverImageHelp.
  ///
  /// In en, this message translates to:
  /// **'A 1200×630 image shown on the itinerary card and link previews. Drag inside the crop box to reposition.'**
  String get coverImageHelp;

  /// No description provided for @itineraryTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title *'**
  String get itineraryTitleLabel;

  /// No description provided for @itineraryTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 10 days in Kyoto & Osaka'**
  String get itineraryTitleHint;

  /// No description provided for @itineraryTitleHelp.
  ///
  /// In en, this message translates to:
  /// **'A short, clear name for this trip. Shown on the itinerary card and share previews.'**
  String get itineraryTitleHelp;

  /// No description provided for @itineraryTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get itineraryTitleRequired;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @descriptionHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. A summary of the trip. Use the toolbar to make text bold or italic, add headings, and create bullet or numbered lists. Switch to the Preview tab to see how it will look to readers.'**
  String get descriptionHelp;

  /// No description provided for @addDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a description'**
  String get addDescriptionLabel;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @currencyHelp.
  ///
  /// In en, this message translates to:
  /// **'Default currency for all stop costs and transport costs in this itinerary.'**
  String get currencyHelp;

  /// No description provided for @visibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibilityLabel;

  /// No description provided for @visibilityHelp.
  ///
  /// In en, this message translates to:
  /// **'Public: anyone can view. Followers: only people who follow you. Restricted: only the users you allowlist below. Only me: private to you.'**
  String get visibilityHelp;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get visibilityPublic;

  /// No description provided for @visibilityFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get visibilityFollowers;

  /// No description provided for @visibilityRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get visibilityRestricted;

  /// No description provided for @visibilityOnlyMe.
  ///
  /// In en, this message translates to:
  /// **'Only me'**
  String get visibilityOnlyMe;

  /// No description provided for @imageSaveButUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Itinerary saved, but image upload failed. Try again from the edit screen.'**
  String get imageSaveButUploadFailed;

  /// No description provided for @formSectionBasics.
  ///
  /// In en, this message translates to:
  /// **'BASICS'**
  String get formSectionBasics;

  /// No description provided for @formLabelCurrency.
  ///
  /// In en, this message translates to:
  /// **'CURRENCY'**
  String get formLabelCurrency;

  /// No description provided for @formLabelWhoCanSee.
  ///
  /// In en, this message translates to:
  /// **'WHO CAN SEE THIS?'**
  String get formLabelWhoCanSee;

  /// No description provided for @formSectionDangerZone.
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get formSectionDangerZone;

  /// No description provided for @formLabelDeleteItinerary.
  ///
  /// In en, this message translates to:
  /// **'DELETE ITINERARY'**
  String get formLabelDeleteItinerary;

  /// No description provided for @formDeleteItineraryHint.
  ///
  /// In en, this message translates to:
  /// **'Type the title to confirm'**
  String get formDeleteItineraryHint;

  /// No description provided for @currencySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search currency…'**
  String get currencySearchHint;

  /// No description provided for @currenciesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load currencies: {error}'**
  String currenciesLoadFailed(String error);

  /// No description provided for @deleteItineraryFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete itinerary'**
  String get deleteItineraryFormTitle;

  /// No description provided for @deleteItineraryFormMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{title}\" and all its stops. Type the title to confirm.'**
  String deleteItineraryFormMessage(String title);

  /// No description provided for @followButton.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get followButton;

  /// No description provided for @followingButton.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followingButton;

  /// No description provided for @requestedButton.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requestedButton;

  /// No description provided for @unfollowedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Unfollowed @{username}'**
  String unfollowedSnackbar(String username);

  /// No description provided for @cancelRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel request?'**
  String get cancelRequestTitle;

  /// No description provided for @cancelRequestMessage.
  ///
  /// In en, this message translates to:
  /// **'Cancel your follow request to @{username}?'**
  String cancelRequestMessage(String username);

  /// No description provided for @cancelRequestConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequestConfirm;

  /// No description provided for @cancelRequestKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get cancelRequestKeep;

  /// No description provided for @undoButton.
  ///
  /// In en, this message translates to:
  /// **'UNDO'**
  String get undoButton;

  /// No description provided for @couldNotUndo.
  ///
  /// In en, this message translates to:
  /// **'Could not undo: {error}'**
  String couldNotUndo(String error);

  /// No description provided for @errorNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Please check your network and try again.'**
  String get errorNoInternet;

  /// No description provided for @errorGenericRetry.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again.'**
  String get errorGenericRetry;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'An error occurred.'**
  String get errorGeneric;

  /// No description provided for @fieldHelpTooltip.
  ///
  /// In en, this message translates to:
  /// **'What is this?'**
  String get fieldHelpTooltip;

  /// No description provided for @typeToConfirmInstruction.
  ///
  /// In en, this message translates to:
  /// **'Type \"{text}\" to confirm:'**
  String typeToConfirmInstruction(String text);

  /// No description provided for @daysLabel.
  ///
  /// In en, this message translates to:
  /// **'d'**
  String get daysLabel;

  /// No description provided for @noneOption.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneOption;

  /// No description provided for @discardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Your changes will not be saved.'**
  String get discardChangesMessage;

  /// No description provided for @keepEditingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditingButton;

  /// No description provided for @orderSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Order saved'**
  String get orderSavedMessage;

  /// No description provided for @segmentSelectBothStops.
  ///
  /// In en, this message translates to:
  /// **'Select both a From and a To stop.'**
  String get segmentSelectBothStops;

  /// No description provided for @segmentStopsMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'From and To stops must differ.'**
  String get segmentStopsMustDiffer;

  /// No description provided for @segmentAddLegFirst.
  ///
  /// In en, this message translates to:
  /// **'Add at least one leg before saving.'**
  String get segmentAddLegFirst;

  /// No description provided for @segmentAlreadyExistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Segment already exists'**
  String get segmentAlreadyExistsTitle;

  /// No description provided for @segmentAlreadyExistsMessage.
  ///
  /// In en, this message translates to:
  /// **'A segment already connects these two stops. What do you want to do?'**
  String get segmentAlreadyExistsMessage;

  /// No description provided for @segmentJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get segmentJoin;

  /// No description provided for @segmentReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get segmentReplace;

  /// No description provided for @segmentFromStopLabel.
  ///
  /// In en, this message translates to:
  /// **'From Stop'**
  String get segmentFromStopLabel;

  /// No description provided for @segmentToStopLabel.
  ///
  /// In en, this message translates to:
  /// **'To Stop'**
  String get segmentToStopLabel;

  /// No description provided for @visibilityScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Who can see this?'**
  String get visibilityScreenTitle;

  /// No description provided for @visibilityAddPerson.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get visibilityAddPerson;

  /// No description provided for @visibilitySearchByUsername.
  ///
  /// In en, this message translates to:
  /// **'Search by username…'**
  String get visibilitySearchByUsername;

  /// No description provided for @couldNotLoadRatings.
  ///
  /// In en, this message translates to:
  /// **'Could not load ratings'**
  String get couldNotLoadRatings;

  /// No description provided for @stopNotFound.
  ///
  /// In en, this message translates to:
  /// **'Stop not found.'**
  String get stopNotFound;

  /// No description provided for @mapPickLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick Location'**
  String get mapPickLocationTitle;

  /// No description provided for @mapConfirmLocation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Location'**
  String get mapConfirmLocation;

  /// No description provided for @stopCostHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 20'**
  String get stopCostHint;

  /// No description provided for @ratingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get ratingsTitle;

  /// No description provided for @noRatingsYet.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get noRatingsYet;

  /// No description provided for @ratingsOverallLabel.
  ///
  /// In en, this message translates to:
  /// **'OVERALL'**
  String get ratingsOverallLabel;

  /// No description provided for @rateThisTrip.
  ///
  /// In en, this message translates to:
  /// **'Rate this trip'**
  String get rateThisTrip;

  /// No description provided for @deletedUser.
  ///
  /// In en, this message translates to:
  /// **'Deleted User'**
  String get deletedUser;

  /// No description provided for @annotationContentHint.
  ///
  /// In en, this message translates to:
  /// **'What should travelers know?'**
  String get annotationContentHint;

  /// No description provided for @countryPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select country'**
  String get countryPickerTitle;

  /// No description provided for @countrySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search countries…'**
  String get countrySearchHint;

  /// No description provided for @countryNoneClear.
  ///
  /// In en, this message translates to:
  /// **'None / Clear'**
  String get countryNoneClear;

  /// No description provided for @languageSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search languages…'**
  String get languageSearchHint;

  /// No description provided for @coverChangeButton.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get coverChangeButton;

  /// No description provided for @coverEditCropButton.
  ///
  /// In en, this message translates to:
  /// **'Edit crop'**
  String get coverEditCropButton;

  /// No description provided for @coverAdjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust cover photo'**
  String get coverAdjustTitle;

  /// No description provided for @mdBoldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get mdBoldTooltip;

  /// No description provided for @mdItalicTooltip.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get mdItalicTooltip;

  /// No description provided for @mdHeading1Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get mdHeading1Tooltip;

  /// No description provided for @mdHeading2Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get mdHeading2Tooltip;

  /// No description provided for @mdBulletListTooltip.
  ///
  /// In en, this message translates to:
  /// **'Bullet list'**
  String get mdBulletListTooltip;

  /// No description provided for @mdNumberedListTooltip.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get mdNumberedListTooltip;

  /// No description provided for @mdEditTab.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get mdEditTab;

  /// No description provided for @mdPreviewTab.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get mdPreviewTab;

  /// No description provided for @legCostHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 12.50'**
  String get legCostHint;

  /// No description provided for @addLegButton.
  ///
  /// In en, this message translates to:
  /// **'Add leg'**
  String get addLegButton;

  /// No description provided for @totalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// No description provided for @reorderOrphanTitle.
  ///
  /// In en, this message translates to:
  /// **'Save reorder?'**
  String get reorderOrphanTitle;

  /// No description provided for @reorderOrphanMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} transit segment will be deleted because its stops will no longer be in adjacent tracks:\n\n{segments}} other{{count} transit segments will be deleted because their stops will no longer be in adjacent tracks:\n\n{segments}}}'**
  String reorderOrphanMessage(int count, String segments);

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingLabel;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get usernameRequired;

  /// No description provided for @usernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 4 characters'**
  String get usernameTooShort;

  /// No description provided for @usernameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Username cannot exceed 30 characters'**
  String get usernameTooLong;

  /// No description provided for @usernameInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Letters, numbers, periods and underscores only. Must start with a letter, end with a letter or number.'**
  String get usernameInvalidFormat;

  /// No description provided for @usernameConsecutiveSpecial.
  ///
  /// In en, this message translates to:
  /// **'Cannot have consecutive periods or underscores'**
  String get usernameConsecutiveSpecial;

  /// No description provided for @displayNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Display name cannot exceed 50 characters'**
  String get displayNameTooLong;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailMessage.
  ///
  /// In en, this message translates to:
  /// **'Verify your email to unlock creating trips, rating, and following people.'**
  String get verifyEmailMessage;

  /// No description provided for @verifyEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Verify with Google'**
  String get verifyEmailButton;

  /// No description provided for @emailVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email verified — you\'re all set!'**
  String get emailVerifiedSuccess;

  /// No description provided for @resendVerificationButton.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get resendVerificationButton;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent — check your inbox.'**
  String get verificationEmailSent;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email and we\'ll send you a link to set a new password.'**
  String get forgotPasswordSubtitle;

  /// No description provided for @forgotPasswordEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get forgotPasswordEmailLabel;

  /// No description provided for @forgotPasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get forgotPasswordSubmit;

  /// No description provided for @forgotPasswordSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get forgotPasswordSentTitle;

  /// No description provided for @forgotPasswordSentBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, we\'ve sent a password reset link. Check your inbox and spam folder.'**
  String get forgotPasswordSentBody;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password, then choose a new one. Changing it signs out every other device.'**
  String get changePasswordSubtitle;

  /// No description provided for @changePasswordCurrentLabel.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get changePasswordCurrentLabel;

  /// No description provided for @changePasswordNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get changePasswordNewLabel;

  /// No description provided for @changePasswordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get changePasswordConfirmLabel;

  /// No description provided for @changePasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get changePasswordMismatch;

  /// No description provided for @changePasswordSameAsOld.
  ///
  /// In en, this message translates to:
  /// **'New password must differ from the current one.'**
  String get changePasswordSameAsOld;

  /// No description provided for @changePasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordSubmit;

  /// No description provided for @changePasswordConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This signs you out on all your other devices. Continue?'**
  String get changePasswordConfirmMessage;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Other devices were signed out.'**
  String get changePasswordSuccess;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn;

  /// No description provided for @speaksLabel.
  ///
  /// In en, this message translates to:
  /// **'Speaks'**
  String get speaksLabel;

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeButton;

  /// No description provided for @doneTooltip.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneTooltip;

  /// No description provided for @addButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your account, itineraries, follows, and ratings will be anonymized or deleted per our privacy policy. You will be signed out immediately. This cannot be undone.'**
  String get deleteAccountConfirmMessage;

  /// No description provided for @deleteAccountRequiredText.
  ///
  /// In en, this message translates to:
  /// **'DELETE MY ACCOUNT'**
  String get deleteAccountRequiredText;

  /// No description provided for @deleteAccountConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountConfirmLabel;

  /// No description provided for @deleteAccountPasswordError.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get deleteAccountPasswordError;

  /// No description provided for @deleteAccountGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get deleteAccountGenericError;

  /// No description provided for @deleteAccountCannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone'**
  String get deleteAccountCannotUndo;

  /// No description provided for @deleteAccountWillRemove.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account will permanently remove:'**
  String get deleteAccountWillRemove;

  /// No description provided for @deleteAccountBullet1.
  ///
  /// In en, this message translates to:
  /// **'Your profile and all personal data'**
  String get deleteAccountBullet1;

  /// No description provided for @deleteAccountBullet2.
  ///
  /// In en, this message translates to:
  /// **'All your itineraries and stops'**
  String get deleteAccountBullet2;

  /// No description provided for @deleteAccountBullet3.
  ///
  /// In en, this message translates to:
  /// **'Your follow relationships'**
  String get deleteAccountBullet3;

  /// No description provided for @deleteAccountNote.
  ///
  /// In en, this message translates to:
  /// **'Ratings you gave to other itineraries will be kept anonymously as community data.'**
  String get deleteAccountNote;

  /// No description provided for @deleteAccountEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to confirm'**
  String get deleteAccountEnterPassword;

  /// No description provided for @deleteAccountPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get deleteAccountPasswordLabel;

  /// No description provided for @deleteAccountPasswordHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get deleteAccountPasswordHelpTitle;

  /// No description provided for @deleteAccountPasswordHelpMessage.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password to confirm deletion. Account deletion is permanent and cannot be undone.'**
  String get deleteAccountPasswordHelpMessage;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete My Account'**
  String get deleteAccountButton;

  /// No description provided for @deleteAccountGoogleExplain.
  ///
  /// In en, this message translates to:
  /// **'This account uses Google Sign-In. Re-authenticate with Google to confirm deletion.'**
  String get deleteAccountGoogleExplain;

  /// No description provided for @deleteAccountGoogleButton.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get deleteAccountGoogleButton;

  /// No description provided for @deleteAnnotationTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete annotation?'**
  String get deleteAnnotationTitle;

  /// No description provided for @deleteAnnotationMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove this annotation from the itinerary.'**
  String get deleteAnnotationMessage;

  /// No description provided for @deleteAnnotationStopMessage.
  ///
  /// In en, this message translates to:
  /// **'This annotation will be permanently removed.'**
  String get deleteAnnotationStopMessage;

  /// No description provided for @removeTransitTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove transit between stops?'**
  String get removeTransitTitle;

  /// No description provided for @removeTransitMessage.
  ///
  /// In en, this message translates to:
  /// **'The connection between these two stops will be cleared. You can add a new one later.'**
  String get removeTransitMessage;

  /// No description provided for @reorderTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder tracks'**
  String get reorderTracksTitle;

  /// No description provided for @shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTooltip;

  /// No description provided for @editDetailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit details & image'**
  String get editDetailsTooltip;

  /// No description provided for @descriptionSection.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionSection;

  /// No description provided for @annotationsSection.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get annotationsSection;

  /// No description provided for @addAnnotationButton.
  ///
  /// In en, this message translates to:
  /// **'Add annotation'**
  String get addAnnotationButton;

  /// No description provided for @noAnnotationsYet.
  ///
  /// In en, this message translates to:
  /// **'No annotations yet.'**
  String get noAnnotationsYet;

  /// No description provided for @stopsList.
  ///
  /// In en, this message translates to:
  /// **'Stop list'**
  String get stopsList;

  /// No description provided for @editStopsButton.
  ///
  /// In en, this message translates to:
  /// **'Edit stops'**
  String get editStopsButton;

  /// No description provided for @addStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add stop'**
  String get addStopTooltip;

  /// No description provided for @reorderTracksTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reorder tracks'**
  String get reorderTracksTooltip;

  /// No description provided for @mapSection.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapSection;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in maps'**
  String get openInMaps;

  /// No description provided for @otherMapsApp.
  ///
  /// In en, this message translates to:
  /// **'Other maps app'**
  String get otherMapsApp;

  /// No description provided for @openRouteInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open route in Google Maps'**
  String get openRouteInMaps;

  /// No description provided for @routeTruncated.
  ///
  /// In en, this message translates to:
  /// **'Google Maps can only show the first {count} stops'**
  String routeTruncated(int count);

  /// No description provided for @openStreetMapContributors.
  ///
  /// In en, this message translates to:
  /// **'OpenStreetMap contributors'**
  String get openStreetMapContributors;

  /// No description provided for @poweredByOSM.
  ///
  /// In en, this message translates to:
  /// **'Powered by OpenStreetMap'**
  String get poweredByOSM;

  /// No description provided for @noStopsYetTapPlus.
  ///
  /// In en, this message translates to:
  /// **'No stops yet. Tap + to add one.'**
  String get noStopsYetTapPlus;

  /// No description provided for @communityRating.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get communityRating;

  /// No description provided for @ratingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 rating} other{{count} ratings}}'**
  String ratingCount(int count);

  /// No description provided for @yourRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get yourRating;

  /// No description provided for @rateIt.
  ///
  /// In en, this message translates to:
  /// **'Rate it'**
  String get rateIt;

  /// No description provided for @deleteOrphanSegmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete transit segment?} other{Delete transit segments?}}'**
  String deleteOrphanSegmentsTitle(int count);

  /// No description provided for @deleteOrphanSegmentsMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{There is 1 transit segment connecting these two stops. Adding a stop between them will hide it because the stops will no longer be adjacent. Delete the segment and continue?} other{There are {count} transit segments connecting these two stops. Adding a stop between them will hide them because the stops will no longer be adjacent. Delete the segments and continue?}}'**
  String deleteOrphanSegmentsMessage(int count);

  /// No description provided for @deleteAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Delete & continue'**
  String get deleteAndContinue;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @stopDetailsView.
  ///
  /// In en, this message translates to:
  /// **'Stop Details'**
  String get stopDetailsView;

  /// No description provided for @editStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Stop'**
  String get editStopTitle;

  /// No description provided for @addStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Stop'**
  String get addStopTitle;

  /// No description provided for @editStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit stop'**
  String get editStopTooltip;

  /// No description provided for @duplicateStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate stop'**
  String get duplicateStopTitle;

  /// No description provided for @duplicateStopMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} is already in this itinerary. Add it again anyway?'**
  String duplicateStopMessage(String name);

  /// No description provided for @addAnyway.
  ///
  /// In en, this message translates to:
  /// **'Add anyway'**
  String get addAnyway;

  /// No description provided for @itineraryUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Itinerary updated elsewhere'**
  String get itineraryUpdatedTitle;

  /// No description provided for @itineraryUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'This itinerary was edited from another device. Go back and reload to see the latest version.'**
  String get itineraryUpdatedMessage;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @deleteStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this stop?'**
  String get deleteStopTitle;

  /// No description provided for @deleteStopMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove the stop, its annotations, and any transit segments connected to it. This cannot be undone.'**
  String get deleteStopMessage;

  /// No description provided for @viewOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get viewOnlyTitle;

  /// No description provided for @viewOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap the Edit button to make changes.'**
  String get viewOnlyMessage;

  /// No description provided for @searchForPlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Search for a place'**
  String get searchForPlaceLabel;

  /// No description provided for @searchAPlaceHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Search a place'**
  String get searchAPlaceHelpTitle;

  /// No description provided for @searchAPlaceHelpMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a place, restaurant, or landmark name. Pick a result to autofill the place name, address, and coordinates below.'**
  String get searchAPlaceHelpMessage;

  /// No description provided for @searchPlaceHintText.
  ///
  /// In en, this message translates to:
  /// **'e.g. Eiffel Tower, Paris'**
  String get searchPlaceHintText;

  /// No description provided for @stopDetailsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Stop details'**
  String get stopDetailsSectionLabel;

  /// No description provided for @placeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Place name'**
  String get placeNameLabel;

  /// No description provided for @placeNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Name of the place, restaurant, landmark, or stop.'**
  String get placeNameHelp;

  /// No description provided for @placeNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Place name is required'**
  String get placeNameRequired;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel;

  /// No description provided for @addressHelp.
  ///
  /// In en, this message translates to:
  /// **'Street address or area description. Optional.'**
  String get addressHelp;

  /// No description provided for @coordinatesHelp.
  ///
  /// In en, this message translates to:
  /// **'The map location for this stop. Tap \"Pick on map\" to set or adjust it.'**
  String get coordinatesHelp;

  /// No description provided for @pickOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pick on map'**
  String get pickOnMap;

  /// No description provided for @placeTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Place type'**
  String get placeTypeLabel;

  /// No description provided for @placeTypeHelp.
  ///
  /// In en, this message translates to:
  /// **'What kind of place this is (e.g. eat & drink, sleep, sight). Used for filtering and the map icon.'**
  String get placeTypeHelp;

  /// No description provided for @selectPlaceType.
  ///
  /// In en, this message translates to:
  /// **'Select place type'**
  String get selectPlaceType;

  /// No description provided for @placeTypeEatDrink.
  ///
  /// In en, this message translates to:
  /// **'Eat & Drink'**
  String get placeTypeEatDrink;

  /// No description provided for @placeTypeSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get placeTypeSleep;

  /// No description provided for @placeTypePray.
  ///
  /// In en, this message translates to:
  /// **'Pray'**
  String get placeTypePray;

  /// No description provided for @placeTypeLearnSee.
  ///
  /// In en, this message translates to:
  /// **'Learn & See'**
  String get placeTypeLearnSee;

  /// No description provided for @placeTypeBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get placeTypeBuy;

  /// No description provided for @placeTypePlayWatch.
  ///
  /// In en, this message translates to:
  /// **'Play & Watch'**
  String get placeTypePlayWatch;

  /// No description provided for @placeTypeNature.
  ///
  /// In en, this message translates to:
  /// **'Nature'**
  String get placeTypeNature;

  /// No description provided for @placeTypeTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get placeTypeTransport;

  /// No description provided for @placeTypeHealBathe.
  ///
  /// In en, this message translates to:
  /// **'Heal & Bathe'**
  String get placeTypeHealBathe;

  /// No description provided for @placeTypeEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get placeTypeEntertainment;

  /// No description provided for @placeTypeSight.
  ///
  /// In en, this message translates to:
  /// **'Sight'**
  String get placeTypeSight;

  /// No description provided for @placeTypeHintEatDrink.
  ///
  /// In en, this message translates to:
  /// **'cafe, restaurant, bar, bakery, food truck'**
  String get placeTypeHintEatDrink;

  /// No description provided for @placeTypeHintSleep.
  ///
  /// In en, this message translates to:
  /// **'hotel, hostel, campsite, inn, lodge'**
  String get placeTypeHintSleep;

  /// No description provided for @placeTypeHintPray.
  ///
  /// In en, this message translates to:
  /// **'church, mosque, temple, synagogue, shrine'**
  String get placeTypeHintPray;

  /// No description provided for @placeTypeHintLearnSee.
  ///
  /// In en, this message translates to:
  /// **'museum, gallery, library, aquarium, observatory'**
  String get placeTypeHintLearnSee;

  /// No description provided for @placeTypeHintBuy.
  ///
  /// In en, this message translates to:
  /// **'shop, market, mall, boutique, stall'**
  String get placeTypeHintBuy;

  /// No description provided for @placeTypeHintPlayWatch.
  ///
  /// In en, this message translates to:
  /// **'stadium, gym, arena, court, bowling alley'**
  String get placeTypeHintPlayWatch;

  /// No description provided for @placeTypeHintNature.
  ///
  /// In en, this message translates to:
  /// **'beach, park, forest, mountain, waterfall'**
  String get placeTypeHintNature;

  /// No description provided for @placeTypeHintTransport.
  ///
  /// In en, this message translates to:
  /// **'airport, train station, bus stop, ferry terminal'**
  String get placeTypeHintTransport;

  /// No description provided for @placeTypeHintHealBathe.
  ///
  /// In en, this message translates to:
  /// **'spa, hot spring, pool, sauna, bathhouse'**
  String get placeTypeHintHealBathe;

  /// No description provided for @placeTypeHintEntertainment.
  ///
  /// In en, this message translates to:
  /// **'theater, cinema, concert hall, nightclub'**
  String get placeTypeHintEntertainment;

  /// No description provided for @placeTypeHintSight.
  ///
  /// In en, this message translates to:
  /// **'monument, viewpoint, castle, square, ruin'**
  String get placeTypeHintSight;

  /// No description provided for @recommendedTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recommended time to spend'**
  String get recommendedTimeLabel;

  /// No description provided for @timeToSpendHelp.
  ///
  /// In en, this message translates to:
  /// **'Roughly how long you expect to stay here. Tap to set days, hours, and minutes.'**
  String get timeToSpendHelp;

  /// No description provided for @stopIsFree.
  ///
  /// In en, this message translates to:
  /// **'This stop is free'**
  String get stopIsFree;

  /// No description provided for @freeHelp.
  ///
  /// In en, this message translates to:
  /// **'Toggle on if visiting this place costs nothing.'**
  String get freeHelp;

  /// No description provided for @costLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get costLabel;

  /// No description provided for @costHelp.
  ///
  /// In en, this message translates to:
  /// **'Approximate cost per person, in the itinerary\'s currency.'**
  String get costHelp;

  /// No description provided for @enterValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get enterValidNumber;

  /// No description provided for @thoughtsLabel.
  ///
  /// In en, this message translates to:
  /// **'Thoughts'**
  String get thoughtsLabel;

  /// No description provided for @thoughtsHelp.
  ///
  /// In en, this message translates to:
  /// **'Your personal take on this stop — what to expect, what you loved, things to skip, opening tips. Use the toolbar to add bold, italic, headings, or bullet lists.'**
  String get thoughtsHelp;

  /// No description provided for @annotationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get annotationsLabel;

  /// No description provided for @annotationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Short tagged notes (advice, caution, avoid, info) attached to this stop. Useful for warnings or tips.'**
  String get annotationsHelp;

  /// No description provided for @saveChangesButton.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChangesButton;

  /// No description provided for @addStopButton.
  ///
  /// In en, this message translates to:
  /// **'Add Stop'**
  String get addStopButton;

  /// No description provided for @deleteStopButton.
  ///
  /// In en, this message translates to:
  /// **'Delete Stop'**
  String get deleteStopButton;

  /// No description provided for @timeToSpendModalTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to spend'**
  String get timeToSpendModalTitle;

  /// No description provided for @editTransitTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Transit'**
  String get editTransitTitle;

  /// No description provided for @addTransitTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Transit'**
  String get addTransitTitle;

  /// No description provided for @updateTransitButton.
  ///
  /// In en, this message translates to:
  /// **'Update Transit'**
  String get updateTransitButton;

  /// No description provided for @transportModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get transportModeLabel;

  /// No description provided for @transportModeHelp.
  ///
  /// In en, this message translates to:
  /// **'How you travel on this leg (walk, bus, train, ferry, etc.). Some modes reveal extra fields for line and direction.'**
  String get transportModeHelp;

  /// No description provided for @transitLineLabel.
  ///
  /// In en, this message translates to:
  /// **'Line (optional)'**
  String get transitLineLabel;

  /// No description provided for @transitLineHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. The line number or name (e.g. \"Bus 42\", \"M1\").'**
  String get transitLineHelp;

  /// No description provided for @transitDirectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Direction (optional)'**
  String get transitDirectionLabel;

  /// No description provided for @transitDirectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Where the line is headed (e.g. \"Northbound\", \"Châtelet\").'**
  String get transitDirectionHelp;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get durationLabel;

  /// No description provided for @durationHelp.
  ///
  /// In en, this message translates to:
  /// **'How long this leg takes in hours and minutes.'**
  String get durationHelp;

  /// No description provided for @legCostHelp.
  ///
  /// In en, this message translates to:
  /// **'Approximate cost in the itinerary\'s currency. Disabled when \"Free\" is on.'**
  String get legCostHelp;

  /// No description provided for @hoursLabel.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hoursLabel;

  /// No description provided for @minutesLabel.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesLabel;

  /// No description provided for @freeLegLabel.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeLegLabel;

  /// No description provided for @freeLegHelp.
  ///
  /// In en, this message translates to:
  /// **'Toggle on if this leg costs nothing (walking, included transfer, etc.).'**
  String get freeLegHelp;

  /// No description provided for @legThoughtsLabel.
  ///
  /// In en, this message translates to:
  /// **'Thoughts (optional)'**
  String get legThoughtsLabel;

  /// No description provided for @legThoughtsHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Anything useful to know about this leg — booking tips, transfer instructions, where to sit, ticket cost surprises.'**
  String get legThoughtsHelp;

  /// No description provided for @annotationTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get annotationTypeLabel;

  /// No description provided for @annotationTypeHelp.
  ///
  /// In en, this message translates to:
  /// **'Advice: a helpful tip. Caution: be careful. Avoid: don\'t go. Info: a neutral note.'**
  String get annotationTypeHelp;

  /// No description provided for @annotationAdvice.
  ///
  /// In en, this message translates to:
  /// **'Advice'**
  String get annotationAdvice;

  /// No description provided for @annotationCaution.
  ///
  /// In en, this message translates to:
  /// **'Caution'**
  String get annotationCaution;

  /// No description provided for @annotationAvoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid'**
  String get annotationAvoid;

  /// No description provided for @annotationInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get annotationInfo;

  /// No description provided for @annotationContentLabel.
  ///
  /// In en, this message translates to:
  /// **'Content *'**
  String get annotationContentLabel;

  /// No description provided for @annotationContentHelp.
  ///
  /// In en, this message translates to:
  /// **'Describe your advice, caution, warning, or note in one or two sentences.'**
  String get annotationContentHelp;

  /// No description provided for @annotationContentRequired.
  ///
  /// In en, this message translates to:
  /// **'Content is required'**
  String get annotationContentRequired;

  /// No description provided for @editAnnotationTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit annotation'**
  String get editAnnotationTitle;

  /// No description provided for @addAnnotationDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add annotation'**
  String get addAnnotationDialogTitle;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @moveStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Move stop'**
  String get moveStopTitle;

  /// No description provided for @moveStopDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose an existing track, a gap to create a new track, or extract into its own track. Tracks at the {max}-stop maximum are disabled.'**
  String moveStopDescription(int max);

  /// No description provided for @extractIntoOwnTrack.
  ///
  /// In en, this message translates to:
  /// **'Extract into its own new track'**
  String get extractIntoOwnTrack;

  /// No description provided for @moveButton.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveButton;

  /// No description provided for @moveStopMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved to {destination}'**
  String moveStopMoved(String destination);

  /// No description provided for @itineraryChangedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Itinerary changed elsewhere — close and reopen to see the latest order.'**
  String get itineraryChangedElsewhere;

  /// No description provided for @moveStopOrphan1.
  ///
  /// In en, this message translates to:
  /// **'This is the last stop in its track — the track will be removed from the itinerary.'**
  String get moveStopOrphan1;

  /// No description provided for @moveStopOrphanSegments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 transit segment will be deleted because its stops will no longer be in adjacent tracks.} other{{count} transit segments will be deleted because their stops will no longer be in adjacent tracks.}}'**
  String moveStopOrphanSegments(int count);

  /// No description provided for @moveStopNewTrack.
  ///
  /// In en, this message translates to:
  /// **'New track'**
  String get moveStopNewTrack;

  /// No description provided for @moveStopNewTrackBefore.
  ///
  /// In en, this message translates to:
  /// **'New track before Track {n}'**
  String moveStopNewTrackBefore(int n);

  /// No description provided for @moveStopNewTrackAfter.
  ///
  /// In en, this message translates to:
  /// **'New track after Track {n}'**
  String moveStopNewTrackAfter(int n);

  /// No description provided for @moveStopNewTrackBetween.
  ///
  /// In en, this message translates to:
  /// **'New track between Track {a} and Track {b}'**
  String moveStopNewTrackBetween(int a, int b);

  /// No description provided for @moveStopCurrentSuffix.
  ///
  /// In en, this message translates to:
  /// **'  •  current'**
  String get moveStopCurrentSuffix;

  /// No description provided for @moveStopFull.
  ///
  /// In en, this message translates to:
  /// **'Full {max}/{max}'**
  String moveStopFull(int max);

  /// No description provided for @extractSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Splits this stop out of \"{trackName}\" — new track lands right after.'**
  String extractSubtitle(String trackName);

  /// No description provided for @removeRatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove your rating?'**
  String get removeRatingTitle;

  /// No description provided for @removeRatingMessage.
  ///
  /// In en, this message translates to:
  /// **'Your rating will be deleted and the average will update for everyone viewing this itinerary.'**
  String get removeRatingMessage;

  /// No description provided for @rateItineraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate this itinerary'**
  String get rateItineraryTitle;

  /// No description provided for @overallRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Overall *'**
  String get overallRatingLabel;

  /// No description provided for @overallRatingHelp.
  ///
  /// In en, this message translates to:
  /// **'Required. Your overall rating of this itinerary, from 1 to 5 stars.'**
  String get overallRatingHelp;

  /// No description provided for @ratingThanksMessage.
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your rating helps others.'**
  String get ratingThanksMessage;

  /// No description provided for @yourImpressionLabel.
  ///
  /// In en, this message translates to:
  /// **'Your impression (optional)'**
  String get yourImpressionLabel;

  /// No description provided for @yourImpressionHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Share what stood out — highlights, regrets, who you\'d recommend it to. Use the toolbar to add bold, italic, headings, or bullet lists.'**
  String get yourImpressionHelp;

  /// No description provided for @removeMyRatingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove my rating'**
  String get removeMyRatingTooltip;

  /// No description provided for @wantToShareMore.
  ///
  /// In en, this message translates to:
  /// **'Want to share more? (optional)'**
  String get wantToShareMore;

  /// No description provided for @safetyLabel.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get safetyLabel;

  /// No description provided for @safetyHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. How safe you felt during this trip.'**
  String get safetyHelp;

  /// No description provided for @experienceLabel.
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get experienceLabel;

  /// No description provided for @experienceHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. How enjoyable and memorable the trip was.'**
  String get experienceHelp;

  /// No description provided for @accessibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibilityLabel;

  /// No description provided for @accessibilityHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. How accessible the itinerary is (mobility, language, signage).'**
  String get accessibilityHelp;

  /// No description provided for @familyFriendlyLabel.
  ///
  /// In en, this message translates to:
  /// **'Family-friendly'**
  String get familyFriendlyLabel;

  /// No description provided for @familyFriendlyHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. How suitable the trip is for families with children.'**
  String get familyFriendlyHelp;

  /// No description provided for @crowdednessLabel.
  ///
  /// In en, this message translates to:
  /// **'Uncrowded'**
  String get crowdednessLabel;

  /// No description provided for @crowdednessHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. How uncrowded and spacious it felt — 5 = pleasantly uncrowded, 1 = overcrowded.'**
  String get crowdednessHelp;

  /// Toggle label to reveal hidden optional fields on the stop/itinerary creation form
  ///
  /// In en, this message translates to:
  /// **'Show optional fields'**
  String get showOptionalFields;

  /// Toggle label to hide optional fields again on the stop/itinerary creation form
  ///
  /// In en, this message translates to:
  /// **'Hide optional fields'**
  String get hideOptionalFields;

  /// No description provided for @transportModeWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get transportModeWalk;

  /// No description provided for @transportModeBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get transportModeBus;

  /// No description provided for @transportModeTram.
  ///
  /// In en, this message translates to:
  /// **'Tram'**
  String get transportModeTram;

  /// No description provided for @transportModeMetro.
  ///
  /// In en, this message translates to:
  /// **'Metro'**
  String get transportModeMetro;

  /// No description provided for @transportModeTrain.
  ///
  /// In en, this message translates to:
  /// **'Train'**
  String get transportModeTrain;

  /// No description provided for @transportModeTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get transportModeTaxi;

  /// No description provided for @transportModeUber.
  ///
  /// In en, this message translates to:
  /// **'Uber'**
  String get transportModeUber;

  /// No description provided for @transportModeBike.
  ///
  /// In en, this message translates to:
  /// **'Bike'**
  String get transportModeBike;

  /// No description provided for @transportModeFerry.
  ///
  /// In en, this message translates to:
  /// **'Ferry'**
  String get transportModeFerry;

  /// No description provided for @transportModeCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get transportModeCar;

  /// No description provided for @transportModeAirplane.
  ///
  /// In en, this message translates to:
  /// **'Airplane'**
  String get transportModeAirplane;

  /// No description provided for @dimensionOverall.
  ///
  /// In en, this message translates to:
  /// **'Overall'**
  String get dimensionOverall;

  /// No description provided for @dimensionOverallDesc.
  ///
  /// In en, this message translates to:
  /// **'General impression'**
  String get dimensionOverallDesc;

  /// No description provided for @dimensionSafetyDesc.
  ///
  /// In en, this message translates to:
  /// **'How safe you felt throughout'**
  String get dimensionSafetyDesc;

  /// No description provided for @dimensionExperienceDesc.
  ///
  /// In en, this message translates to:
  /// **'Quality of the overall experience'**
  String get dimensionExperienceDesc;

  /// No description provided for @dimensionAccessibilityDesc.
  ///
  /// In en, this message translates to:
  /// **'Ease of access for all abilities'**
  String get dimensionAccessibilityDesc;

  /// No description provided for @dimensionFamilyFriendlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Suitability for children and families'**
  String get dimensionFamilyFriendlyDesc;

  /// No description provided for @dimensionCrowdednessDesc.
  ///
  /// In en, this message translates to:
  /// **'How uncrowded and spacious it felt'**
  String get dimensionCrowdednessDesc;

  /// No description provided for @dimensionRatingTitle.
  ///
  /// In en, this message translates to:
  /// **'{label} Rating'**
  String dimensionRatingTitle(String label);

  /// No description provided for @noRatingsYetFor.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet for {label}'**
  String noRatingsYetFor(String label);

  /// No description provided for @basedOnRatings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Based on {count} rating} other{Based on {count} ratings}}'**
  String basedOnRatings(int count);

  /// No description provided for @ratersLabel.
  ///
  /// In en, this message translates to:
  /// **'Raters'**
  String get ratersLabel;

  /// No description provided for @annotationAdviceDesc.
  ///
  /// In en, this message translates to:
  /// **'Something useful or pro-tip.'**
  String get annotationAdviceDesc;

  /// No description provided for @annotationCautionDesc.
  ///
  /// In en, this message translates to:
  /// **'Pay attention — surprises possible.'**
  String get annotationCautionDesc;

  /// No description provided for @annotationAvoidDesc.
  ///
  /// In en, this message translates to:
  /// **'Don\'t do this. Save your time.'**
  String get annotationAvoidDesc;

  /// No description provided for @annotationInfoDesc.
  ///
  /// In en, this message translates to:
  /// **'A neutral fact worth knowing.'**
  String get annotationInfoDesc;

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownUser;

  /// No description provided for @timeAgoMonths.
  ///
  /// In en, this message translates to:
  /// **'{count}mo ago'**
  String timeAgoMonths(int count);

  /// No description provided for @timeAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeAgoDays(int count);

  /// No description provided for @timeAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeAgoHours(int count);

  /// No description provided for @timeAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}min ago'**
  String timeAgoMinutes(int count);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @yearsAbbrev.
  ///
  /// In en, this message translates to:
  /// **'y'**
  String get yearsAbbrev;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @transitLabel.
  ///
  /// In en, this message translates to:
  /// **'Transit'**
  String get transitLabel;

  /// No description provided for @noLegsYetTapAdd.
  ///
  /// In en, this message translates to:
  /// **'No legs yet. Tap ＋ to add.'**
  String get noLegsYetTapAdd;

  /// No description provided for @segmentNeedsOneLeg.
  ///
  /// In en, this message translates to:
  /// **'A segment needs at least one leg. Delete the segment instead.'**
  String get segmentNeedsOneLeg;

  /// No description provided for @fromStopName.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String fromStopName(String name);

  /// No description provided for @toStopName.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String toStopName(String name);

  /// No description provided for @visibilityPublicDesc.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link can view.'**
  String get visibilityPublicDesc;

  /// No description provided for @visibilityFollowersDesc.
  ///
  /// In en, this message translates to:
  /// **'Only people who follow you.'**
  String get visibilityFollowersDesc;

  /// No description provided for @visibilityRestrictedDesc.
  ///
  /// In en, this message translates to:
  /// **'Only people you allow.'**
  String get visibilityRestrictedDesc;

  /// No description provided for @visibilityOnlyMeDesc.
  ///
  /// In en, this message translates to:
  /// **'Just you.'**
  String get visibilityOnlyMeDesc;

  /// No description provided for @saveItineraryFirstAllowlist.
  ///
  /// In en, this message translates to:
  /// **'Save the itinerary first, then manage your allowlist from the edit screen.'**
  String get saveItineraryFirstAllowlist;

  /// No description provided for @allowlistLabel.
  ///
  /// In en, this message translates to:
  /// **'Allowlist'**
  String get allowlistLabel;

  /// No description provided for @personCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} person} other{{count} people}}'**
  String personCount(int count);

  /// No description provided for @removedFromAllowlist.
  ///
  /// In en, this message translates to:
  /// **'Removed {name} from allowlist'**
  String removedFromAllowlist(String name);

  /// No description provided for @addPeople.
  ///
  /// In en, this message translates to:
  /// **'Add people'**
  String get addPeople;

  /// No description provided for @otherOption.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherOption;

  /// No description provided for @thisItineraryFallback.
  ///
  /// In en, this message translates to:
  /// **'this itinerary'**
  String get thisItineraryFallback;

  /// No description provided for @discardReorderMessage.
  ///
  /// In en, this message translates to:
  /// **'Your reorder will not be saved.'**
  String get discardReorderMessage;

  /// No description provided for @emptyTrackName.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get emptyTrackName;

  /// No description provided for @unnamedStop.
  ///
  /// In en, this message translates to:
  /// **'(unnamed)'**
  String get unnamedStop;

  /// No description provided for @unknownStop.
  ///
  /// In en, this message translates to:
  /// **'(unknown)'**
  String get unknownStop;

  /// No description provided for @dragToChangeTrackOrder.
  ///
  /// In en, this message translates to:
  /// **'Drag to change the track order'**
  String get dragToChangeTrackOrder;

  /// No description provided for @transitSegmentsWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 transit segment will be deleted} other{{count} transit segments will be deleted}}'**
  String transitSegmentsWillBeDeleted(int count);

  /// No description provided for @andMoreCount.
  ///
  /// In en, this message translates to:
  /// **'… and {count} more'**
  String andMoreCount(int count);

  /// No description provided for @altsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} alt} other{{count} alts}}'**
  String altsCount(int count);

  /// No description provided for @segmentToWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'→ {name}  —  segment will be deleted'**
  String segmentToWillBeDeleted(String name);

  /// No description provided for @reorderAlternativesTitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder alternatives'**
  String get reorderAlternativesTitle;

  /// No description provided for @reorderAlternativesHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to change which option appears first. Tap Save to apply.'**
  String get reorderAlternativesHint;

  /// No description provided for @emptyTrackLabel.
  ///
  /// In en, this message translates to:
  /// **'(empty track)'**
  String get emptyTrackLabel;

  /// No description provided for @moveStopToLabel.
  ///
  /// In en, this message translates to:
  /// **'Move stop to'**
  String get moveStopToLabel;

  /// No description provided for @messageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageLabel;

  /// No description provided for @annotationKeepShortHint.
  ///
  /// In en, this message translates to:
  /// **'Keep it short — under 200 characters reads best on small screens.'**
  String get annotationKeepShortHint;

  /// No description provided for @transportModeSection.
  ///
  /// In en, this message translates to:
  /// **'Transport mode'**
  String get transportModeSection;

  /// No description provided for @lineDirectionSection.
  ///
  /// In en, this message translates to:
  /// **'Line & direction'**
  String get lineDirectionSection;

  /// No description provided for @durationCostSection.
  ///
  /// In en, this message translates to:
  /// **'Duration & cost'**
  String get durationCostSection;

  /// No description provided for @allRatersLabel.
  ///
  /// In en, this message translates to:
  /// **'All raters'**
  String get allRatersLabel;

  /// No description provided for @travelersRatedThis.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} traveler rated this} other{{count} travelers rated this}}'**
  String travelersRatedThis(int count);

  /// No description provided for @byDimensionLabel.
  ///
  /// In en, this message translates to:
  /// **'By dimension'**
  String get byDimensionLabel;

  /// No description provided for @notEnoughRatings.
  ///
  /// In en, this message translates to:
  /// **'Not enough ratings'**
  String get notEnoughRatings;

  /// No description provided for @youRatedThis.
  ///
  /// In en, this message translates to:
  /// **'You rated this'**
  String get youRatedThis;

  /// No description provided for @changeButton.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeButton;

  /// No description provided for @hideReview.
  ///
  /// In en, this message translates to:
  /// **'Hide review'**
  String get hideReview;

  /// No description provided for @readReview.
  ///
  /// In en, this message translates to:
  /// **'Read review'**
  String get readReview;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// No description provided for @viewLess.
  ///
  /// In en, this message translates to:
  /// **'view less'**
  String get viewLess;

  /// No description provided for @viewMore.
  ///
  /// In en, this message translates to:
  /// **'... view more'**
  String get viewMore;

  /// No description provided for @imageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image is too large (max 10 MB).'**
  String get imageTooLarge;

  /// No description provided for @couldNotLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Could not load image. Please try another.'**
  String get couldNotLoadImage;

  /// No description provided for @pinchToZoomHint.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom · Drag to reposition'**
  String get pinchToZoomHint;

  /// No description provided for @addCoverImage.
  ///
  /// In en, this message translates to:
  /// **'Add a cover image'**
  String get addCoverImage;

  /// No description provided for @coverOptionalMapFallback.
  ///
  /// In en, this message translates to:
  /// **'Optional — the map will be used otherwise.'**
  String get coverOptionalMapFallback;

  /// No description provided for @noCoverImage.
  ///
  /// In en, this message translates to:
  /// **'No cover image'**
  String get noCoverImage;

  /// No description provided for @mapTapToPlacePin.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place a pin'**
  String get mapTapToPlacePin;

  /// No description provided for @mapTapToMovePin.
  ///
  /// In en, this message translates to:
  /// **'Tap elsewhere to move the pin, then tap Confirm'**
  String get mapTapToMovePin;

  /// No description provided for @nothingToPreview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview yet.'**
  String get nothingToPreview;

  /// No description provided for @rateOverallFirstHint.
  ///
  /// In en, this message translates to:
  /// **'Rate your overall impression. Once you do, you can share more.'**
  String get rateOverallFirstHint;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Discover & share travel itineraries\ncrafted by real explorers'**
  String get splashTagline;

  /// No description provided for @splashMotto.
  ///
  /// In en, this message translates to:
  /// **'Explore the world, one route at a time'**
  String get splashMotto;

  /// No description provided for @tripsPillLabel.
  ///
  /// In en, this message translates to:
  /// **'trips'**
  String get tripsPillLabel;

  /// No description provided for @stopsPillLabel.
  ///
  /// In en, this message translates to:
  /// **'stops'**
  String get stopsPillLabel;

  /// No description provided for @travelledPillLabel.
  ///
  /// In en, this message translates to:
  /// **'travelled'**
  String get travelledPillLabel;

  /// No description provided for @stopFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopFallbackName;

  /// No description provided for @stopWithNumber.
  ///
  /// In en, this message translates to:
  /// **'Stop {n}'**
  String stopWithNumber(int n);

  /// No description provided for @undoLabel.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoLabel;

  /// No description provided for @updateYourRating.
  ///
  /// In en, this message translates to:
  /// **'Update your rating'**
  String get updateYourRating;

  /// No description provided for @moveActionLabel.
  ///
  /// In en, this message translates to:
  /// **'move'**
  String get moveActionLabel;

  /// No description provided for @reorderActionLabel.
  ///
  /// In en, this message translates to:
  /// **'reorder'**
  String get reorderActionLabel;

  /// No description provided for @aStopFallback.
  ///
  /// In en, this message translates to:
  /// **'A stop'**
  String get aStopFallback;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @noLocationSet.
  ///
  /// In en, this message translates to:
  /// **'No location set'**
  String get noLocationSet;

  /// No description provided for @detailsSection.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsSection;

  /// No description provided for @addLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Add language'**
  String get addLanguageTitle;

  /// No description provided for @alreadyInItinerary.
  ///
  /// In en, this message translates to:
  /// **'{name} is already in this itinerary.'**
  String alreadyInItinerary(String name);

  /// No description provided for @stopNumberOfTotal.
  ///
  /// In en, this message translates to:
  /// **'Stop {n} of {total}'**
  String stopNumberOfTotal(int n, int total);

  /// No description provided for @shareCaption.
  ///
  /// In en, this message translates to:
  /// **'Check out \"{title}\" on Ntripi — {stops}, {duration}'**
  String shareCaption(String title, String stops, String duration);

  /// No description provided for @apiErrorNotAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'You are not signed in.'**
  String get apiErrorNotAuthenticated;

  /// No description provided for @apiErrorAccountDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deactivated.'**
  String get apiErrorAccountDeactivated;

  /// No description provided for @apiErrorEmailUnverified.
  ///
  /// In en, this message translates to:
  /// **'Verify your email via Google to do this.'**
  String get apiErrorEmailUnverified;

  /// No description provided for @apiErrorItineraryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Itinerary not found.'**
  String get apiErrorItineraryNotFound;

  /// No description provided for @apiErrorItineraryNotOwner.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to modify this itinerary.'**
  String get apiErrorItineraryNotOwner;

  /// No description provided for @apiErrorIfMatchRequired.
  ///
  /// In en, this message translates to:
  /// **'This change could not be saved — please reload and try again.'**
  String get apiErrorIfMatchRequired;

  /// No description provided for @apiErrorItineraryStale.
  ///
  /// In en, this message translates to:
  /// **'The itinerary was modified — please reload.'**
  String get apiErrorItineraryStale;

  /// No description provided for @apiErrorWaitlistContactRequired.
  ///
  /// In en, this message translates to:
  /// **'Provide at least an email or a WhatsApp number.'**
  String get apiErrorWaitlistContactRequired;

  /// No description provided for @apiErrorGoogleTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid Google token.'**
  String get apiErrorGoogleTokenInvalid;

  /// No description provided for @apiErrorInvalidGrant.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get apiErrorInvalidGrant;

  /// No description provided for @apiErrorStopNotFound.
  ///
  /// In en, this message translates to:
  /// **'Stop not found.'**
  String get apiErrorStopNotFound;

  /// No description provided for @apiErrorTrackNotFound.
  ///
  /// In en, this message translates to:
  /// **'Track not found, or it doesn\'t belong to this itinerary.'**
  String get apiErrorTrackNotFound;

  /// No description provided for @apiErrorSegmentNotFound.
  ///
  /// In en, this message translates to:
  /// **'Transit segment not found.'**
  String get apiErrorSegmentNotFound;

  /// No description provided for @apiErrorLegNotFound.
  ///
  /// In en, this message translates to:
  /// **'Transport leg not found.'**
  String get apiErrorLegNotFound;

  /// No description provided for @apiErrorItineraryAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this itinerary.'**
  String get apiErrorItineraryAccessDenied;

  /// No description provided for @apiErrorAllowlistRestrictedOnly.
  ///
  /// In en, this message translates to:
  /// **'The allowlist only applies to restricted itineraries.'**
  String get apiErrorAllowlistRestrictedOnly;

  /// No description provided for @apiErrorUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found.'**
  String get apiErrorUserNotFound;

  /// No description provided for @apiErrorAllowlistUserExists.
  ///
  /// In en, this message translates to:
  /// **'This user already has access.'**
  String get apiErrorAllowlistUserExists;

  /// No description provided for @apiErrorAllowlistUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found in the allowlist.'**
  String get apiErrorAllowlistUserNotFound;

  /// No description provided for @apiErrorRankCollision.
  ///
  /// In en, this message translates to:
  /// **'Ordering conflict — please retry.'**
  String get apiErrorRankCollision;

  /// No description provided for @apiErrorAnnotationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Annotation not found.'**
  String get apiErrorAnnotationNotFound;

  /// No description provided for @apiErrorRatingNotFound.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t rated this itinerary.'**
  String get apiErrorRatingNotFound;

  /// No description provided for @apiErrorSegmentAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A segment already connects these two stops.'**
  String get apiErrorSegmentAlreadyExists;

  /// No description provided for @apiErrorIncorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password.'**
  String get apiErrorIncorrectPassword;

  /// No description provided for @apiErrorLoginInvalid.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email/username or password.'**
  String get apiErrorLoginInvalid;

  /// No description provided for @apiErrorCannotFollowSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot follow yourself.'**
  String get apiErrorCannotFollowSelf;

  /// No description provided for @apiErrorNotFollowing.
  ///
  /// In en, this message translates to:
  /// **'You are not following this user.'**
  String get apiErrorNotFollowing;

  /// No description provided for @apiErrorFollowRequestNotFound.
  ///
  /// In en, this message translates to:
  /// **'Follow request not found.'**
  String get apiErrorFollowRequestNotFound;

  /// No description provided for @apiErrorFollowRequestAlreadyAccepted.
  ///
  /// In en, this message translates to:
  /// **'This follow request has already been accepted.'**
  String get apiErrorFollowRequestAlreadyAccepted;

  /// No description provided for @apiErrorCannotRejectRequest.
  ///
  /// In en, this message translates to:
  /// **'You cannot reject this follow request.'**
  String get apiErrorCannotRejectRequest;

  /// No description provided for @apiErrorAccountPrivate.
  ///
  /// In en, this message translates to:
  /// **'This account is private.'**
  String get apiErrorAccountPrivate;

  /// No description provided for @apiErrorTosRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Terms of Service to register.'**
  String get apiErrorTosRequired;

  /// No description provided for @apiErrorUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'This username is already taken.'**
  String get apiErrorUsernameTaken;

  /// No description provided for @apiErrorEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get apiErrorEmailTaken;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
