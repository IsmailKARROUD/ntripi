// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get required => 'Requis';

  @override
  String get retry => 'Réessayer';

  @override
  String get dismiss => 'Ignorer';

  @override
  String get seeAll => 'Voir tout';

  @override
  String get back => 'Retour';

  @override
  String get navSearch => 'Recherche';

  @override
  String get navProfile => 'Profil';

  @override
  String get navItineraries => 'Itinéraires';

  @override
  String get navFeed => 'Fil';

  @override
  String get feedTitle => 'Découvrir';

  @override
  String get feedTabTop => 'Top';

  @override
  String get feedTabRecent => 'Récents';

  @override
  String get feedEmpty =>
      'Aucun itinéraire public pour l\'instant. Revenez bientôt !';

  @override
  String get feedTopEmpty => 'Pas assez de voyages notés — voir Récents.';

  @override
  String get offlineBanner =>
      'Vous êtes hors ligne ! Certaines fonctionnalités peuvent être indisponibles.';

  @override
  String get downloadBanner =>
      'Pour une meilleure expérience, téléchargez l\'application Ntripi.';

  @override
  String get downloadBannerButton => 'Télécharger';

  @override
  String get loginTitle => 'Bon retour';

  @override
  String get loginSubtitle => 'Connectez-vous pour continuer votre voyage';

  @override
  String get loginEmailLabel => 'Email ou nom d\'utilisateur';

  @override
  String get loginEmailHelp =>
      'Connectez-vous avec l\'email avec lequel vous vous êtes inscrit, ou votre @identifiant.';

  @override
  String get loginEmailHint => 'vous@exemple.com ou @identifiant';

  @override
  String get loginPasswordLabel => 'Mot de passe';

  @override
  String get loginPasswordHelp =>
      'Votre mot de passe. Appuyez sur l\'icône œil pour l\'afficher ou le masquer.';

  @override
  String get loginForgotPassword => 'Mot de passe oublié ?';

  @override
  String get loginSignIn => 'Se connecter';

  @override
  String get loginNoAccount => 'Pas encore de compte ? ';

  @override
  String get loginSignUp => 'S\'inscrire';

  @override
  String get loginOrContinueWith => 'ou continuer avec';

  @override
  String get registerTitle => 'Créer un compte';

  @override
  String get registerSubtitle =>
      'Rejoignez des milliers d\'explorateurs qui partagent leurs itinéraires';

  @override
  String get registerDisplayName => 'Nom affiché';

  @override
  String get registerDisplayNameHelp =>
      'Comment votre nom apparaît aux autres. 50 caractères maximum, toute langue et emoji. Affiche @identifiant si vide.';

  @override
  String get registerDisplayNameHint => 'Votre nom';

  @override
  String get registerUsername => 'Identifiant *';

  @override
  String get registerUsernameHelp =>
      'Votre @identifiant unique. Lettres minuscules, chiffres et tirets bas uniquement. Impossible à modifier plus tard.';

  @override
  String get registerUsernameHint => 'votreidentifiant';

  @override
  String get registerEmail => 'Email *';

  @override
  String get registerEmailHelp =>
      'Utilisé pour se connecter et récupérer votre compte. Nous ne l\'affichons jamais publiquement.';

  @override
  String get registerEmailHint => 'vous@exemple.com';

  @override
  String get registerEmailRequired => 'L\'email est requis.';

  @override
  String get registerEmailInvalid => 'Veuillez entrer un email valide.';

  @override
  String get registerPassword => 'Mot de passe *';

  @override
  String get registerPasswordHelp =>
      'Au moins 8 caractères avec au moins un chiffre.';

  @override
  String get registerPasswordHint => 'Min. 8 caractères';

  @override
  String get registerPasswordRequired => 'Le mot de passe est requis.';

  @override
  String get registerPasswordTooShort => 'Doit contenir au moins 8 caractères.';

  @override
  String get registerPasswordNoDigit => 'Doit contenir au moins un chiffre.';

  @override
  String get registerConfirmPassword => 'Confirmer le mot de passe *';

  @override
  String get registerConfirmPasswordHelp =>
      'Saisissez à nouveau votre mot de passe pour vérifier qu\'il correspond.';

  @override
  String get registerConfirmRequired =>
      'Veuillez confirmer votre mot de passe.';

  @override
  String get registerConfirmMismatch =>
      'Les mots de passe ne correspondent pas.';

  @override
  String get registerTosAgree => 'J\'accepte les ';

  @override
  String get registerTos => 'Conditions d\'utilisation';

  @override
  String get registerTosAnd => ' et la ';

  @override
  String get registerPrivacyPolicy => 'Politique de confidentialité';

  @override
  String get registerTosHelp =>
      'Vous devez accepter les Conditions d\'utilisation et la Politique de confidentialité pour créer un compte.';

  @override
  String get registerTosRequired =>
      'Vous devez accepter les Conditions d\'utilisation.';

  @override
  String get registerTosTitle => 'Conditions d\'utilisation';

  @override
  String get registerTosLoading => 'Chargement…';

  @override
  String get registerCreateAccount => 'Créer un compte';

  @override
  String get registerAlreadyHaveAccount => 'Vous avez déjà un compte ? ';

  @override
  String get registerSignIn => 'Se connecter';

  @override
  String get followers => 'Abonnés';

  @override
  String get following => 'Abonnements';

  @override
  String get latestTrip => 'DERNIER VOYAGE';

  @override
  String get whereIveBeen => 'OÙ J\'AI ÉTÉ';

  @override
  String get noStopsYet => 'Aucune étape';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étapes',
      one: '$count étape',
    );
    return '$_temp0';
  }

  @override
  String get expand => 'Agrandir';

  @override
  String get tapToSeeStops => 'Toucher pour voir les arrêts';

  @override
  String get coverImageSection => 'Image de couverture';

  @override
  String get coverImageUrlLabel => 'URL de l\'image de couverture';

  @override
  String get uploadCoverImage => 'Téléverser une image de couverture';

  @override
  String followRequestsBannerTitle(int count) {
    return 'Demandes d\'abonnement ($count)';
  }

  @override
  String get tapToReview => 'Appuyer pour consulter';

  @override
  String get editProfileTooltip => 'Modifier le profil';

  @override
  String get settingsTooltip => 'Paramètres';

  @override
  String get shareProfileTooltip => 'Partager le profil';

  @override
  String get couldNotLoadItineraries =>
      'Impossible de charger les itinéraires.';

  @override
  String get whereTheyveBeen => 'OÙ IL/ELLE A ÉTÉ';

  @override
  String get itinerariesSectionHeader => 'ITINÉRAIRES';

  @override
  String get noPublicItinerariesYet =>
      'Aucun itinéraire public pour l\'instant.';

  @override
  String get accountIsPrivateTitle => 'Ce compte est privé';

  @override
  String get followRequestSentTitle => 'Demande envoyée';

  @override
  String get followRequestPendingMessage =>
      'Une fois votre demande acceptée, vous verrez ses itinéraires, ses étapes et sa carte de voyage.';

  @override
  String followToSeeMessage(String handle) {
    return 'Abonnez-vous à $handle pour voir ses itinéraires, ses étapes et sa carte de voyage.';
  }

  @override
  String get editProfileTitle => 'Modifier le profil';

  @override
  String get uploadPhoto => 'Télécharger une photo';

  @override
  String get identitySection => 'Identité';

  @override
  String get displayNameLabel => 'Nom affiché';

  @override
  String get usernameLabel => 'Identifiant';

  @override
  String get bioLabel => 'BIO';

  @override
  String get bioHelpMessage =>
      'Une courte description. Prend en charge le markdown **gras** et les emoji.';

  @override
  String get avatarUrlLabel => 'URL de l\'avatar';

  @override
  String get travelIdentitySection => 'Identité de voyage';

  @override
  String get passportLabel => 'Passeport';

  @override
  String get livesInLabel => 'Réside à';

  @override
  String get languagesLabel => 'Langues';

  @override
  String get privacySection => 'Confidentialité';

  @override
  String get dangerZoneSection => 'Zone de danger';

  @override
  String get privateAccountLabel => 'Compte privé';

  @override
  String get privateAccountSubtitle =>
      'Les personnes doivent demander à vous suivre pour voir vos itinéraires.';

  @override
  String get switchToPublicTitle => 'Passer en public ?';

  @override
  String switchToPublicMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Vous avez $count demandes d\'abonnement en attente. Passer en public les acceptera toutes automatiquement. Continuer ?',
      one:
          'Vous avez 1 demande d\'abonnement en attente. Passer en public l\'acceptera automatiquement. Continuer ?',
    );
    return '$_temp0';
  }

  @override
  String get switchToPublicButton => 'Passer en public';

  @override
  String get planFirstJourney => 'Planifiez votre premier voyage';

  @override
  String get planFirstJourneyHint =>
      'Ajoutez des étapes, des segments de transit et des notes. Partagez-le avec des amis ou gardez-le privé.';

  @override
  String get createItinerary => 'Créer un itinéraire';

  @override
  String get needInspiration => 'Besoin d\'inspiration ?';

  @override
  String get browseForIdeas =>
      'Explorez le fil de la communauté pour trouver des idées.';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsAccount => 'Compte';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsOn => 'Activées';

  @override
  String get settingsNotificationsOff => 'Désactivées';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsSupport => 'Assistance';

  @override
  String get settingsHelpCenter => 'Centre d\'aide';

  @override
  String get settingsAbout => 'À propos de Ntripi';

  @override
  String get settingsTerms => 'Conditions et confidentialité';

  @override
  String get settingsLogout => 'Se déconnecter';

  @override
  String get settingsDeleteAccount => 'Supprimer le compte';

  @override
  String get logoutConfirmTitle => 'Se déconnecter';

  @override
  String get logoutConfirmMessage =>
      'Êtes-vous sûr de vouloir vous déconnecter ?';

  @override
  String get logoutConfirmButton => 'Se déconnecter';

  @override
  String get languagePickerTitle => 'Langue';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get followRequestsTitle => 'Demandes d\'abonnement';

  @override
  String get noRequests => 'Aucune demande en attente';

  @override
  String requestsCountLabel(int count) {
    return 'Demandes · $count';
  }

  @override
  String get acceptButton => 'Accepter';

  @override
  String get rejectButton => 'Refuser';

  @override
  String followersTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abonnés',
      zero: 'Abonnés',
    );
    return '$_temp0';
  }

  @override
  String followingTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abonnements',
      zero: 'Abonnements',
    );
    return '$_temp0';
  }

  @override
  String followRequestsSectionLabel(int count) {
    return 'Demandes d\'abonnement · $count';
  }

  @override
  String get allFollowersSection => 'Tous les abonnés';

  @override
  String get noFollowersYet => 'Aucun abonné pour l\'instant.';

  @override
  String get notFollowingAnyone => 'Vous ne suivez personne pour l\'instant.';

  @override
  String get peopleYouFollow => 'Les personnes que vous suivez';

  @override
  String get confirmButton => 'Confirmer';

  @override
  String get searchPeoplePlaceholder => 'Rechercher des personnes…';

  @override
  String get searchForPeople => 'Rechercher des personnes à suivre';

  @override
  String get noUsersFound => 'Aucun utilisateur trouvé.';

  @override
  String searchResultsCount(int count) {
    return 'Résultats · $count';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abonnés',
      one: '$count abonné',
    );
    return '$_temp0';
  }

  @override
  String get searchUsersHelp =>
      'Trouvez des personnes par leur @identifiant ou leur nom affiché. Appuyez sur un résultat pour voir leur profil.';

  @override
  String get myItineraries => 'Mes itinéraires';

  @override
  String get noItinerariesYet => 'Aucun itinéraire pour l\'instant.';

  @override
  String get tapToCreateFirst =>
      'Appuyez sur + pour créer votre premier voyage.';

  @override
  String get deleteItineraryTitle => 'Supprimer cet itinéraire ?';

  @override
  String get deleteItineraryMessage =>
      'Toutes les étapes, annotations, segments, évaluations et liens partagés seront définitivement supprimés. Cette action est irréversible.';

  @override
  String get deleteItineraryButton => 'Supprimer l\'itinéraire';

  @override
  String get newItinerary => 'Nouvel itinéraire';

  @override
  String get editItinerary => 'Modifier l\'itinéraire';

  @override
  String get coverImageLabel => 'Image de couverture';

  @override
  String get coverImageHelp =>
      'Une image 1200×630 affichée sur la carte de l\'itinéraire et les aperçus de liens.';

  @override
  String get itineraryTitleLabel => 'Titre *';

  @override
  String get itineraryTitleHint => 'ex. 10 jours à Kyoto & Osaka';

  @override
  String get itineraryTitleHelp =>
      'Un nom court et clair pour ce voyage. Affiché sur la carte et les aperçus de partage.';

  @override
  String get itineraryTitleRequired => 'Le titre est requis';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get descriptionHelp =>
      'Facultatif. Un résumé du voyage. Utilisez la barre d\'outils pour mettre du texte en gras ou en italique, ajouter des titres et créer des listes.';

  @override
  String get currencyLabel => 'Devise';

  @override
  String get currencyHelp =>
      'Devise par défaut pour tous les coûts de ce voyage.';

  @override
  String get visibilityLabel => 'Visibilité';

  @override
  String get visibilityHelp =>
      'Public : tout le monde peut voir. Abonnés : uniquement les personnes qui vous suivent. Restreint : uniquement les utilisateurs autorisés. Moi uniquement : privé pour vous.';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityFollowers => 'Abonnés';

  @override
  String get visibilityRestricted => 'Restreint';

  @override
  String get visibilityOnlyMe => 'Moi uniquement';

  @override
  String get imageSaveButUploadFailed =>
      'Itinéraire enregistré, mais l\'envoi de l\'image a échoué. Réessayez depuis l\'écran de modification.';

  @override
  String get formSectionBasics => 'GÉNÉRAL';

  @override
  String get formLabelCurrency => 'DEVISE';

  @override
  String get formLabelWhoCanSee => 'QUI PEUT VOIR ÇA ?';

  @override
  String get formSectionDangerZone => 'ZONE DANGEREUSE';

  @override
  String get formLabelDeleteItinerary => 'SUPPRIMER L\'ITINÉRAIRE';

  @override
  String get formDeleteItineraryHint => 'Tapez le titre pour confirmer';

  @override
  String get currencySearchHint => 'Rechercher une devise…';

  @override
  String currenciesLoadFailed(String error) {
    return 'Échec du chargement des devises : $error';
  }

  @override
  String get deleteItineraryFormTitle => 'Supprimer l\'itinéraire';

  @override
  String deleteItineraryFormMessage(String title) {
    return 'Cela supprimera définitivement \"$title\" et toutes ses étapes. Saisissez le titre pour confirmer.';
  }

  @override
  String get followButton => 'Suivre';

  @override
  String get followingButton => 'Abonné';

  @override
  String get requestedButton => 'En attente';

  @override
  String unfollowedSnackbar(String username) {
    return 'Vous ne suivez plus @$username';
  }

  @override
  String get cancelRequestTitle => 'Annuler la demande ?';

  @override
  String cancelRequestMessage(String username) {
    return 'Annuler votre demande d\'abonnement à @$username ?';
  }

  @override
  String get cancelRequestConfirm => 'Annuler la demande';

  @override
  String get cancelRequestKeep => 'Conserver';

  @override
  String get undoButton => 'ANNULER';

  @override
  String couldNotUndo(String error) {
    return 'Impossible d\'annuler : $error';
  }

  @override
  String get errorNoInternet =>
      'Pas de connexion internet. Vérifiez votre réseau et réessayez.';

  @override
  String get errorGenericRetry =>
      'Une erreur est survenue. Veuillez réessayer.';

  @override
  String get errorGeneric => 'Une erreur est survenue.';

  @override
  String get fieldHelpTooltip => 'Qu\'est-ce que c\'est ?';

  @override
  String typeToConfirmInstruction(String text) {
    return 'Tapez « $text » pour confirmer :';
  }

  @override
  String get daysLabel => 'j';

  @override
  String get noneOption => 'Aucun';

  @override
  String get discardButton => 'Ignorer';

  @override
  String get discardChangesTitle => 'Abandonner les modifications ?';

  @override
  String get discardChangesMessage =>
      'Vos modifications ne seront pas enregistrées.';

  @override
  String get keepEditingButton => 'Continuer l\'édition';

  @override
  String get orderSavedMessage => 'Ordre enregistré';

  @override
  String get segmentSelectBothStops =>
      'Sélectionnez un arrêt de départ et un arrêt d\'arrivée.';

  @override
  String get segmentStopsMustDiffer =>
      'Les arrêts de départ et d\'arrivée doivent être différents.';

  @override
  String get segmentAddLegFirst =>
      'Ajoutez au moins un tronçon avant d\'enregistrer.';

  @override
  String get segmentAlreadyExistsTitle => 'Segment déjà existant';

  @override
  String get segmentAlreadyExistsMessage =>
      'Un segment relie déjà ces deux arrêts. Que souhaitez-vous faire ?';

  @override
  String get segmentJoin => 'Rejoindre';

  @override
  String get segmentReplace => 'Remplacer';

  @override
  String get segmentFromStopLabel => 'Arrêt de départ';

  @override
  String get segmentToStopLabel => 'Arrêt d\'arrivée';

  @override
  String get visibilityScreenTitle => 'Qui peut voir ça ?';

  @override
  String get visibilityAddPerson => 'Ajouter une personne';

  @override
  String get visibilitySearchByUsername => 'Rechercher par identifiant…';

  @override
  String get couldNotLoadRatings => 'Impossible de charger les évaluations';

  @override
  String get stopNotFound => 'Étape introuvable.';

  @override
  String get mapPickLocationTitle => 'Choisir un emplacement';

  @override
  String get mapConfirmLocation => 'Confirmer l\'emplacement';

  @override
  String get stopCostHint => 'ex. 20';

  @override
  String get unsavedDescriptionTitle => 'Description non enregistrée';

  @override
  String get unsavedDescriptionMessage =>
      'Enregistrer vos modifications avant de quitter ?';

  @override
  String get saveDescriptionLabel => 'Enregistrer la description';

  @override
  String get ratingsTitle => 'Évaluations';

  @override
  String get noRatingsYet => 'Aucune évaluation pour l\'instant';

  @override
  String get ratingsOverallLabel => 'GÉNÉRAL';

  @override
  String get rateThisTrip => 'Évaluer ce voyage';

  @override
  String get deletedUser => 'Utilisateur supprimé';

  @override
  String get annotationContentHint => 'Que doivent savoir les voyageurs ?';

  @override
  String get countryPickerTitle => 'Sélectionner un pays';

  @override
  String get countrySearchHint => 'Rechercher un pays…';

  @override
  String get countryNoneClear => 'Aucun / Effacer';

  @override
  String get languageSearchHint => 'Rechercher une langue…';

  @override
  String get coverChangeButton => 'Modifier';

  @override
  String get coverEditCropButton => 'Ajuster le recadrage';

  @override
  String get coverAdjustTitle => 'Ajuster la photo de couverture';

  @override
  String get mdBoldTooltip => 'Gras';

  @override
  String get mdItalicTooltip => 'Italique';

  @override
  String get mdHeading1Tooltip => 'Titre 1';

  @override
  String get mdHeading2Tooltip => 'Titre 2';

  @override
  String get mdBulletListTooltip => 'Liste à puces';

  @override
  String get mdNumberedListTooltip => 'Liste numérotée';

  @override
  String get mdEditTab => 'Modifier';

  @override
  String get mdPreviewTab => 'Aperçu';

  @override
  String get legCostHint => 'ex. 12,50';

  @override
  String get addLegButton => 'Ajouter un tronçon';

  @override
  String get totalLabel => 'Total';

  @override
  String get reorderOrphanTitle => 'Enregistrer la réorganisation ?';

  @override
  String reorderOrphanMessage(int count, String segments) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count tronçons de transport seront supprimés car leurs arrêts ne seront plus dans des pistes adjacentes :\n\n$segments',
      one:
          '$count tronçon de transport sera supprimé car ses arrêts ne seront plus dans des pistes adjacentes :\n\n$segments',
    );
    return '$_temp0';
  }

  @override
  String get loadingLabel => 'Chargement…';

  @override
  String get usernameRequired => 'L\'identifiant est requis';

  @override
  String get usernameTooShort =>
      'L\'identifiant doit contenir au moins 4 caractères';

  @override
  String get usernameTooLong =>
      'L\'identifiant ne peut pas dépasser 30 caractères';

  @override
  String get usernameInvalidFormat =>
      'Lettres, chiffres, points et tirets bas uniquement. Doit commencer par une lettre et se terminer par une lettre ou un chiffre.';

  @override
  String get usernameConsecutiveSpecial =>
      'Ne peut pas avoir des points ou tirets bas consécutifs';

  @override
  String get displayNameTooLong =>
      'Le nom affiché ne peut pas dépasser 50 caractères';

  @override
  String get comingSoon => 'Bientôt disponible';

  @override
  String get verifyEmailTitle => 'Vérifiez votre e-mail';

  @override
  String get verifyEmailMessage =>
      'Connectez-vous avec Google pour créer des itinéraires, noter et suivre des personnes.';

  @override
  String get verifyEmailButton => 'Vérifier avec Google';

  @override
  String get emailVerifiedSuccess => 'E-mail vérifié — tout est prêt !';

  @override
  String get speaksLabel => 'Parle';

  @override
  String get removeButton => 'Supprimer';

  @override
  String get doneTooltip => 'Terminer';

  @override
  String get addButton => 'Ajouter';

  @override
  String get deleteButton => 'Supprimer';

  @override
  String get deleteAccountTitle => 'Supprimer le compte';

  @override
  String get deleteAccountConfirmTitle => 'Supprimer votre compte ?';

  @override
  String get deleteAccountConfirmMessage =>
      'Votre compte, vos itinéraires, vos abonnements et vos évaluations seront anonymisés ou supprimés conformément à notre politique de confidentialité. Vous serez déconnecté immédiatement. Cette action est irréversible.';

  @override
  String get deleteAccountRequiredText => 'SUPPRIMER MON COMPTE';

  @override
  String get deleteAccountConfirmLabel => 'Supprimer mon compte';

  @override
  String get deleteAccountPasswordError =>
      'Mot de passe incorrect. Veuillez réessayer.';

  @override
  String get deleteAccountGenericError =>
      'Une erreur est survenue. Veuillez réessayer.';

  @override
  String get deleteAccountCannotUndo => 'Cette action est irréversible';

  @override
  String get deleteAccountWillRemove =>
      'La suppression de votre compte supprimera définitivement :';

  @override
  String get deleteAccountBullet1 =>
      'Votre profil et toutes vos données personnelles';

  @override
  String get deleteAccountBullet2 => 'Tous vos itinéraires et étapes';

  @override
  String get deleteAccountBullet3 => 'Vos abonnements et abonnés';

  @override
  String get deleteAccountNote =>
      'Les évaluations que vous avez données à d\'autres itinéraires seront conservées de manière anonyme comme données communautaires.';

  @override
  String get deleteAccountEnterPassword =>
      'Entrez votre mot de passe pour confirmer';

  @override
  String get deleteAccountPasswordLabel => 'Mot de passe';

  @override
  String get deleteAccountPasswordHelpTitle => 'Confirmer le mot de passe';

  @override
  String get deleteAccountPasswordHelpMessage =>
      'Saisissez à nouveau votre mot de passe pour confirmer la suppression. La suppression du compte est permanente et irréversible.';

  @override
  String get deleteAccountButton => 'Supprimer mon compte';

  @override
  String get deleteAnnotationTitle => 'Supprimer l\'annotation ?';

  @override
  String get deleteAnnotationMessage =>
      'Cela supprimera définitivement cette annotation de l\'itinéraire.';

  @override
  String get deleteAnnotationStopMessage =>
      'Cette annotation sera définitivement supprimée.';

  @override
  String get removeTransitTitle => 'Supprimer le transit entre les étapes ?';

  @override
  String get removeTransitMessage =>
      'La connexion entre ces deux étapes sera supprimée. Vous pourrez en ajouter une nouvelle ultérieurement.';

  @override
  String get reorderTracksTitle => 'Réorganiser les pistes';

  @override
  String get shareTooltip => 'Partager';

  @override
  String get editDetailsTooltip => 'Modifier les détails et l\'image';

  @override
  String get descriptionSection => 'Description';

  @override
  String get annotationsSection => 'Annotations';

  @override
  String get addAnnotationButton => 'Ajouter une annotation';

  @override
  String get noAnnotationsYet => 'Aucune annotation pour l\'instant.';

  @override
  String get stopsList => 'Liste des étapes';

  @override
  String get editStopsButton => 'Modifier les étapes';

  @override
  String get addStopTooltip => 'Ajouter une étape';

  @override
  String get reorderTracksTooltip => 'Réorganiser les pistes';

  @override
  String get mapSection => 'Carte';

  @override
  String get openStreetMapContributors => 'Contributeurs OpenStreetMap';

  @override
  String get poweredByOSM => 'Propulsé par OpenStreetMap';

  @override
  String get noStopsYetTapPlus =>
      'Aucune étape. Appuyez sur + pour en ajouter une.';

  @override
  String get communityRating => 'Communauté';

  @override
  String ratingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count évaluations',
      one: '1 évaluation',
    );
    return '$_temp0';
  }

  @override
  String get yourRating => 'Votre évaluation';

  @override
  String get rateIt => 'Évaluer';

  @override
  String deleteOrphanSegmentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer les segments de transit ?',
      one: 'Supprimer le segment de transit ?',
    );
    return '$_temp0';
  }

  @override
  String deleteOrphanSegmentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Il y a $count segments de transit reliant ces deux étapes. Ajouter une étape entre elles les masquera car les étapes ne seront plus adjacentes. Supprimer les segments et continuer ?',
      one:
          'Il y a 1 segment de transit reliant ces deux étapes. Ajouter une étape entre elles le masquera car les étapes ne seront plus adjacentes. Supprimer le segment et continuer ?',
    );
    return '$_temp0';
  }

  @override
  String get deleteAndContinue => 'Supprimer et continuer';

  @override
  String get notSet => 'Non défini';

  @override
  String get stopDetailsView => 'Détails de l\'étape';

  @override
  String get editStopTitle => 'Modifier l\'étape';

  @override
  String get addStopTitle => 'Ajouter une étape';

  @override
  String get editStopTooltip => 'Modifier l\'étape';

  @override
  String get duplicateStopTitle => 'Étape en double';

  @override
  String duplicateStopMessage(String name) {
    return '$name est déjà dans cet itinéraire. Ajouter quand même ?';
  }

  @override
  String get addAnyway => 'Ajouter quand même';

  @override
  String get itineraryUpdatedTitle => 'Itinéraire mis à jour ailleurs';

  @override
  String get itineraryUpdatedMessage =>
      'Cet itinéraire a été modifié depuis un autre appareil. Retournez en arrière et rechargez pour voir la dernière version.';

  @override
  String get goBack => 'Retour';

  @override
  String get deleteStopTitle => 'Supprimer cette étape ?';

  @override
  String get deleteStopMessage =>
      'Cela supprimera l\'étape, ses annotations et tous les segments de transit qui y sont connectés. Cette action est irréversible.';

  @override
  String get viewOnlyTitle => 'Lecture seule';

  @override
  String get viewOnlyMessage =>
      'Appuyez sur le bouton Modifier pour apporter des modifications.';

  @override
  String get searchForPlaceLabel => 'Rechercher un lieu';

  @override
  String get searchAPlaceHelpTitle => 'Rechercher un lieu';

  @override
  String get searchAPlaceHelpMessage =>
      'Saisissez le nom d\'un lieu, d\'un restaurant ou d\'un monument. Sélectionnez un résultat pour remplir automatiquement le nom, l\'adresse et les coordonnées.';

  @override
  String get searchPlaceHintText => 'ex. Tour Eiffel, Paris';

  @override
  String get stopDetailsSectionLabel => 'Détails de l\'étape';

  @override
  String get placeNameLabel => 'Nom du lieu';

  @override
  String get placeNameHelp => 'Nom du lieu, restaurant, monument ou étape.';

  @override
  String get placeNameRequired => 'Le nom du lieu est requis';

  @override
  String get addressLabel => 'Adresse';

  @override
  String get addressHelp =>
      'Adresse postale ou description de la zone. Optionnel.';

  @override
  String get coordinatesHelp =>
      'La localisation sur la carte pour cette étape. Appuyez sur « Sélectionner sur la carte » pour la définir ou l\'ajuster.';

  @override
  String get pickOnMap => 'Sélectionner sur la carte';

  @override
  String get placeTypeLabel => 'Type de lieu';

  @override
  String get placeTypeHelp =>
      'Le type de lieu (ex. manger & boire, dormir, site touristique). Utilisé pour le filtrage et l\'icône de la carte.';

  @override
  String get selectPlaceType => 'Sélectionner le type';

  @override
  String get recommendedTimeLabel => 'Temps recommandé à passer';

  @override
  String get timeToSpendHelp =>
      'Approximativement combien de temps vous prévoyez de rester ici. Appuyez pour définir les jours, heures et minutes.';

  @override
  String get stopIsFree => 'Cette étape est gratuite';

  @override
  String get freeHelp => 'Activez si la visite de ce lieu ne coûte rien.';

  @override
  String get costLabel => 'Coût';

  @override
  String get costHelp =>
      'Coût approximatif par personne, dans la devise de l\'itinéraire.';

  @override
  String get enterValidNumber => 'Entrez un nombre valide';

  @override
  String get thoughtsLabel => 'Réflexions';

  @override
  String get thoughtsHelp =>
      'Votre avis personnel sur cette étape — ce à quoi s\'attendre, ce que vous avez aimé, ce à éviter, conseils pratiques.';

  @override
  String get annotationsLabel => 'Annotations';

  @override
  String get annotationsHelp =>
      'Notes courtes taguées (conseil, prudence, éviter, info) attachées à cette étape.';

  @override
  String get saveChangesButton => 'Enregistrer';

  @override
  String get addStopButton => 'Ajouter l\'étape';

  @override
  String get deleteStopButton => 'Supprimer l\'étape';

  @override
  String get timeToSpendModalTitle => 'Temps à passer';

  @override
  String get editTransitTitle => 'Modifier le transit';

  @override
  String get addTransitTitle => 'Ajouter un transit';

  @override
  String get updateTransitButton => 'Mettre à jour le transit';

  @override
  String get transportModeLabel => 'Mode';

  @override
  String get transportModeHelp =>
      'Comment vous voyagez sur ce tronçon (marche, bus, train, ferry, etc.).';

  @override
  String get transitLineLabel => 'Ligne (optionnel)';

  @override
  String get transitLineHelp =>
      'Optionnel. Le numéro ou nom de la ligne (ex. « Bus 42 », « M1 »).';

  @override
  String get transitDirectionLabel => 'Direction (optionnel)';

  @override
  String get transitDirectionHelp =>
      'Optionnel. La destination de la ligne (ex. « Vers le nord », « Châtelet »).';

  @override
  String get durationLabel => 'Durée';

  @override
  String get durationHelp =>
      'Combien de temps dure ce tronçon en heures et minutes.';

  @override
  String get legCostHelp =>
      'Coût approximatif dans la devise de l\'itinéraire. Désactivé quand « Gratuit » est activé.';

  @override
  String get hoursLabel => 'h';

  @override
  String get minutesLabel => 'min';

  @override
  String get freeLegLabel => 'Gratuit';

  @override
  String get freeLegHelp =>
      'Activez si ce tronçon ne coûte rien (marche, correspondance incluse, etc.).';

  @override
  String get legThoughtsLabel => 'Réflexions (optionnel)';

  @override
  String get legThoughtsHelp =>
      'Optionnel. Tout ce qui est utile à savoir sur ce tronçon — conseils de réservation, instructions de correspondance, surprises sur les tarifs.';

  @override
  String get annotationTypeLabel => 'Type';

  @override
  String get annotationTypeHelp =>
      'Conseil : une astuce utile. Prudence : soyez prudent. Éviter : à ne pas faire. Info : une note neutre.';

  @override
  String get annotationAdvice => 'Conseil';

  @override
  String get annotationCaution => 'Prudence';

  @override
  String get annotationAvoid => 'Éviter';

  @override
  String get annotationInfo => 'Info';

  @override
  String get annotationContentLabel => 'Contenu *';

  @override
  String get annotationContentHelp =>
      'Décrivez votre conseil, mise en garde, avertissement ou note en une ou deux phrases.';

  @override
  String get annotationContentRequired => 'Le contenu est requis';

  @override
  String get editAnnotationTitle => 'Modifier l\'annotation';

  @override
  String get addAnnotationDialogTitle => 'Ajouter une annotation';

  @override
  String get saveButton => 'Enregistrer';

  @override
  String get moveStopTitle => 'Déplacer l\'étape';

  @override
  String moveStopDescription(int max) {
    return 'Choisissez une piste existante, un espace pour créer une nouvelle piste, ou extrayez dans sa propre piste. Les pistes au maximum de $max étapes sont désactivées.';
  }

  @override
  String get extractIntoOwnTrack => 'Extraire dans sa propre piste';

  @override
  String get moveButton => 'Déplacer';

  @override
  String moveStopMoved(String destination) {
    return 'Déplacé vers $destination';
  }

  @override
  String get itineraryChangedElsewhere =>
      'Itinéraire modifié ailleurs — fermez et rouvrez pour voir la dernière version.';

  @override
  String get moveStopOrphan1 =>
      'C\'est la dernière étape de sa piste — la piste sera supprimée de l\'itinéraire.';

  @override
  String moveStopOrphanSegments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segments de transit seront supprimés car leurs étapes ne seront plus dans des pistes adjacentes.',
      one:
          '1 segment de transit sera supprimé car ses étapes ne seront plus dans des pistes adjacentes.',
    );
    return '$_temp0';
  }

  @override
  String get moveStopNewTrack => 'Nouvelle piste';

  @override
  String moveStopNewTrackBefore(int n) {
    return 'Nouvelle piste avant la piste $n';
  }

  @override
  String moveStopNewTrackAfter(int n) {
    return 'Nouvelle piste après la piste $n';
  }

  @override
  String moveStopNewTrackBetween(int a, int b) {
    return 'Nouvelle piste entre la piste $a et la piste $b';
  }

  @override
  String get moveStopCurrentSuffix => '  •  actuelle';

  @override
  String moveStopFull(int max) {
    return 'Pleine $max/$max';
  }

  @override
  String extractSubtitle(String trackName) {
    return 'Extrait cette étape de « $trackName » — la nouvelle piste se place juste après.';
  }

  @override
  String get removeRatingTitle => 'Supprimer votre évaluation ?';

  @override
  String get removeRatingMessage =>
      'Votre évaluation sera supprimée et la moyenne sera mise à jour pour tous les visiteurs de cet itinéraire.';

  @override
  String get rateItineraryTitle => 'Évaluer cet itinéraire';

  @override
  String get overallRatingLabel => 'Global *';

  @override
  String get overallRatingHelp =>
      'Requis. Votre évaluation globale de cet itinéraire, de 1 à 5 étoiles.';

  @override
  String get ratingThanksMessage => 'Merci ! Votre évaluation aide les autres.';

  @override
  String get yourImpressionLabel => 'Votre impression (optionnel)';

  @override
  String get yourImpressionHelp =>
      'Optionnel. Partagez ce qui vous a marqué — points forts, regrets, à qui vous le recommanderiez.';

  @override
  String get removeMyRatingTooltip => 'Supprimer mon évaluation';

  @override
  String get wantToShareMore => 'Vous voulez en dire plus ? (optionnel)';

  @override
  String get safetyLabel => 'Sécurité';

  @override
  String get safetyHelp =>
      'Optionnel. À quel point vous vous êtes senti en sécurité pendant ce voyage.';

  @override
  String get experienceLabel => 'Expérience';

  @override
  String get experienceHelp =>
      'Optionnel. À quel point le voyage était agréable et mémorable.';

  @override
  String get accessibilityLabel => 'Accessibilité';

  @override
  String get accessibilityHelp =>
      'Optionnel. À quel point l\'itinéraire est accessible (mobilité, langue, signalisation).';

  @override
  String get familyFriendlyLabel => 'Familial';

  @override
  String get familyFriendlyHelp =>
      'Optionnel. À quel point ce voyage convient aux familles avec enfants.';

  @override
  String get showOptionalFields => 'Afficher les champs optionnels';

  @override
  String get hideOptionalFields => 'Masquer les champs optionnels';
}
