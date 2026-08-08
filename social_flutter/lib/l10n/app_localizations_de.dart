// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get required => 'Erforderlich';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get dismiss => 'Verwerfen';

  @override
  String get seeAll => 'Alle ansehen';

  @override
  String get back => 'Zurück';

  @override
  String get navSearch => 'Suche';

  @override
  String get navProfile => 'Profil';

  @override
  String get navItineraries => 'Reiserouten';

  @override
  String get navFeed => 'Feed';

  @override
  String get navSaved => 'Gespeichert';

  @override
  String get saveItineraryTooltip => 'Reiseroute speichern';

  @override
  String get unsaveItineraryTooltip => 'Aus Gespeicherten entfernen';

  @override
  String get savedItinerariesTitle => 'Gespeichert';

  @override
  String get noSavedItinerariesYet =>
      'Noch keine gespeicherten Reiserouten. Tippe bei einer beliebigen Reiseroute auf das Lesezeichen, um sie hier zu behalten.';

  @override
  String get searchSavedHint => 'Gespeicherte durchsuchen…';

  @override
  String get savedSearchNoResults =>
      'Keine gespeicherte Reiseroute passt zu deiner Suche.';

  @override
  String get feedTitle => 'Entdecken';

  @override
  String get feedTabTop => 'Top';

  @override
  String get feedTabRecent => 'Neu';

  @override
  String get feedEmpty =>
      'Noch keine öffentlichen Reiserouten. Schau bald wieder vorbei!';

  @override
  String get feedTopEmpty =>
      'Noch nicht genug bewertete Reisen – sieh unter Neu nach.';

  @override
  String get offlineBanner =>
      'Du bist offline! Einige Funktionen sind möglicherweise nicht verfügbar.';

  @override
  String get offlineActionTitle => 'Du bist offline';

  @override
  String get offlineActionMessage =>
      'Ohne Internetverbindung können keine Änderungen vorgenommen werden. Stelle die Verbindung wieder her und versuche es erneut.';

  @override
  String get downloadBanner =>
      'Für ein besseres Erlebnis lade die Ntripi-App herunter.';

  @override
  String get downloadBannerButton => 'Herunterladen';

  @override
  String get loginTitle => 'Willkommen zurück';

  @override
  String get loginSubtitle => 'Melde dich an, um deine Reise fortzusetzen';

  @override
  String get loginEmailLabel => 'E-Mail oder Benutzername';

  @override
  String get loginEmailHelp =>
      'Melde dich mit der E-Mail, mit der du dich registriert hast, oder mit deinem @Benutzernamen an.';

  @override
  String get loginEmailHint => 'du@beispiel.com oder @Benutzername';

  @override
  String get loginPasswordLabel => 'Passwort';

  @override
  String get loginPasswordHelp =>
      'Das Passwort deines Kontos. Tippe auf das Augensymbol, um es ein- oder auszublenden.';

  @override
  String get loginForgotPassword => 'Passwort vergessen?';

  @override
  String get loginSignIn => 'Anmelden';

  @override
  String get loginNoAccount => 'Noch kein Konto? ';

  @override
  String get loginSignUp => 'Registrieren';

  @override
  String get loginOrContinueWith => 'oder weiter mit';

  @override
  String get registerTitle => 'Konto erstellen';

  @override
  String get registerSubtitle =>
      'Schließe dich Tausenden von Entdeckern an, die Routen teilen';

  @override
  String get registerDisplayName => 'Anzeigename';

  @override
  String get registerDisplayNameHelp =>
      'Wie dein Name anderen angezeigt wird. Bis zu 50 Zeichen, jede Sprache und Emojis. Ohne Angabe wird @Benutzername verwendet.';

  @override
  String get registerDisplayNameHint => 'Dein Name';

  @override
  String get registerUsername => 'Benutzername *';

  @override
  String get registerUsernameHelp =>
      'Dein eindeutiger @Name. Nur Kleinbuchstaben, Ziffern und Unterstriche. Er kann später nicht geändert werden.';

  @override
  String get registerUsernameHint => 'deinname';

  @override
  String get registerDob => 'Geburtsdatum *';

  @override
  String get registerDobHelp =>
      'Ntripi ist für Menschen ab 16 Jahren. Wir fragen einmal danach, es erscheint nie in deinem Profil, und andere Nutzer sehen es nie.';

  @override
  String get registerDobHint => 'Geburtsdatum auswählen';

  @override
  String get registerDobRequired => 'Dein Geburtsdatum ist erforderlich.';

  @override
  String registerDobTooYoung(int age) {
    return 'Du musst mindestens $age Jahre alt sein, um Ntripi zu nutzen.';
  }

  @override
  String get dobPickerHelp => 'Geburtsdatum auswählen';

  @override
  String get dobFromGoogle => 'Aus deinem Google-Konto übernommen';

  @override
  String get googleConsentDobLabel => 'Geburtsdatum';

  @override
  String get acceptTermsDobPrompt =>
      'Wir brauchen außerdem dein Geburtsdatum. Ntripi ist für Menschen ab 16 Jahren.';

  @override
  String get errorUnderage =>
      'Du musst mindestens 16 Jahre alt sein, um Ntripi zu nutzen.';

  @override
  String get errorDobRequired =>
      'Zum Fortfahren ist ein Geburtsdatum erforderlich.';

  @override
  String get registerEmail => 'E-Mail *';

  @override
  String get registerEmailHelp =>
      'Wird zum Anmelden und Wiederherstellen deines Kontos verwendet. Wir zeigen sie nie öffentlich an.';

  @override
  String get registerEmailHint => 'du@beispiel.com';

  @override
  String get registerEmailRequired => 'E-Mail ist erforderlich.';

  @override
  String get registerEmailInvalid => 'Bitte gib eine gültige E-Mail ein.';

  @override
  String get registerPassword => 'Passwort *';

  @override
  String get registerPasswordHelp =>
      'Mindestens 8 Zeichen mit mindestens einer Ziffer.';

  @override
  String get registerPasswordHint => 'Mind. 8 Zeichen';

  @override
  String get registerPasswordRequired => 'Passwort ist erforderlich.';

  @override
  String get registerPasswordTooShort => 'Muss mindestens 8 Zeichen lang sein.';

  @override
  String get registerPasswordNoDigit =>
      'Muss mindestens eine Ziffer enthalten.';

  @override
  String get passwordTooLong =>
      'Das Passwort ist zu lang – bis zu 72 Zeichen (weniger bei nicht-lateinischen Buchstaben).';

  @override
  String get registerConfirmPassword => 'Passwort bestätigen *';

  @override
  String get registerConfirmPasswordHelp =>
      'Gib dein Passwort erneut ein, um sicherzustellen, dass es übereinstimmt.';

  @override
  String get registerConfirmRequired => 'Bitte bestätige dein Passwort.';

  @override
  String get registerConfirmMismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get registerTosAgree => 'Ich stimme den ';

  @override
  String get registerTos => 'Nutzungsbedingungen';

  @override
  String get registerTosComma => ', den ';

  @override
  String get registerGuidelines => 'Community-Richtlinien';

  @override
  String get registerTosAnd => ' und der ';

  @override
  String get registerPrivacyPolicy => 'Datenschutzerklärung';

  @override
  String get registerTosSuffix => ' zu. ';

  @override
  String get registerTosProhibited =>
      'Mir ist bewusst, dass anstößige Inhalte und missbräuchliches Verhalten strengstens verboten sind.';

  @override
  String get registerTosHelp =>
      'Du musst den Nutzungsbedingungen, den Community-Richtlinien und der Datenschutzerklärung zustimmen, um ein Konto zu erstellen. Tippe auf die hervorgehobenen Links, um sie zu lesen.';

  @override
  String get registerTosRequired =>
      'Du musst die Nutzungsbedingungen und die Community-Richtlinien akzeptieren.';

  @override
  String get registerTosTitle => 'Nutzungsbedingungen';

  @override
  String get registerGuidelinesTitle => 'Community-Richtlinien';

  @override
  String get legalDocLoadFailed =>
      'Dieses Dokument konnte nicht geladen werden. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get legalDocOpenInBrowser => 'Im Browser öffnen';

  @override
  String get googleTosTitle => 'Nur noch ein Schritt';

  @override
  String get googleTosSubtitle =>
      'Sie legen ein neues Ntripi-Konto an. Bitte nehmen Sie unsere Bedingungen an, um fortzufahren.';

  @override
  String get googleTosAccept => 'Annehmen und fortfahren';

  @override
  String get acceptTermsTitle => 'Unsere Bedingungen haben sich geändert';

  @override
  String get acceptTermsBody =>
      'Wir haben unsere Nutzungsbedingungen, Community-Richtlinien und Datenschutzerklärung aktualisiert. Bitte lesen und akzeptieren Sie sie, um Ntripi weiter zu nutzen.';

  @override
  String get acceptTermsButton => 'Annehmen und fortfahren';

  @override
  String get registerCreateAccount => 'Konto erstellen';

  @override
  String get registerAlreadyHaveAccount => 'Du hast bereits ein Konto? ';

  @override
  String get registerSignIn => 'Anmelden';

  @override
  String get followers => 'Follower';

  @override
  String get following => 'Gefolgt';

  @override
  String get latestTrip => 'LETZTE REISE';

  @override
  String get whereIveBeen => 'WO ICH WAR';

  @override
  String get noStopsYet => 'Noch keine Stopps';

  @override
  String get addFirstStop => 'Ersten Stopp hinzufügen';

  @override
  String get addStopHintTitle => 'Füge deine Stopps hinzu';

  @override
  String get addStopHintMessage =>
      'Um Stopps hinzuzufügen, tippe oben auf Bearbeiten ✎.';

  @override
  String get addCoverHintMessage =>
      'Um ein Titelbild hinzuzufügen, tippe oben auf diese Schaltfläche.';

  @override
  String get longPressEditHintTitle => 'Zum Bearbeiten gedrückt halten';

  @override
  String get longPressEditHintMessage =>
      'Halte einen beliebigen Teil deiner Reise gedrückt — das Titelbild, eine Anmerkung, einen Stopp — um ihn direkt zu bearbeiten.';

  @override
  String get addProfilePhoto => 'Füge ein Profilfoto hinzu';

  @override
  String get addAvatarHintMessage =>
      'Um ein Profilfoto hinzuzufügen, tippe oben auf diese Schaltfläche.';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stopps',
      one: '$count Stopp',
    );
    return '$_temp0';
  }

  @override
  String get expand => 'Ausklappen';

  @override
  String get tapToSeeStops => 'Tippen, um Stopps zu sehen';

  @override
  String get coverImageSection => 'Titelbild';

  @override
  String get coverImageUrlLabel => 'URL des Titelbilds';

  @override
  String get uploadCoverImage => 'Titelbild hochladen';

  @override
  String followRequestsBannerTitle(int count) {
    return 'Follower-Anfragen ($count)';
  }

  @override
  String get tapToReview => 'Tippen zum Prüfen';

  @override
  String get editProfileTooltip => 'Profil bearbeiten';

  @override
  String get settingsTooltip => 'Einstellungen';

  @override
  String get shareProfileTooltip => 'Profil teilen';

  @override
  String get couldNotLoadItineraries =>
      'Reiserouten konnten nicht geladen werden.';

  @override
  String get whereTheyveBeen => 'WO SIE WAREN';

  @override
  String get itinerariesSectionHeader => 'REISEROUTEN';

  @override
  String get noPublicItinerariesYet => 'Noch keine öffentlichen Reiserouten.';

  @override
  String get accountIsPrivateTitle => 'Dieses Konto ist privat';

  @override
  String get followRequestSentTitle => 'Anfrage gesendet';

  @override
  String get followRequestPendingMessage =>
      'Sobald deine Anfrage angenommen wird, siehst du die Reiserouten, Stopps und die Reisekarte.';

  @override
  String followToSeeMessage(String handle) {
    return 'Folge $handle, um ihre Reiserouten, Stopps und Reisekarte zu sehen.';
  }

  @override
  String get editProfileTitle => 'Profil bearbeiten';

  @override
  String get uploadPhoto => 'Foto hochladen';

  @override
  String get identitySection => 'Identität';

  @override
  String get displayNameLabel => 'Anzeigename';

  @override
  String get usernameLabel => 'Benutzername';

  @override
  String get bioLabel => 'BIO';

  @override
  String get bioHelpMessage =>
      'Eine kurze Beschreibung. Unterstützt **fett**-Markdown und Emojis.';

  @override
  String get addBioLabel => 'Füge eine Bio hinzu';

  @override
  String get avatarUrlLabel => 'Avatar-URL';

  @override
  String get travelIdentitySection => 'Reise-Identität';

  @override
  String get passportLabel => 'Reisepass';

  @override
  String get livesInLabel => 'Wohnt in';

  @override
  String get languagesLabel => 'Sprachen';

  @override
  String maxLanguagesReached(int count) {
    return 'Du kannst bis zu $count Sprachen hinzufügen.';
  }

  @override
  String get privacySection => 'Privatsphäre';

  @override
  String get securitySection => 'Sicherheit';

  @override
  String get dangerZoneSection => 'Gefahrenzone';

  @override
  String get privateAccountLabel => 'Privates Konto';

  @override
  String get privateAccountSubtitle =>
      'Nutzer müssen eine Anfrage senden, um dir zu folgen und deine Reiserouten zu sehen.';

  @override
  String get switchToPublicTitle => 'Zu öffentlich wechseln?';

  @override
  String switchToPublicMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Du hast $count offene Follower-Anfragen. Beim Wechsel zu öffentlich werden alle automatisch angenommen. Fortfahren?',
      one:
          'Du hast 1 offene Follower-Anfrage. Beim Wechsel zu öffentlich wird sie automatisch angenommen. Fortfahren?',
    );
    return '$_temp0';
  }

  @override
  String get switchToPublicButton => 'Zu öffentlich wechseln';

  @override
  String get planFirstJourney => 'Plane deine erste Reise';

  @override
  String get planFirstJourneyHint =>
      'Füge Stopps, Transportabschnitte und Notizen hinzu. Teile sie mit Freunden oder behalte sie privat.';

  @override
  String get createItinerary => 'Reiseroute erstellen';

  @override
  String get needInspiration => 'Brauchst du Inspiration?';

  @override
  String get browseForIdeas => 'Durchstöbere den Community-Feed nach Ideen.';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsNotifications => 'Benachrichtigungen';

  @override
  String get settingsNotificationsOn => 'An';

  @override
  String get settingsNotificationsOff => 'Aus';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsHelpCenter => 'Hilfecenter';

  @override
  String get settingsAbout => 'Über Ntripi';

  @override
  String get settingsTerms => 'Nutzung & Datenschutz';

  @override
  String get settingsLogout => 'Abmelden';

  @override
  String get settingsDeleteAccount => 'Konto löschen';

  @override
  String get logoutConfirmTitle => 'Abmelden';

  @override
  String get logoutConfirmMessage => 'Möchtest du dich wirklich abmelden?';

  @override
  String get logoutConfirmButton => 'Abmelden';

  @override
  String get languagePickerTitle => 'Sprache';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageChinese => '简体中文';

  @override
  String get themePickerTitle => 'Design';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get followRequestsTitle => 'Follower-Anfragen';

  @override
  String get noRequests => 'Keine offenen Anfragen';

  @override
  String requestsCountLabel(int count) {
    return 'Anfragen · $count';
  }

  @override
  String get acceptButton => 'Annehmen';

  @override
  String get rejectButton => 'Ablehnen';

  @override
  String followersTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Follower',
      zero: 'Follower',
    );
    return '$_temp0';
  }

  @override
  String followingTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gefolgt',
      zero: 'Gefolgt',
    );
    return '$_temp0';
  }

  @override
  String followRequestsSectionLabel(int count) {
    return 'Follower-Anfragen · $count';
  }

  @override
  String get allFollowersSection => 'Alle Follower';

  @override
  String get noFollowersYet => 'Noch keine Follower.';

  @override
  String get notFollowingAnyone => 'Du folgst noch niemandem.';

  @override
  String get peopleYouFollow => 'Personen, denen du folgst';

  @override
  String get confirmButton => 'Bestätigen';

  @override
  String get searchPeoplePlaceholder => 'Personen suchen…';

  @override
  String get searchForPeople => 'Suche nach Personen, denen du folgen kannst';

  @override
  String get noUsersFound => 'Keine Benutzer gefunden.';

  @override
  String searchResultsCount(int count) {
    return 'Ergebnisse · $count';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Follower',
      one: '$count Follower',
    );
    return '$_temp0';
  }

  @override
  String get searchUsersHelp =>
      'Finde Personen über ihren @Benutzernamen oder ihren Anzeigenamen. Tippe auf ein Ergebnis, um das Profil anzusehen.';

  @override
  String get myItineraries => 'Meine Reiserouten';

  @override
  String get noItinerariesYet => 'Noch keine Reiserouten.';

  @override
  String get tapToCreateFirst =>
      'Tippe auf +, um deine erste Reise zu erstellen.';

  @override
  String get deleteItineraryTitle => 'Diese Reiseroute löschen?';

  @override
  String get deleteItineraryMessage =>
      'Alle Stopps, Anmerkungen, Abschnitte, Bewertungen und geteilten Links werden dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get deleteItineraryButton => 'Reiseroute löschen';

  @override
  String get newItinerary => 'Neue Reiseroute';

  @override
  String get editItinerary => 'Reiseroute bearbeiten';

  @override
  String get coverImageLabel => 'Titelbild';

  @override
  String get coverImageHelp =>
      'Ein 1200×630-Bild, das auf der Reiseroutenkarte und in Link-Vorschauen angezeigt wird. Ziehe im Zuschneidefeld, um es neu zu positionieren.';

  @override
  String get itineraryTitleLabel => 'Titel *';

  @override
  String get itineraryTitleHint => 'z. B. 10 Tage in Kyoto & Osaka';

  @override
  String get itineraryTitleHelp =>
      'Ein kurzer, klarer Name für diese Reise. Wird auf der Reiseroutenkarte und in Teilen-Vorschauen angezeigt.';

  @override
  String get itineraryTitleRequired => 'Titel ist erforderlich';

  @override
  String get descriptionLabel => 'Beschreibung';

  @override
  String get descriptionHelp =>
      'Optional. Eine Zusammenfassung der Reise. Nutze die Symbolleiste, um Text fett oder kursiv zu machen, Überschriften hinzuzufügen und Aufzählungs- oder nummerierte Listen zu erstellen. Wechsle zum Tab Vorschau, um zu sehen, wie es für Leser aussieht.';

  @override
  String get addDescriptionLabel => 'Füge eine Beschreibung hinzu';

  @override
  String get currencyLabel => 'Währung';

  @override
  String get currencyHelp =>
      'Standardwährung für alle Stopp- und Transportkosten in dieser Reiseroute.';

  @override
  String get visibilityLabel => 'Sichtbarkeit';

  @override
  String get visibilityHelp =>
      'Öffentlich: jeder kann es sehen. Follower: nur Personen, die dir folgen. Eingeschränkt: nur die von dir erlaubten Nutzer. Nur ich: privat für dich.';

  @override
  String get visibilityPublic => 'Öffentlich';

  @override
  String get visibilityFollowers => 'Follower';

  @override
  String get visibilityRestricted => 'Eingeschränkt';

  @override
  String get visibilityOnlyMe => 'Nur ich';

  @override
  String get imageSaveButUploadFailed =>
      'Reiseroute gespeichert, aber der Bild-Upload ist fehlgeschlagen. Versuche es erneut über den Bearbeitungsbildschirm.';

  @override
  String get formSectionBasics => 'GRUNDLAGEN';

  @override
  String get formLabelCurrency => 'WÄHRUNG';

  @override
  String get formLabelWhoCanSee => 'WER KANN DAS SEHEN?';

  @override
  String get formSectionDangerZone => 'GEFAHRENZONE';

  @override
  String get formLabelDeleteItinerary => 'REISEROUTE LÖSCHEN';

  @override
  String get formDeleteItineraryHint => 'Gib zur Bestätigung den Titel ein';

  @override
  String get currencySearchHint => 'Währung suchen…';

  @override
  String get bestTimeToVisit => 'Beste Reisezeit';

  @override
  String get addBestTimeToVisit => 'Beste Reisezeit hinzufügen';

  @override
  String get formLabelBestTime => 'BESTE REISEZEIT';

  @override
  String get periodNotSet => 'Nicht angegeben';

  @override
  String get periodSectionMonths => 'BESTE MONATE';

  @override
  String get periodSectionWindows => 'ZEITRÄUME';

  @override
  String get periodSectionWeekdays => 'WOCHENTAGE';

  @override
  String get periodSectionWhy => 'WARUM DIESE ZEIT?';

  @override
  String get periodMonthsHelp =>
      'Tippe jeden Monat an, der sich für die Reise lohnt. Benachbarte Monate werden zu einem Zeitraum.';

  @override
  String get periodNoMonthsSelected => 'Noch keine Monate gewählt';

  @override
  String get periodExactDays => 'Genaue Tage';

  @override
  String get periodStartsOn => 'Beginnt am';

  @override
  String get periodEndsOn => 'Endet am';

  @override
  String get periodWholeMonth => 'Ganzer Monat';

  @override
  String get periodWeekdays => 'Wochentags';

  @override
  String get periodWeekends => 'Am Wochenende';

  @override
  String get periodWhyHint =>
      'z. B. Kirschblüte, mildes Wetter, weniger Andrang';

  @override
  String get periodClear => 'Löschen';

  @override
  String get periodClearConfirmTitle => 'Beste Reisezeit löschen?';

  @override
  String get periodClearConfirmMessage =>
      'Die gewählten Monate, genauen Tage, Wochentage und die Notiz werden alle entfernt.';

  @override
  String currenciesLoadFailed(String error) {
    return 'Währungen konnten nicht geladen werden: $error';
  }

  @override
  String get deleteItineraryFormTitle => 'Reiseroute löschen';

  @override
  String deleteItineraryFormMessage(String title) {
    return 'Dadurch werden \"$title\" und alle zugehörigen Stopps dauerhaft gelöscht. Gib den Titel ein, um zu bestätigen.';
  }

  @override
  String get followButton => 'Folgen';

  @override
  String get followingButton => 'Gefolgt';

  @override
  String get requestedButton => 'Angefragt';

  @override
  String unfollowTitle(String username) {
    return '@$username nicht mehr folgen?';
  }

  @override
  String get unfollowMessage =>
      'Du siehst deren Reiserouten dann nicht mehr in deinem Feed.';

  @override
  String get unfollowConfirm => 'Nicht mehr folgen';

  @override
  String get unfollowKeep => 'Weiter folgen';

  @override
  String unfollowedSnackbar(String username) {
    return '@$username nicht mehr gefolgt';
  }

  @override
  String get cancelRequestTitle => 'Anfrage zurückziehen?';

  @override
  String cancelRequestMessage(String username) {
    return 'Deine Follower-Anfrage an @$username zurückziehen?';
  }

  @override
  String get cancelRequestConfirm => 'Anfrage zurückziehen';

  @override
  String get cancelRequestKeep => 'Behalten';

  @override
  String get declineRequestTitle => 'Anfrage ablehnen?';

  @override
  String declineRequestMessage(String username) {
    return 'Follower-Anfrage von @$username ablehnen? Diese Person kann später eine neue senden.';
  }

  @override
  String get declineRequestConfirm => 'Ablehnen';

  @override
  String get undoButton => 'RÜCKGÄNGIG';

  @override
  String couldNotUndo(String error) {
    return 'Rückgängig machen fehlgeschlagen: $error';
  }

  @override
  String get errorNoInternet =>
      'Keine Internetverbindung. Bitte prüfe dein Netzwerk und versuche es erneut.';

  @override
  String get errorGenericRetry =>
      'Ein Fehler ist aufgetreten. Bitte versuche es erneut.';

  @override
  String get errorGeneric => 'Ein Fehler ist aufgetreten.';

  @override
  String get fieldHelpTooltip => 'Was ist das?';

  @override
  String typeToConfirmInstruction(String text) {
    return 'Gib zur Bestätigung \"$text\" ein:';
  }

  @override
  String get daysLabel => 'T';

  @override
  String get noneOption => 'Keine';

  @override
  String get discardButton => 'Verwerfen';

  @override
  String get discardChangesTitle => 'Änderungen verwerfen?';

  @override
  String get discardChangesMessage =>
      'Deine Änderungen werden nicht gespeichert.';

  @override
  String get keepEditingButton => 'Weiter bearbeiten';

  @override
  String get orderSavedMessage => 'Reihenfolge gespeichert';

  @override
  String get segmentSelectBothStops =>
      'Wähle einen Start- und einen Zielstopp aus.';

  @override
  String get segmentStopsMustDiffer =>
      'Start- und Zielstopp müssen unterschiedlich sein.';

  @override
  String get segmentAddLegFirst =>
      'Füge vor dem Speichern mindestens eine Etappe hinzu.';

  @override
  String get segmentAlreadyExistsTitle => 'Abschnitt existiert bereits';

  @override
  String get segmentAlreadyExistsMessage =>
      'Ein Abschnitt verbindet diese beiden Stopps bereits. Was möchtest du tun?';

  @override
  String get segmentJoin => 'Zusammenführen';

  @override
  String get segmentReplace => 'Ersetzen';

  @override
  String get segmentFromStopLabel => 'Startstopp';

  @override
  String get segmentToStopLabel => 'Zielstopp';

  @override
  String get visibilityScreenTitle => 'Wer kann das sehen?';

  @override
  String get visibilityAddPerson => 'Person hinzufügen';

  @override
  String get visibilitySearchByUsername => 'Nach Benutzername suchen…';

  @override
  String get couldNotLoadRatings => 'Bewertungen konnten nicht geladen werden';

  @override
  String get stopNotFound => 'Stopp nicht gefunden.';

  @override
  String get mapPickLocationTitle => 'Ort auswählen';

  @override
  String get mapConfirmLocation => 'Ort bestätigen';

  @override
  String get stopCostHint => 'z. B. 20';

  @override
  String get ratingsTitle => 'Bewertungen';

  @override
  String get noRatingsYet => 'Noch keine Bewertungen';

  @override
  String get ratingsOverallLabel => 'GESAMT';

  @override
  String get rateThisTrip => 'Diese Reise bewerten';

  @override
  String get editYourItinerary => 'Bearbeite deine Reiseroute';

  @override
  String get deletedUser => 'Gelöschter Benutzer';

  @override
  String get annotationContentHint => 'Was sollten Reisende wissen?';

  @override
  String get countryPickerTitle => 'Land auswählen';

  @override
  String get countrySearchHint => 'Länder suchen…';

  @override
  String get countryNoneClear => 'Keins / Löschen';

  @override
  String get languageSearchHint => 'Sprachen suchen…';

  @override
  String get coverChangeButton => 'Ändern';

  @override
  String get coverEditCropButton => 'Zuschnitt bearbeiten';

  @override
  String get coverAdjustTitle => 'Titelbild anpassen';

  @override
  String get mdBoldTooltip => 'Fett';

  @override
  String get mdItalicTooltip => 'Kursiv';

  @override
  String get mdHeading1Tooltip => 'Überschrift 1';

  @override
  String get mdHeading2Tooltip => 'Überschrift 2';

  @override
  String get mdBulletListTooltip => 'Aufzählungsliste';

  @override
  String get mdNumberedListTooltip => 'Nummerierte Liste';

  @override
  String get mdEditTab => 'Bearbeiten';

  @override
  String get mdPreviewTab => 'Vorschau';

  @override
  String get legCostHint => 'z. B. 12,50';

  @override
  String get addLegButton => 'Etappe hinzufügen';

  @override
  String get totalLabel => 'Gesamt';

  @override
  String get reorderOrphanTitle => 'Neue Reihenfolge speichern?';

  @override
  String reorderOrphanMessage(int count, String segments) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Transportabschnitte werden gelöscht, weil ihre Stopps nicht mehr in benachbarten Spalten liegen:\n\n$segments',
      one:
          '$count Transportabschnitt wird gelöscht, weil seine Stopps nicht mehr in benachbarten Spalten liegen:\n\n$segments',
    );
    return '$_temp0';
  }

  @override
  String get loadingLabel => 'Wird geladen…';

  @override
  String get usernameRequired => 'Benutzername ist erforderlich';

  @override
  String get usernameTooShort =>
      'Der Benutzername muss mindestens 4 Zeichen lang sein';

  @override
  String get usernameTooLong =>
      'Der Benutzername darf höchstens 30 Zeichen lang sein';

  @override
  String get usernameInvalidFormat =>
      'Nur Buchstaben, Zahlen, Punkte und Unterstriche. Muss mit einem Buchstaben beginnen und mit einem Buchstaben oder einer Zahl enden.';

  @override
  String get usernameConsecutiveSpecial =>
      'Keine aufeinanderfolgenden Punkte oder Unterstriche erlaubt';

  @override
  String get displayNameTooLong =>
      'Der Anzeigename darf höchstens 50 Zeichen lang sein';

  @override
  String get comingSoon => 'Demnächst verfügbar';

  @override
  String get verifyEmailTitle => 'Bestätige deine E-Mail';

  @override
  String get verifyEmailMessage =>
      'Bestätige deine E-Mail, um das Erstellen von Reisen, Bewerten und Folgen von Personen freizuschalten.';

  @override
  String get verifyEmailButton => 'Mit Google bestätigen';

  @override
  String get emailVerifiedSuccess => 'E-Mail bestätigt – alles bereit!';

  @override
  String get resendVerificationButton => 'Bestätigungs-E-Mail erneut senden';

  @override
  String get verificationEmailSent =>
      'Bestätigungs-E-Mail gesendet – sieh in deinem Posteingang nach.';

  @override
  String get forgotPasswordTitle => 'Passwort zurücksetzen';

  @override
  String get forgotPasswordSubtitle =>
      'Gib die E-Mail deines Kontos ein und wir senden dir einen Link, um ein neues Passwort festzulegen.';

  @override
  String get forgotPasswordEmailLabel => 'E-Mail';

  @override
  String get forgotPasswordSubmit => 'Link zum Zurücksetzen senden';

  @override
  String get forgotPasswordSentTitle => 'Sieh in deiner E-Mail nach';

  @override
  String get forgotPasswordSentBody =>
      'Falls ein Konto mit dieser E-Mail existiert, haben wir einen Link zum Zurücksetzen des Passworts gesendet. Prüfe deinen Posteingang und den Spam-Ordner.';

  @override
  String get changePasswordTitle => 'Passwort ändern';

  @override
  String get changePasswordSubtitle =>
      'Gib dein aktuelles Passwort ein und wähle dann ein neues. Beim Ändern wirst du auf allen anderen Geräten abgemeldet.';

  @override
  String get changePasswordCurrentLabel => 'Aktuelles Passwort';

  @override
  String get changePasswordNewLabel => 'Neues Passwort';

  @override
  String get changePasswordConfirmLabel => 'Neues Passwort bestätigen';

  @override
  String get changePasswordMismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get changePasswordSameAsOld =>
      'Das neue Passwort muss sich vom aktuellen unterscheiden.';

  @override
  String get changePasswordSubmit => 'Passwort ändern';

  @override
  String get changePasswordConfirmMessage =>
      'Dadurch wirst du auf allen anderen Geräten abgemeldet. Fortfahren?';

  @override
  String get changePasswordSuccess =>
      'Passwort geändert. Andere Geräte wurden abgemeldet.';

  @override
  String get backToSignIn => 'Zurück zur Anmeldung';

  @override
  String get speaksLabel => 'Spricht';

  @override
  String get removeButton => 'Entfernen';

  @override
  String get doneTooltip => 'Fertig';

  @override
  String get addButton => 'Hinzufügen';

  @override
  String get deleteButton => 'Löschen';

  @override
  String get deleteAccountTitle => 'Konto löschen';

  @override
  String get deleteAccountConfirmTitle => 'Dein Konto löschen?';

  @override
  String get deleteAccountConfirmMessage =>
      'Dein Konto, deine Reiserouten, Follows und Bewertungen werden gemäß unserer Datenschutzerklärung anonymisiert oder gelöscht. Du wirst sofort abgemeldet. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountRequiredText => 'MEIN KONTO LÖSCHEN';

  @override
  String get deleteAccountConfirmLabel => 'Mein Konto löschen';

  @override
  String get deleteAccountPasswordError =>
      'Falsches Passwort. Bitte versuche es erneut.';

  @override
  String get deleteAccountGenericError =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get deleteAccountCannotUndo =>
      'Dies kann nicht rückgängig gemacht werden';

  @override
  String get deleteAccountWillRemove =>
      'Das Löschen deines Kontos entfernt dauerhaft:';

  @override
  String get deleteAccountBullet1 => 'Dein Profil und alle persönlichen Daten';

  @override
  String get deleteAccountBullet2 => 'Alle deine Reiserouten und Stopps';

  @override
  String get deleteAccountBullet3 => 'Deine Follow-Beziehungen';

  @override
  String get deleteAccountNote =>
      'Bewertungen, die du für andere Reiserouten abgegeben hast, werden anonym als Community-Daten behalten.';

  @override
  String get deleteAccountEnterPassword =>
      'Gib zur Bestätigung dein Passwort ein';

  @override
  String get deleteAccountEnterPasswordError =>
      'Bitte gib dein Passwort ein, um fortzufahren.';

  @override
  String get deleteAccountPasswordLabel => 'Passwort';

  @override
  String get deleteAccountPasswordHelpTitle => 'Passwort bestätigen';

  @override
  String get deleteAccountPasswordHelpMessage =>
      'Gib dein Passwort erneut ein, um das Löschen zu bestätigen. Das Löschen des Kontos ist endgültig und kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountButton => 'Mein Konto löschen';

  @override
  String get deleteAccountGoogleExplain =>
      'Dieses Konto verwendet die Google-Anmeldung. Authentifiziere dich erneut mit Google, um das Löschen zu bestätigen.';

  @override
  String get deleteAccountGoogleButton => 'Mit Google fortfahren';

  @override
  String get deleteAccountOrDivider => 'ODER';

  @override
  String get deleteAccountGoogleAlternative =>
      'Lieber Google? Authentifiziere dich stattdessen erneut mit Google.';

  @override
  String get deleteAnnotationTitle => 'Anmerkung löschen?';

  @override
  String get deleteAnnotationMessage =>
      'Dadurch wird diese Anmerkung dauerhaft aus der Reiseroute entfernt.';

  @override
  String get deleteAnnotationStopMessage =>
      'Diese Anmerkung wird dauerhaft entfernt.';

  @override
  String get removeTransitTitle => 'Transport zwischen Stopps entfernen?';

  @override
  String get removeTransitMessage =>
      'Die Verbindung zwischen diesen beiden Stopps wird gelöscht. Du kannst später eine neue hinzufügen.';

  @override
  String get reorderTracksTitle => 'Spalten neu anordnen';

  @override
  String get shareTooltip => 'Teilen';

  @override
  String get editDetailsTooltip => 'Details & Bild bearbeiten';

  @override
  String get descriptionSection => 'Beschreibung';

  @override
  String get annotationsSection => 'Anmerkungen';

  @override
  String get addAnnotationButton => 'Anmerkung hinzufügen';

  @override
  String get noAnnotationsYet => 'Noch keine Anmerkungen.';

  @override
  String get stopsList => 'Stoppliste';

  @override
  String get editStopsButton => 'Stopps bearbeiten';

  @override
  String get addStopTooltip => 'Stopp hinzufügen';

  @override
  String get reorderTracksTooltip => 'Spalten neu anordnen';

  @override
  String get mapSection => 'Karte';

  @override
  String get openInMaps => 'In Karten öffnen';

  @override
  String get otherMapsApp => 'Andere Karten-App';

  @override
  String get openRouteInMaps => 'Route in Google Maps öffnen';

  @override
  String routeTruncated(int count) {
    return 'Google Maps kann nur die ersten $count Stopps anzeigen';
  }

  @override
  String get openStreetMapContributors => 'OpenStreetMap-Mitwirkende';

  @override
  String get poweredByOSM => 'Bereitgestellt von OpenStreetMap';

  @override
  String get noStopsYetTapPlus =>
      'Noch keine Stopps. Tippe auf +, um einen hinzuzufügen.';

  @override
  String get communityRating => 'Community';

  @override
  String ratingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bewertungen',
      one: '1 Bewertung',
    );
    return '$_temp0';
  }

  @override
  String get yourRating => 'Deine Bewertung';

  @override
  String get rateIt => 'Bewerten';

  @override
  String deleteOrphanSegmentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Transportabschnitte löschen?',
      one: 'Transportabschnitt löschen?',
    );
    return '$_temp0';
  }

  @override
  String deleteOrphanSegmentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Es gibt $count Transportabschnitte, die diese beiden Stopps verbinden. Wenn du einen Stopp dazwischen einfügst, werden sie ausgeblendet, weil die Stopps nicht mehr benachbart sind. Abschnitte löschen und fortfahren?',
      one:
          'Es gibt 1 Transportabschnitt, der diese beiden Stopps verbindet. Wenn du einen Stopp dazwischen einfügst, wird er ausgeblendet, weil die Stopps nicht mehr benachbart sind. Abschnitt löschen und fortfahren?',
    );
    return '$_temp0';
  }

  @override
  String get deleteAndContinue => 'Löschen & fortfahren';

  @override
  String get notSet => 'Nicht festgelegt';

  @override
  String get stopDetailsView => 'Stopp-Details';

  @override
  String get editStopTitle => 'Stopp bearbeiten';

  @override
  String get addStopTitle => 'Stopp hinzufügen';

  @override
  String get editStopTooltip => 'Stopp bearbeiten';

  @override
  String get duplicateStopTitle => 'Doppelter Stopp';

  @override
  String duplicateStopMessage(String name) {
    return '$name ist bereits in dieser Reiseroute. Trotzdem erneut hinzufügen?';
  }

  @override
  String get addAnyway => 'Trotzdem hinzufügen';

  @override
  String get itineraryUpdatedTitle => 'Reiseroute anderswo aktualisiert';

  @override
  String get itineraryUpdatedMessage =>
      'Diese Reiseroute wurde von einem anderen Gerät bearbeitet. Gehe zurück und lade neu, um die neueste Version zu sehen.';

  @override
  String get goBack => 'Zurück';

  @override
  String get deleteStopTitle => 'Diesen Stopp löschen?';

  @override
  String get deleteStopMessage =>
      'Dadurch werden der Stopp, seine Anmerkungen und alle damit verbundenen Transportabschnitte entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get viewOnlyTitle => 'Nur ansehen';

  @override
  String get viewOnlyMessage =>
      'Tippe auf die Schaltfläche Bearbeiten, um Änderungen vorzunehmen.';

  @override
  String get searchForPlaceLabel => 'Nach einem Ort suchen';

  @override
  String get searchAPlaceHelpTitle => 'Einen Ort suchen';

  @override
  String get searchAPlaceHelpMessage =>
      'Gib den Namen eines Ortes, Restaurants oder einer Sehenswürdigkeit ein. Wähle ein Ergebnis, um Ortsname, Adresse und Koordinaten unten automatisch auszufüllen.';

  @override
  String get searchPlaceHintText => 'z. B. Eiffelturm, Paris';

  @override
  String get stopDetailsSectionLabel => 'Stopp-Details';

  @override
  String get placeNameLabel => 'Ortsname';

  @override
  String get placeNameHelp =>
      'Name des Ortes, Restaurants, der Sehenswürdigkeit oder des Stopps.';

  @override
  String get placeNameRequired => 'Ortsname ist erforderlich';

  @override
  String get addressLabel => 'Adresse';

  @override
  String get addressHelp =>
      'Straßenadresse oder Gebietsbeschreibung. Optional.';

  @override
  String get mapLinkLabel => 'Google-Maps-Link';

  @override
  String get mapLinkHint => 'Füge einen Google-Maps-Link ein';

  @override
  String get mapLinkInvalid => 'Gib einen gültigen Google-Maps-Link ein';

  @override
  String get mapLinkPaste => 'Einfügen';

  @override
  String get mapLinkClear => 'Löschen';

  @override
  String get locationModeCoordinates => 'Koordinaten';

  @override
  String get locationModeMapLink => 'Google-Maps-Link';

  @override
  String get linkPreviewOpensInMaps => 'Öffnet in Google Maps';

  @override
  String get linkPreviewLoading => 'Vorschau wird geladen…';

  @override
  String get linkPreviewTitleCopied => 'Titel kopiert';

  @override
  String get linkPreviewMapMobileOnly =>
      'Kartenvorschau in der mobilen App verfügbar';

  @override
  String get coordinatesHelp =>
      'Der Kartenstandort für diesen Stopp. Tippe auf \"Auf Karte auswählen\", um ihn festzulegen oder anzupassen.';

  @override
  String get pickOnMap => 'Auf Karte auswählen';

  @override
  String get placeTypeLabel => 'Ortstyp';

  @override
  String get placeTypeHelp =>
      'Welche Art von Ort das ist (z. B. Essen & Trinken, Schlafen, Sehenswürdigkeit). Wird zum Filtern und für das Kartensymbol verwendet.';

  @override
  String get selectPlaceType => 'Ortstyp auswählen';

  @override
  String get placeTypeEatDrink => 'Essen & Trinken';

  @override
  String get placeTypeSleep => 'Schlafen';

  @override
  String get placeTypePray => 'Beten';

  @override
  String get placeTypeLearnSee => 'Lernen & Sehen';

  @override
  String get placeTypeBuy => 'Einkaufen';

  @override
  String get placeTypePlayWatch => 'Spielen & Zuschauen';

  @override
  String get placeTypeNature => 'Natur';

  @override
  String get placeTypeTransport => 'Transport';

  @override
  String get placeTypeHealBathe => 'Heilen & Baden';

  @override
  String get placeTypeEntertainment => 'Unterhaltung';

  @override
  String get placeTypeSight => 'Sehenswürdigkeit';

  @override
  String get placeTypeHintEatDrink =>
      'Café, Restaurant, Bar, Bäckerei, Foodtruck';

  @override
  String get placeTypeHintSleep =>
      'Hotel, Hostel, Campingplatz, Gasthaus, Lodge';

  @override
  String get placeTypeHintPray => 'Kirche, Moschee, Tempel, Synagoge, Schrein';

  @override
  String get placeTypeHintLearnSee =>
      'Museum, Galerie, Bibliothek, Aquarium, Sternwarte';

  @override
  String get placeTypeHintBuy =>
      'Geschäft, Markt, Einkaufszentrum, Boutique, Stand';

  @override
  String get placeTypeHintPlayWatch =>
      'Stadion, Fitnessstudio, Arena, Platz, Bowlingbahn';

  @override
  String get placeTypeHintNature => 'Strand, Park, Wald, Berg, Wasserfall';

  @override
  String get placeTypeHintTransport =>
      'Flughafen, Bahnhof, Bushaltestelle, Fährterminal';

  @override
  String get placeTypeHintHealBathe =>
      'Spa, heiße Quelle, Schwimmbad, Sauna, Badehaus';

  @override
  String get placeTypeHintEntertainment =>
      'Theater, Kino, Konzerthalle, Nachtclub';

  @override
  String get placeTypeHintSight =>
      'Denkmal, Aussichtspunkt, Schloss, Platz, Ruine';

  @override
  String get recommendedTimeLabel => 'Empfohlene Aufenthaltsdauer';

  @override
  String get timeToSpendHelp =>
      'Ungefähr, wie lange du hier bleiben möchtest. Tippe, um Tage, Stunden und Minuten festzulegen.';

  @override
  String get stopIsFree => 'Dieser Stopp ist kostenlos';

  @override
  String get freeHelp =>
      'Aktivieren, wenn der Besuch dieses Ortes nichts kostet.';

  @override
  String get costLabel => 'Kosten';

  @override
  String get costHelp =>
      'Ungefähre Kosten pro Person, in der Währung der Reiseroute.';

  @override
  String get enterValidNumber => 'Gib eine gültige Zahl ein';

  @override
  String get thoughtsLabel => 'Gedanken';

  @override
  String get thoughtsHelp =>
      'Deine persönliche Meinung zu diesem Stopp – was dich erwartet, was dir gefallen hat, was du auslassen kannst, Tipps zu Öffnungszeiten. Nutze die Symbolleiste für Fett, Kursiv, Überschriften oder Aufzählungslisten.';

  @override
  String get annotationsLabel => 'Anmerkungen';

  @override
  String get annotationsHelp =>
      'Kurze getaggte Notizen (Tipp, Vorsicht, Vermeiden, Info), die diesem Stopp angehängt sind. Nützlich für Warnungen oder Hinweise.';

  @override
  String get saveChangesButton => 'Änderungen speichern';

  @override
  String get addStopButton => 'Stopp hinzufügen';

  @override
  String get deleteStopButton => 'Stopp löschen';

  @override
  String get timeToSpendModalTitle => 'Aufenthaltsdauer';

  @override
  String get editTransitTitle => 'Transport bearbeiten';

  @override
  String get addTransitTitle => 'Transport hinzufügen';

  @override
  String get updateTransitButton => 'Transport aktualisieren';

  @override
  String get transportModeLabel => 'Modus';

  @override
  String get transportModeHelp =>
      'Wie du auf dieser Etappe reist (zu Fuß, Bus, Zug, Fähre usw.). Einige Modi zeigen zusätzliche Felder für Linie und Richtung an.';

  @override
  String get transitLineLabel => 'Linie (optional)';

  @override
  String get transitLineHelp =>
      'Optional. Die Liniennummer oder der Name (z. B. \"Bus 42\", \"M1\").';

  @override
  String get transitDirectionLabel => 'Richtung (optional)';

  @override
  String get transitDirectionHelp =>
      'Optional. Wohin die Linie fährt (z. B. \"Richtung Norden\", \"Châtelet\").';

  @override
  String get durationLabel => 'Dauer';

  @override
  String get durationHelp =>
      'Wie lange diese Etappe dauert, in Stunden und Minuten.';

  @override
  String get legCostHelp =>
      'Ungefähre Kosten in der Währung der Reiseroute. Deaktiviert, wenn \"Kostenlos\" aktiviert ist.';

  @override
  String get hoursLabel => 'Std';

  @override
  String get minutesLabel => 'Min';

  @override
  String get freeLegLabel => 'Kostenlos';

  @override
  String get freeLegHelp =>
      'Aktivieren, wenn diese Etappe nichts kostet (zu Fuß, inkludierter Umstieg usw.).';

  @override
  String get legThoughtsLabel => 'Gedanken (optional)';

  @override
  String get legThoughtsHelp =>
      'Optional. Alles Nützliche zu dieser Etappe – Buchungstipps, Umstiegshinweise, wo man sitzen sollte, überraschende Ticketkosten.';

  @override
  String get annotationTypeLabel => 'Typ';

  @override
  String get annotationTypeHelp =>
      'Tipp: ein hilfreicher Hinweis. Vorsicht: sei vorsichtig. Vermeiden: nicht hingehen. Info: eine neutrale Notiz.';

  @override
  String get annotationAdvice => 'Tipp';

  @override
  String get annotationCaution => 'Vorsicht';

  @override
  String get annotationAvoid => 'Vermeiden';

  @override
  String get annotationInfo => 'Info';

  @override
  String get annotationContentLabel => 'Inhalt *';

  @override
  String get annotationContentHelp =>
      'Beschreibe deinen Tipp, deine Vorsicht, Warnung oder Notiz in ein oder zwei Sätzen.';

  @override
  String get annotationContentRequired => 'Inhalt ist erforderlich';

  @override
  String get editAnnotationTitle => 'Anmerkung bearbeiten';

  @override
  String get addAnnotationDialogTitle => 'Anmerkung hinzufügen';

  @override
  String get saveButton => 'Speichern';

  @override
  String get moveStopTitle => 'Stopp verschieben';

  @override
  String moveStopDescription(int max) {
    return 'Wähle eine vorhandene Spalte, eine Lücke für eine neue Spalte oder lagere den Stopp in eine eigene Spalte aus. Spalten mit dem Maximum von $max Stopps sind deaktiviert.';
  }

  @override
  String get extractIntoOwnTrack => 'In eine eigene neue Spalte auslagern';

  @override
  String get moveButton => 'Verschieben';

  @override
  String moveStopMoved(String destination) {
    return 'Verschoben nach $destination';
  }

  @override
  String get itineraryChangedElsewhere =>
      'Reiseroute wurde anderswo geändert – schließe sie und öffne sie erneut, um die neueste Reihenfolge zu sehen.';

  @override
  String get moveStopOrphan1 =>
      'Dies ist der letzte Stopp in seiner Spalte – die Spalte wird aus der Reiseroute entfernt.';

  @override
  String moveStopOrphanSegments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Transportabschnitte werden gelöscht, weil ihre Stopps nicht mehr in benachbarten Spalten liegen.',
      one:
          '1 Transportabschnitt wird gelöscht, weil seine Stopps nicht mehr in benachbarten Spalten liegen.',
    );
    return '$_temp0';
  }

  @override
  String get moveStopNewTrack => 'Neue Spalte';

  @override
  String moveStopNewTrackBefore(int n) {
    return 'Neue Spalte vor Spalte $n';
  }

  @override
  String moveStopNewTrackAfter(int n) {
    return 'Neue Spalte nach Spalte $n';
  }

  @override
  String moveStopNewTrackBetween(int a, int b) {
    return 'Neue Spalte zwischen Spalte $a und Spalte $b';
  }

  @override
  String get moveStopCurrentSuffix => '  •  aktuell';

  @override
  String moveStopFull(int max) {
    return 'Voll $max/$max';
  }

  @override
  String extractSubtitle(String trackName) {
    return 'Trennt diesen Stopp aus \"$trackName\" ab – die neue Spalte erscheint direkt danach.';
  }

  @override
  String get removeRatingTitle => 'Deine Bewertung entfernen?';

  @override
  String get removeRatingMessage =>
      'Deine Bewertung wird gelöscht und der Durchschnitt wird für alle aktualisiert, die diese Reiseroute ansehen.';

  @override
  String get rateItineraryTitle => 'Diese Reiseroute bewerten';

  @override
  String get overallRatingLabel => 'Gesamt *';

  @override
  String get overallRatingHelp =>
      'Erforderlich. Deine Gesamtbewertung dieser Reiseroute, von 1 bis 5 Sternen.';

  @override
  String get ratingThanksMessage => 'Danke! Deine Bewertung hilft anderen.';

  @override
  String get yourImpressionLabel => 'Dein Eindruck (optional)';

  @override
  String get yourImpressionHelp =>
      'Optional. Teile, was herausstach – Höhepunkte, Enttäuschungen, wem du es empfehlen würdest. Nutze die Symbolleiste für Fett, Kursiv, Überschriften oder Aufzählungslisten.';

  @override
  String get removeMyRatingTooltip => 'Meine Bewertung entfernen';

  @override
  String get wantToShareMore => 'Möchtest du mehr teilen? (optional)';

  @override
  String get safetyLabel => 'Sicherheit';

  @override
  String get safetyHelp =>
      'Optional. Wie sicher du dich während dieser Reise gefühlt hast.';

  @override
  String get experienceLabel => 'Erlebnis';

  @override
  String get experienceHelp =>
      'Optional. Wie angenehm und einprägsam die Reise war.';

  @override
  String get accessibilityLabel => 'Barrierefreiheit';

  @override
  String get accessibilityHelp =>
      'Optional. Wie zugänglich die Reiseroute ist (Mobilität, Sprache, Beschilderung).';

  @override
  String get familyFriendlyLabel => 'Familienfreundlich';

  @override
  String get familyFriendlyHelp =>
      'Optional. Wie geeignet die Reise für Familien mit Kindern ist.';

  @override
  String get crowdednessLabel => 'Wenig überfüllt';

  @override
  String get crowdednessHelp =>
      'Optional. Wie wenig überfüllt und geräumig es wirkte – 5 = angenehm leer, 1 = überfüllt.';

  @override
  String get showOptionalFields => 'Optionale Felder anzeigen';

  @override
  String get hideOptionalFields => 'Optionale Felder ausblenden';

  @override
  String get transportModeWalk => 'Zu Fuß';

  @override
  String get transportModeBus => 'Bus';

  @override
  String get transportModeTram => 'Straßenbahn';

  @override
  String get transportModeMetro => 'U-Bahn';

  @override
  String get transportModeTrain => 'Zug';

  @override
  String get transportModeTaxi => 'Taxi';

  @override
  String get transportModeUber => 'Uber';

  @override
  String get transportModeBike => 'Fahrrad';

  @override
  String get transportModeFerry => 'Fähre';

  @override
  String get transportModeCar => 'Auto';

  @override
  String get transportModeAirplane => 'Flugzeug';

  @override
  String get dimensionOverall => 'Gesamt';

  @override
  String get dimensionOverallDesc => 'Gesamteindruck';

  @override
  String get dimensionSafetyDesc =>
      'Wie sicher du dich durchgehend gefühlt hast';

  @override
  String get dimensionExperienceDesc => 'Qualität des Gesamterlebnisses';

  @override
  String get dimensionAccessibilityDesc => 'Zugänglichkeit für alle';

  @override
  String get dimensionFamilyFriendlyDesc => 'Eignung für Kinder und Familien';

  @override
  String get dimensionCrowdednessDesc =>
      'Wie wenig überfüllt und geräumig es wirkte';

  @override
  String dimensionRatingTitle(String label) {
    return 'Bewertung: $label';
  }

  @override
  String noRatingsYetFor(String label) {
    return 'Noch keine Bewertungen für $label';
  }

  @override
  String basedOnRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Basierend auf $count Bewertungen',
      one: 'Basierend auf $count Bewertung',
    );
    return '$_temp0';
  }

  @override
  String get ratersLabel => 'Bewertende';

  @override
  String get annotationAdviceDesc => 'Etwas Nützliches oder ein Profi-Tipp.';

  @override
  String get annotationCautionDesc => 'Aufpassen – Überraschungen möglich.';

  @override
  String get annotationAvoidDesc => 'Lass das. Spar dir die Zeit.';

  @override
  String get annotationInfoDesc => 'Eine neutrale Info, die man kennen sollte.';

  @override
  String get unknownUser => 'Unbekannt';

  @override
  String timeAgoMonths(int count) {
    return 'vor $count Mon.';
  }

  @override
  String timeAgoDays(int count) {
    return 'vor $count T.';
  }

  @override
  String timeAgoHours(int count) {
    return 'vor $count Std.';
  }

  @override
  String timeAgoMinutes(int count) {
    return 'vor $count Min.';
  }

  @override
  String get timeJustNow => 'Gerade eben';

  @override
  String get yearsAbbrev => 'J';

  @override
  String get timeLabel => 'Zeit';

  @override
  String get transitLabel => 'Transport';

  @override
  String get noLegsYetTapAdd =>
      'Noch keine Etappen. Tippe auf ＋, um hinzuzufügen.';

  @override
  String get segmentNeedsOneLeg =>
      'Ein Abschnitt benötigt mindestens eine Etappe. Lösche stattdessen den Abschnitt.';

  @override
  String fromStopName(String name) {
    return 'Von $name';
  }

  @override
  String toStopName(String name) {
    return 'Nach $name';
  }

  @override
  String get visibilityPublicDesc => 'Jeder mit dem Link kann es ansehen.';

  @override
  String get visibilityFollowersDesc => 'Nur Personen, die dir folgen.';

  @override
  String get visibilityRestrictedDesc => 'Nur Personen, die du erlaubst.';

  @override
  String get visibilityOnlyMeDesc => 'Nur du.';

  @override
  String get saveItineraryFirstAllowlist =>
      'Speichere zuerst die Reiseroute und verwalte dann deine Zugriffsliste über den Bearbeitungsbildschirm.';

  @override
  String get allowlistLabel => 'Zugriffsliste';

  @override
  String personCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Personen',
      one: '$count Person',
    );
    return '$_temp0';
  }

  @override
  String removedFromAllowlist(String name) {
    return '$name von der Zugriffsliste entfernt';
  }

  @override
  String get addPeople => 'Personen hinzufügen';

  @override
  String get otherOption => 'Andere';

  @override
  String get thisItineraryFallback => 'diese Reiseroute';

  @override
  String get discardReorderMessage =>
      'Deine neue Reihenfolge wird nicht gespeichert.';

  @override
  String get emptyTrackName => '(leer)';

  @override
  String get unnamedStop => '(unbenannt)';

  @override
  String get unknownStop => '(unbekannt)';

  @override
  String get dragToChangeTrackOrder =>
      'Ziehen, um die Spaltenreihenfolge zu ändern';

  @override
  String transitSegmentsWillBeDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Transportabschnitte werden gelöscht',
      one: '1 Transportabschnitt wird gelöscht',
    );
    return '$_temp0';
  }

  @override
  String andMoreCount(int count) {
    return '… und $count weitere';
  }

  @override
  String altsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Alt.',
      one: '$count Alt.',
    );
    return '$_temp0';
  }

  @override
  String segmentToWillBeDeleted(String name) {
    return '→ $name  —  Abschnitt wird gelöscht';
  }

  @override
  String get reorderAlternativesTitle => 'Alternativen neu anordnen';

  @override
  String get reorderAlternativesHint =>
      'Ziehen, um zu ändern, welche Option zuerst erscheint. Tippe auf Speichern, um zu übernehmen.';

  @override
  String get emptyTrackLabel => '(leere Spalte)';

  @override
  String get moveStopToLabel => 'Stopp verschieben nach';

  @override
  String get messageLabel => 'Nachricht';

  @override
  String get annotationKeepShortHint =>
      'Halte es kurz – unter 200 Zeichen liest sich auf kleinen Bildschirmen am besten.';

  @override
  String get transportModeSection => 'Transportmodus';

  @override
  String get lineDirectionSection => 'Linie & Richtung';

  @override
  String get durationCostSection => 'Dauer & Kosten';

  @override
  String get allRatersLabel => 'Alle Bewertenden';

  @override
  String travelersRatedThis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Reisende haben dies bewertet',
      one: '$count Reisender hat dies bewertet',
    );
    return '$_temp0';
  }

  @override
  String get byDimensionLabel => 'Nach Dimension';

  @override
  String get notEnoughRatings => 'Nicht genug Bewertungen';

  @override
  String get youRatedThis => 'Du hast dies bewertet';

  @override
  String get changeButton => 'Ändern';

  @override
  String get hideReview => 'Rezension ausblenden';

  @override
  String get readReview => 'Rezension lesen';

  @override
  String get notesLabel => 'Notizen';

  @override
  String get viewLess => 'weniger anzeigen';

  @override
  String get viewMore => '... mehr anzeigen';

  @override
  String get imageTooLarge => 'Das Bild ist zu groß (max. 10 MB).';

  @override
  String get couldNotLoadImage =>
      'Bild konnte nicht geladen werden. Bitte versuche ein anderes.';

  @override
  String get pinchToZoomHint =>
      'Zum Zoomen zusammenziehen · Zum Verschieben ziehen';

  @override
  String get addCoverImage => 'Füge ein Titelbild hinzu';

  @override
  String get coverOptionalMapFallback =>
      'Optional – andernfalls wird die Karte verwendet.';

  @override
  String get noCoverImage => 'Kein Titelbild';

  @override
  String get mapTapToPlacePin =>
      'Tippe auf die Karte, um eine Markierung zu setzen';

  @override
  String get mapTapToMovePin =>
      'Tippe woanders, um die Markierung zu verschieben, und tippe dann auf Bestätigen';

  @override
  String get mapMyLocation => 'Mein Standort';

  @override
  String get mapUseMyLocation => 'Meinen Standort verwenden';

  @override
  String get mapSearchNoResults => 'Keine Orte gefunden.';

  @override
  String get mapSearchThisArea => 'Dieses Gebiet durchsuchen';

  @override
  String get mapUnnamedPlace => 'Unbenannter Ort';

  @override
  String get locationPermissionDenied => 'Standortberechtigung verweigert';

  @override
  String get locationServiceDisabled => 'Standortdienste sind deaktiviert';

  @override
  String get locationUnavailable =>
      'Dein Standort konnte nicht ermittelt werden';

  @override
  String get locationOpenSettings => 'Einstellungen öffnen';

  @override
  String get nothingToPreview => 'Noch nichts zum Vorschauen.';

  @override
  String get rateOverallFirstHint =>
      'Bewerte deinen Gesamteindruck. Sobald du das getan hast, kannst du mehr teilen.';

  @override
  String get splashTagline =>
      'Entdecke und teile Reiserouten\nvon echten Entdeckern';

  @override
  String get splashMotto => 'Erkunde die Welt, eine Route nach der anderen';

  @override
  String get tripsPillLabel => 'Reisen';

  @override
  String get stopsPillLabel => 'Stopps';

  @override
  String get travelledPillLabel => 'bereist';

  @override
  String get stopFallbackName => 'Stopp';

  @override
  String stopWithNumber(int n) {
    return 'Stopp $n';
  }

  @override
  String get undoLabel => 'Rückgängig';

  @override
  String get updateYourRating => 'Aktualisiere deine Bewertung';

  @override
  String get moveActionLabel => 'verschieben';

  @override
  String get reorderActionLabel => 'neu anordnen';

  @override
  String get addParallelStopLabel => '// Stopp';

  @override
  String get aStopFallback => 'Ein Stopp';

  @override
  String get locationLabel => 'Standort';

  @override
  String get noLocationSet => 'Kein Standort festgelegt';

  @override
  String get latitudeLabel => 'Breitengrad';

  @override
  String get longitudeLabel => 'Längengrad';

  @override
  String get invalidLatitudeError =>
      'Der Breitengrad muss eine Zahl zwischen -90 und 90 sein';

  @override
  String get invalidLongitudeError =>
      'Der Längengrad muss eine Zahl zwischen -180 und 180 sein';

  @override
  String get coordinatesPairRequiredError =>
      'Gib sowohl Breiten- als auch Längengrad ein';

  @override
  String get detailsSection => 'Details';

  @override
  String get selectLanguagesTitle => 'Sprachen auswählen';

  @override
  String get done => 'Fertig';

  @override
  String alreadyInItinerary(String name) {
    return '$name ist bereits in dieser Reiseroute.';
  }

  @override
  String stopNumberOfTotal(int n, int total) {
    return 'Stopp $n von $total';
  }

  @override
  String shareCaption(String title, String stops, String duration) {
    return 'Schau dir \"$title\" auf Ntripi an — $stops, $duration';
  }

  @override
  String get apiErrorNotAuthenticated => 'Du bist nicht angemeldet.';

  @override
  String get apiErrorAccountDeactivated => 'Dein Konto wurde deaktiviert.';

  @override
  String get apiErrorEmailUnverified =>
      'Bestätige deine E-Mail über Google, um dies zu tun.';

  @override
  String get apiErrorItineraryNotFound => 'Reiseroute nicht gefunden.';

  @override
  String get apiErrorItineraryNotOwner =>
      'Du hast keine Berechtigung, diese Reiseroute zu ändern.';

  @override
  String get apiErrorIfMatchRequired =>
      'Diese Änderung konnte nicht gespeichert werden – bitte neu laden und erneut versuchen.';

  @override
  String get apiErrorItineraryStale =>
      'Die Reiseroute wurde geändert – bitte neu laden.';

  @override
  String get apiErrorWaitlistContactRequired =>
      'Gib mindestens eine E-Mail oder eine WhatsApp-Nummer an.';

  @override
  String get apiErrorGoogleTokenInvalid => 'Ungültiges Google-Token.';

  @override
  String get apiErrorInvalidGrant =>
      'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.';

  @override
  String get apiErrorStopNotFound => 'Stopp nicht gefunden.';

  @override
  String get apiErrorTrackNotFound =>
      'Spalte nicht gefunden oder gehört nicht zu dieser Reiseroute.';

  @override
  String get apiErrorSegmentNotFound => 'Transportabschnitt nicht gefunden.';

  @override
  String get apiErrorLegNotFound => 'Transportetappe nicht gefunden.';

  @override
  String get apiErrorItineraryAccessDenied =>
      'Du hast keinen Zugriff auf diese Reiseroute.';

  @override
  String get apiErrorAllowlistRestrictedOnly =>
      'Die Zugriffsliste gilt nur für eingeschränkte Reiserouten.';

  @override
  String get apiErrorUserNotFound => 'Benutzer nicht gefunden.';

  @override
  String get apiErrorAllowlistUserExists =>
      'Dieser Benutzer hat bereits Zugriff.';

  @override
  String get apiErrorAllowlistUserNotFound =>
      'Benutzer nicht in der Zugriffsliste gefunden.';

  @override
  String get apiErrorRankCollision =>
      'Reihenfolgenkonflikt – bitte erneut versuchen.';

  @override
  String get apiErrorAnnotationNotFound => 'Anmerkung nicht gefunden.';

  @override
  String get apiErrorRatingNotFound =>
      'Du hast diese Reiseroute noch nicht bewertet.';

  @override
  String get apiErrorSegmentAlreadyExists =>
      'Ein Abschnitt verbindet diese beiden Stopps bereits.';

  @override
  String get apiErrorIncorrectPassword => 'Falsches Passwort.';

  @override
  String get apiErrorLoginInvalid =>
      'E-Mail/Benutzername oder Passwort ist falsch.';

  @override
  String get apiErrorCannotFollowSelf => 'Du kannst dir nicht selbst folgen.';

  @override
  String get apiErrorNotFollowing => 'Du folgst diesem Benutzer nicht.';

  @override
  String get apiErrorFollowRequestNotFound =>
      'Follower-Anfrage nicht gefunden.';

  @override
  String get apiErrorFollowRequestAlreadyAccepted =>
      'Diese Follower-Anfrage wurde bereits angenommen.';

  @override
  String get apiErrorCannotRejectRequest =>
      'Du kannst diese Follower-Anfrage nicht ablehnen.';

  @override
  String get apiErrorAccountPrivate => 'Dieses Konto ist privat.';

  @override
  String get apiErrorTosRequired =>
      'Du musst die Nutzungsbedingungen akzeptieren, um dich zu registrieren.';

  @override
  String get apiErrorUsernameTaken =>
      'Dieser Benutzername ist bereits vergeben.';

  @override
  String get apiErrorEmailTaken =>
      'Ein Konto mit dieser E-Mail existiert bereits.';

  @override
  String get reportItineraryTitle => 'Diese Reiseroute melden';

  @override
  String get reportItineraryTooltip => 'Melden';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonNsfw => 'Nacktheit oder sexuelle Inhalte';

  @override
  String get reportReasonViolence => 'Gewalt';

  @override
  String get reportReasonHateSpeech => 'Hassrede';

  @override
  String get reportReasonHarassment => 'Belästigung';

  @override
  String get reportReasonCopyright => 'Urheberrechtsverletzung';

  @override
  String get reportReasonOther => 'Sonstiges';

  @override
  String get reportNotesHint => 'Details hinzufügen (optional)';

  @override
  String get reportSubmit => 'Meldung senden';

  @override
  String get reportThanks => 'Danke. Wir prüfen diese Meldung.';

  @override
  String get apiErrorReportOwnContent =>
      'Du kannst deine eigenen Inhalte nicht melden.';

  @override
  String get apiErrorReportRateLimited =>
      'Zu viele Meldungen. Bitte versuche es später erneut.';

  @override
  String get imageBlockedNsfw =>
      'Dieses Bild scheint unzulässige Inhalte zu enthalten.';

  @override
  String get apiErrorImageModerationRejected =>
      'Dieses Bild kann nicht hochgeladen werden, da es möglicherweise unzulässige Inhalte enthält.';

  @override
  String get suspendedTitle => 'Dein Konto ist gesperrt';

  @override
  String get suspendedMessage =>
      'Ein Moderator hat dieses Konto wegen Verstoßes gegen unsere Community-Richtlinien gesperrt. Solange die Sperre aktiv ist, kannst du dich nicht anmelden.';

  @override
  String get suspendedAppealButton => 'Entscheidung anfechten';

  @override
  String get suspendedBackToLogin => 'Zurück zur Anmeldung';

  @override
  String get hiddenBannerTitle => 'Von einem Moderator ausgeblendet';

  @override
  String get hiddenBannerMessage =>
      'Nur du siehst diese Reiseroute. Sie erscheint weder im Feed noch in der Suche oder auf ihrer Teilen-Seite. Du kannst sie unter Kontostatus in den Einstellungen anfechten.';

  @override
  String get hiddenReviewMessage =>
      'Nur du siehst diese Bewertung. Sie erscheint nicht bei der Reiseroute und zählt nicht für deren Bewertung.';

  @override
  String get hiddenProfileMessage =>
      'Nur du siehst deinen Anzeigenamen und deine Bio. Andere sehen stattdessen deinen @Benutzernamen.';

  @override
  String get accountStatusTitle => 'Kontostatus';

  @override
  String get violationsEmpty => 'Keine Moderationsmaßnahmen für dein Konto.';

  @override
  String get violationHidden => 'Ausgeblendet';

  @override
  String get violationRemoved => 'Entfernt';

  @override
  String get violationWarned => 'Verwarnung';

  @override
  String get violationBanned => 'Sperre';

  @override
  String get violationOther => 'Moderationsmaßnahme';

  @override
  String get violationLifted => 'Aufgehoben';

  @override
  String get appealPending => 'Einspruch wird geprüft';

  @override
  String get appealRejected => 'Einspruch abgelehnt';

  @override
  String get appealRestored => 'Wiederhergestellt';

  @override
  String get appealReduced => 'Maßnahme abgemildert';

  @override
  String get appealAvailable => 'Einspruch möglich';

  @override
  String get appealSubmit => 'Einspruch';

  @override
  String get appealSubmitted =>
      'Einspruch eingereicht. Wir senden dir das Ergebnis per E-Mail.';

  @override
  String get appealFormTitle => 'Diese Entscheidung anfechten';

  @override
  String get appealFormMessage =>
      'Erkläre, warum du die Entscheidung für falsch hältst. Ein Moderator prüft sie.';

  @override
  String get appealReasonLabel => 'Deine Erklärung';

  @override
  String get appealReasonRequired =>
      'Bitte erkläre, warum du Einspruch einlegst.';

  @override
  String appealCooldownUntil(String date) {
    return 'Du kannst nach dem $date erneut Einspruch einlegen.';
  }

  @override
  String get apiErrorAppealPending =>
      'Für dieses Element läuft bereits ein Einspruch.';

  @override
  String get apiErrorAppealCooldown =>
      'Du kannst für dieses Element erst 30 Tage nach einer Ablehnung erneut Einspruch einlegen.';

  @override
  String get apiErrorAppealTargetNotFound =>
      'Hier gibt es keine Moderationsmaßnahme zum Anfechten.';

  @override
  String get apiErrorTextModerationRejected =>
      'Dieser Text verstößt möglicherweise gegen die Community-Richtlinien und wurde nicht gespeichert. Bitte bearbeite ihn und versuche es erneut.';

  @override
  String get apiErrorCannotBlockSelf =>
      'Du kannst dich nicht selbst blockieren.';

  @override
  String moderationRejectedBecause(String reason) {
    return 'Dieser Text wurde nicht gespeichert, weil er möglicherweise $reason enthält. Bitte bearbeite ihn und versuche es erneut.';
  }

  @override
  String get moderationCategoryMinors => 'Inhalte mit Minderjährigen';

  @override
  String get moderationCategorySexual => 'sexuelle Inhalte';

  @override
  String get moderationCategoryHate => 'Hassrede';

  @override
  String get moderationCategoryHarassment => 'Belästigung';

  @override
  String get moderationCategoryViolence => 'gewalttätige Inhalte';

  @override
  String get moderationCategorySelfHarm => 'Inhalte über Selbstverletzung';

  @override
  String get moderationCategoryIllicit => 'illegale Aktivitäten';

  @override
  String get reportReasonCsam => 'Darstellungen sexuellen Kindesmissbrauchs';

  @override
  String get reportReasonSexualContent => 'Nacktheit oder sexuelle Inhalte';

  @override
  String get reportReasonViolenceThreat => 'Gewalt oder Drohungen';

  @override
  String get reportContent => 'Melden';

  @override
  String get reportUser => 'Dieses Konto melden';

  @override
  String get reportStop => 'Diesen Stopp melden';

  @override
  String get reportReview => 'Diese Bewertung melden';

  @override
  String get reportAnnotation => 'Diese Anmerkung melden';

  @override
  String get blockUser => 'Blockieren';

  @override
  String get unblockUser => 'Blockierung aufheben';

  @override
  String blockUserTitle(String username) {
    return '@$username blockieren?';
  }

  @override
  String get blockUserMessage =>
      'Ihr seht eure Reisen und Profile gegenseitig nicht mehr, und keiner kann dem anderen folgen. Die Person wird nicht benachrichtigt.';

  @override
  String get blockedUsers => 'Blockierte Konten';

  @override
  String get blockedUsersEmpty => 'Du hast niemanden blockiert.';

  @override
  String blockedUserRemoved(String username) {
    return '@$username entblockt.';
  }

  @override
  String blockedUserAdded(String username) {
    return '@$username blockiert.';
  }

  @override
  String get abuseContact => 'Missbrauch melden';

  @override
  String get abuseContactSubtitle => 'Schreib uns wegen schädlicher Inhalte';

  @override
  String get communityGuidelines => 'Community-Richtlinien';

  @override
  String get moderationHintTitle => 'Das könnte beleidigend wirken';

  @override
  String get moderationHintBody =>
      'Du kannst es trotzdem posten — das ist nur ein Hinweis, keine Sperre.';

  @override
  String get hiddenAppealAction => 'Um Überprüfung bitten';

  @override
  String hiddenBannerReason(String reason) {
    return 'Grund: $reason';
  }

  @override
  String get bugReportTitle => 'Problem melden';

  @override
  String get bugReportHint => 'Was ist passiert?';

  @override
  String get bugReportSubmit => 'Bericht senden';

  @override
  String get bugReportThanks => 'Danke. Wir sehen uns das an.';

  @override
  String get bugReportAttachmentNotice =>
      'Dein Screenshot und deine Gerätedaten werden angehängt.';

  @override
  String get bugReportCategoryCrash => 'Die App hing oder wurde beendet';

  @override
  String get bugReportCategoryVisual => 'Etwas wird falsch dargestellt';

  @override
  String get bugReportCategoryData => 'Falsche oder fehlende Informationen';

  @override
  String get bugReportCategorySlow => 'Zu langsam';

  @override
  String get bugReportCategoryOther => 'Etwas anderes';

  @override
  String get bugReportNavigate => 'Navigieren';

  @override
  String get bugReportDraw => 'Zeichnen';

  @override
  String get settingsReportBug => 'Fehler melden';

  @override
  String get settingsShakeToReport => 'Schütteln zum Melden';

  @override
  String get settingsShakeToReportDetail =>
      'Schüttle dein Telefon, um ein Problem zu melden';

  @override
  String get notificationsTitle => 'Benachrichtigungen';

  @override
  String get notificationsEmpty =>
      'Noch nichts da.\nFollows, Bewertungen und Merkungen erscheinen hier.';

  @override
  String notificationsCountLabel(int count) {
    return 'Neueste · $count';
  }

  @override
  String get notificationSomeone => 'Jemand';

  @override
  String get notificationGeneric => 'Du hast eine neue Benachrichtigung.';

  @override
  String get notificationTapForDetails => 'Tippen für Details und Einspruch';

  @override
  String notificationFollowRequest(String name) {
    return '$name möchte dir folgen';
  }

  @override
  String notificationNewFollower(String name) {
    return '$name folgt dir jetzt';
  }

  @override
  String notificationFollowAccepted(String name) {
    return '$name hat deine Follow-Anfrage angenommen';
  }

  @override
  String notificationRated(String name) {
    return '$name hat eine deiner Reiserouten bewertet';
  }

  @override
  String notificationSaved(String name) {
    return '$name hat eine deiner Reiserouten gespeichert';
  }

  @override
  String notificationHidden(String title) {
    return '„$title“ wurde ausgeblendet';
  }

  @override
  String get notificationHiddenUntitled =>
      'Eine deiner Reiserouten wurde ausgeblendet';

  @override
  String notificationRemoved(String title) {
    return '„$title“ wurde entfernt';
  }

  @override
  String get notificationRemovedUntitled =>
      'Eine deiner Reiserouten wurde entfernt';

  @override
  String get notificationSettingsOptionalLabel => 'Optional';

  @override
  String get notificationSettingsRatings => 'Bewertungen';

  @override
  String get notificationSettingsRatingsDetail =>
      'Wenn jemand deine Reiseroute bewertet';

  @override
  String get notificationSettingsSaves => 'Gespeichert';

  @override
  String get notificationSettingsSavesDetail =>
      'Wenn jemand deine Reiseroute speichert';

  @override
  String get notificationSettingsFollowAccepted => 'Anfrage angenommen';

  @override
  String get notificationSettingsFollowAcceptedDetail =>
      'Wenn jemand deine Follow-Anfrage annimmt';

  @override
  String get notificationSettingsAlwaysOnNote =>
      'Follow-Anfragen und Moderationshinweise sind immer aktiv. Eine Anfrage, die du nie siehst, kann nicht beantwortet werden, und du musst wissen, wann deine Inhalte ausgeblendet werden, um rechtzeitig Einspruch einlegen zu können.';

  @override
  String settingsNotificationsOnCount(int count) {
    return '$count von 3 aktiv';
  }

  @override
  String get notificationWarned =>
      'Du hast eine Verwarnung der Moderation erhalten';

  @override
  String get notificationWarnedDetail =>
      'Tippen, um den Grund zu sehen und Einspruch einzulegen';
}
