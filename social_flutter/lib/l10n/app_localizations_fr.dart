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
  String get feedTopEmpty => 'Pas assez de voyages évalués — voir Récents.';

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
  String get loginEmailLabel => 'E-mail ou nom d\'utilisateur';

  @override
  String get loginEmailHelp =>
      'Connectez-vous avec l\'e-mail avec lequel vous vous êtes inscrit, ou votre @identifiant.';

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
  String get registerEmail => 'E-mail *';

  @override
  String get registerEmailHelp =>
      'Utilisé pour se connecter et récupérer votre compte. Nous ne l\'affichons jamais publiquement.';

  @override
  String get registerEmailHint => 'vous@exemple.com';

  @override
  String get registerEmailRequired => 'L\'e-mail est requis.';

  @override
  String get registerEmailInvalid => 'Veuillez entrer un e-mail valide.';

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
  String get addStopHintTitle => 'Ajoutez vos étapes';

  @override
  String get addStopHintMessage =>
      'Pour ajouter des étapes, appuyez sur Modifier ✎ en haut.';

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
  String get tapToSeeStops => 'Toucher pour voir les étapes';

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
  String get securitySection => 'Sécurité';

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
  String get languageArabic => 'العربية';

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
      'Une image 1200×630 affichée sur la carte de l\'itinéraire et les aperçus de liens. Faites glisser dans la zone de recadrage pour repositionner.';

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
      'Optionnel. Un résumé du voyage. Utilisez la barre d\'outils pour mettre du texte en gras ou en italique, ajouter des titres et créer des listes à puces ou numérotées. Passez à l\'onglet Aperçu pour voir le rendu final.';

  @override
  String get addDescriptionLabel => 'Ajouter une description';

  @override
  String get currencyLabel => 'Devise';

  @override
  String get currencyHelp =>
      'Devise par défaut pour tous les coûts des étapes et des transports de cet itinéraire.';

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
      'Sélectionnez une étape de départ et une étape d\'arrivée.';

  @override
  String get segmentStopsMustDiffer =>
      'Les étapes de départ et d\'arrivée doivent être différentes.';

  @override
  String get segmentAddLegFirst =>
      'Ajoutez au moins un tronçon avant d\'enregistrer.';

  @override
  String get segmentAlreadyExistsTitle => 'Segment déjà existant';

  @override
  String get segmentAlreadyExistsMessage =>
      'Un segment relie déjà ces deux étapes. Que souhaitez-vous faire ?';

  @override
  String get segmentJoin => 'Rejoindre';

  @override
  String get segmentReplace => 'Remplacer';

  @override
  String get segmentFromStopLabel => 'Étape de départ';

  @override
  String get segmentToStopLabel => 'Étape d\'arrivée';

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
          '$count segments de transit seront supprimés car leurs étapes ne seront plus dans des pistes adjacentes :\n\n$segments',
      one:
          '$count segment de transit sera supprimé car ses étapes ne seront plus dans des pistes adjacentes :\n\n$segments',
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
      'Vérifiez votre e-mail pour créer des voyages, évaluer des itinéraires et suivre des personnes.';

  @override
  String get verifyEmailButton => 'Vérifier avec Google';

  @override
  String get emailVerifiedSuccess => 'E-mail vérifié — tout est prêt !';

  @override
  String get resendVerificationButton => 'Renvoyer l\'e-mail de vérification';

  @override
  String get verificationEmailSent =>
      'E-mail de vérification envoyé — vérifiez votre boîte de réception.';

  @override
  String get forgotPasswordTitle => 'Réinitialiser votre mot de passe';

  @override
  String get forgotPasswordSubtitle =>
      'Entrez l\'e-mail de votre compte et nous vous enverrons un lien pour définir un nouveau mot de passe.';

  @override
  String get forgotPasswordEmailLabel => 'E-mail';

  @override
  String get forgotPasswordSubmit => 'Envoyer le lien';

  @override
  String get forgotPasswordSentTitle => 'Vérifiez votre e-mail';

  @override
  String get forgotPasswordSentBody =>
      'Si un compte existe pour cet e-mail, nous avons envoyé un lien de réinitialisation. Vérifiez votre boîte de réception et vos spams.';

  @override
  String get changePasswordTitle => 'Changer le mot de passe';

  @override
  String get changePasswordSubtitle =>
      'Saisissez votre mot de passe actuel, puis choisissez-en un nouveau. Le changement déconnecte tous les autres appareils.';

  @override
  String get changePasswordCurrentLabel => 'Mot de passe actuel';

  @override
  String get changePasswordNewLabel => 'Nouveau mot de passe';

  @override
  String get changePasswordConfirmLabel => 'Confirmer le nouveau mot de passe';

  @override
  String get changePasswordMismatch =>
      'Les mots de passe ne correspondent pas.';

  @override
  String get changePasswordSameAsOld =>
      'Le nouveau mot de passe doit être différent de l\'actuel.';

  @override
  String get changePasswordSubmit => 'Changer le mot de passe';

  @override
  String get changePasswordConfirmMessage =>
      'Cela vous déconnectera de tous vos autres appareils. Continuer ?';

  @override
  String get changePasswordSuccess =>
      'Mot de passe changé. Les autres appareils ont été déconnectés.';

  @override
  String get backToSignIn => 'Retour à la connexion';

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
  String get placeTypeEatDrink => 'Manger & Boire';

  @override
  String get placeTypeSleep => 'Dormir';

  @override
  String get placeTypePray => 'Prier';

  @override
  String get placeTypeLearnSee => 'Apprendre & Voir';

  @override
  String get placeTypeBuy => 'Acheter';

  @override
  String get placeTypePlayWatch => 'Jouer & Regarder';

  @override
  String get placeTypeNature => 'Nature';

  @override
  String get placeTypeTransport => 'Transport';

  @override
  String get placeTypeHealBathe => 'Soins & Bains';

  @override
  String get placeTypeEntertainment => 'Divertissement';

  @override
  String get placeTypeSight => 'Site';

  @override
  String get placeTypeHintEatDrink =>
      'café, restaurant, bar, boulangerie, food truck';

  @override
  String get placeTypeHintSleep => 'hôtel, auberge, camping, gîte, lodge';

  @override
  String get placeTypeHintPray =>
      'église, mosquée, temple, synagogue, sanctuaire';

  @override
  String get placeTypeHintLearnSee =>
      'musée, galerie, bibliothèque, aquarium, observatoire';

  @override
  String get placeTypeHintBuy => 'boutique, marché, centre commercial, échoppe';

  @override
  String get placeTypeHintPlayWatch =>
      'stade, salle de sport, arène, court, bowling';

  @override
  String get placeTypeHintNature => 'plage, parc, forêt, montagne, cascade';

  @override
  String get placeTypeHintTransport =>
      'aéroport, gare, arrêt de bus, terminal de ferry';

  @override
  String get placeTypeHintHealBathe =>
      'spa, source chaude, piscine, sauna, bains';

  @override
  String get placeTypeHintEntertainment =>
      'théâtre, cinéma, salle de concert, boîte de nuit';

  @override
  String get placeTypeHintSight =>
      'monument, point de vue, château, place, ruines';

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
      'Votre avis personnel sur cette étape — ce à quoi s\'attendre, ce que vous avez aimé, ce à éviter, conseils pratiques. Utilisez la barre d\'outils pour ajouter du gras, de l\'italique, des titres ou des listes à puces.';

  @override
  String get annotationsLabel => 'Annotations';

  @override
  String get annotationsHelp =>
      'Notes courtes taguées (conseil, prudence, éviter, info) attachées à cette étape. Utile pour les avertissements ou les conseils.';

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
      'Comment vous voyagez sur ce tronçon (marche, bus, train, ferry, etc.). Certains modes affichent des champs supplémentaires pour la ligne et la direction.';

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
  String get crowdednessLabel => 'Tranquillité';

  @override
  String get crowdednessHelp =>
      'Optionnel. À quel point l\'endroit était peu fréquenté et spacieux — 5 = agréablement peu fréquenté, 1 = bondé.';

  @override
  String get showOptionalFields => 'Afficher les champs optionnels';

  @override
  String get hideOptionalFields => 'Masquer les champs optionnels';

  @override
  String get transportModeWalk => 'Marche';

  @override
  String get transportModeBus => 'Bus';

  @override
  String get transportModeTram => 'Tramway';

  @override
  String get transportModeMetro => 'Métro';

  @override
  String get transportModeTrain => 'Train';

  @override
  String get transportModeTaxi => 'Taxi';

  @override
  String get transportModeUber => 'Uber';

  @override
  String get transportModeBike => 'Vélo';

  @override
  String get transportModeFerry => 'Ferry';

  @override
  String get transportModeCar => 'Voiture';

  @override
  String get transportModeAirplane => 'Avion';

  @override
  String get dimensionOverall => 'Globale';

  @override
  String get dimensionOverallDesc => 'Impression générale';

  @override
  String get dimensionSafetyDesc =>
      'À quel point vous vous êtes senti en sécurité';

  @override
  String get dimensionExperienceDesc => 'Qualité de l\'expérience globale';

  @override
  String get dimensionAccessibilityDesc => 'Facilité d\'accès pour tous';

  @override
  String get dimensionFamilyFriendlyDesc =>
      'Convient aux enfants et aux familles';

  @override
  String get dimensionCrowdednessDesc =>
      'À quel point l\'endroit était peu fréquenté et spacieux';

  @override
  String dimensionRatingTitle(String label) {
    return 'Évaluation $label';
  }

  @override
  String noRatingsYetFor(String label) {
    return 'Aucune évaluation pour $label pour l\'instant';
  }

  @override
  String basedOnRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Basé sur $count évaluations',
      one: 'Basé sur $count évaluation',
    );
    return '$_temp0';
  }

  @override
  String get ratersLabel => 'Évaluateurs';

  @override
  String get annotationAdviceDesc =>
      'Quelque chose d\'utile ou une astuce de pro.';

  @override
  String get annotationCautionDesc => 'Faites attention — surprises possibles.';

  @override
  String get annotationAvoidDesc => 'À ne pas faire. Gagnez du temps.';

  @override
  String get annotationInfoDesc => 'Un fait neutre bon à savoir.';

  @override
  String get unknownUser => 'Inconnu';

  @override
  String timeAgoMonths(int count) {
    return 'il y a $count mois';
  }

  @override
  String timeAgoDays(int count) {
    return 'il y a $count j';
  }

  @override
  String timeAgoHours(int count) {
    return 'il y a $count h';
  }

  @override
  String timeAgoMinutes(int count) {
    return 'il y a $count min';
  }

  @override
  String get timeJustNow => 'À l\'instant';

  @override
  String get yearsAbbrev => 'a';

  @override
  String get timeLabel => 'Temps';

  @override
  String get transitLabel => 'Transit';

  @override
  String get noLegsYetTapAdd =>
      'Aucun tronçon. Appuyez sur ＋ pour en ajouter un.';

  @override
  String get segmentNeedsOneLeg =>
      'Un segment doit avoir au moins un tronçon. Supprimez plutôt le segment.';

  @override
  String fromStopName(String name) {
    return 'Depuis $name';
  }

  @override
  String toStopName(String name) {
    return 'Vers $name';
  }

  @override
  String get visibilityPublicDesc =>
      'Toute personne disposant du lien peut voir.';

  @override
  String get visibilityFollowersDesc =>
      'Uniquement les personnes qui vous suivent.';

  @override
  String get visibilityRestrictedDesc =>
      'Uniquement les personnes que vous autorisez.';

  @override
  String get visibilityOnlyMeDesc => 'Vous uniquement.';

  @override
  String get saveItineraryFirstAllowlist =>
      'Enregistrez d\'abord l\'itinéraire, puis gérez votre liste d\'accès depuis l\'écran de modification.';

  @override
  String get allowlistLabel => 'Liste d\'accès';

  @override
  String personCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes',
      one: '$count personne',
    );
    return '$_temp0';
  }

  @override
  String removedFromAllowlist(String name) {
    return '$name retiré de la liste d\'accès';
  }

  @override
  String get addPeople => 'Ajouter des personnes';

  @override
  String get otherOption => 'Autre';

  @override
  String get thisItineraryFallback => 'cet itinéraire';

  @override
  String get discardReorderMessage =>
      'Votre réorganisation ne sera pas enregistrée.';

  @override
  String get emptyTrackName => '(vide)';

  @override
  String get unnamedStop => '(sans nom)';

  @override
  String get unknownStop => '(inconnu)';

  @override
  String get dragToChangeTrackOrder =>
      'Faites glisser pour changer l\'ordre des pistes';

  @override
  String transitSegmentsWillBeDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments de transit seront supprimés',
      one: '1 segment de transit sera supprimé',
    );
    return '$_temp0';
  }

  @override
  String andMoreCount(int count) {
    return '… et $count de plus';
  }

  @override
  String altsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alt.',
      one: '$count alt.',
    );
    return '$_temp0';
  }

  @override
  String segmentToWillBeDeleted(String name) {
    return '→ $name  —  le segment sera supprimé';
  }

  @override
  String get reorderAlternativesTitle => 'Réorganiser les alternatives';

  @override
  String get reorderAlternativesHint =>
      'Faites glisser pour changer l\'option qui apparaît en premier. Appuyez sur Enregistrer pour appliquer.';

  @override
  String get emptyTrackLabel => '(piste vide)';

  @override
  String get moveStopToLabel => 'Déplacer l\'étape vers';

  @override
  String get messageLabel => 'Message';

  @override
  String get annotationKeepShortHint =>
      'Restez concis — moins de 200 caractères pour une meilleure lisibilité sur petits écrans.';

  @override
  String get transportModeSection => 'Mode de transport';

  @override
  String get lineDirectionSection => 'Ligne et direction';

  @override
  String get durationCostSection => 'Durée et coût';

  @override
  String get allRatersLabel => 'Tous les évaluateurs';

  @override
  String travelersRatedThis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voyageurs ont évalué cet itinéraire',
      one: '$count voyageur a évalué cet itinéraire',
    );
    return '$_temp0';
  }

  @override
  String get byDimensionLabel => 'Par dimension';

  @override
  String get notEnoughRatings => 'Pas assez d\'évaluations';

  @override
  String get youRatedThis => 'Vous avez évalué';

  @override
  String get changeButton => 'Modifier';

  @override
  String get hideReview => 'Masquer l\'avis';

  @override
  String get readReview => 'Lire l\'avis';

  @override
  String get notesLabel => 'Notes';

  @override
  String get viewLess => 'voir moins';

  @override
  String get viewMore => '… voir plus';

  @override
  String get addNoteButton => 'Ajouter une note';

  @override
  String get imageTooLarge => 'L\'image est trop volumineuse (max 10 Mo).';

  @override
  String get couldNotLoadImage =>
      'Impossible de charger l\'image. Veuillez en essayer une autre.';

  @override
  String get pinchToZoomHint =>
      'Pincez pour zoomer · Faites glisser pour repositionner';

  @override
  String get addCoverImage => 'Ajouter une image de couverture';

  @override
  String get coverOptionalMapFallback =>
      'Optionnel — la carte sera utilisée sinon.';

  @override
  String get mapTapToPlacePin => 'Appuyez sur la carte pour placer un repère';

  @override
  String get mapTapToMovePin =>
      'Appuyez ailleurs pour déplacer le repère, puis appuyez sur Confirmer';

  @override
  String get nothingToPreview => 'Rien à prévisualiser pour l\'instant.';

  @override
  String get rateOverallFirstHint =>
      'Évaluez votre impression générale. Ensuite, vous pourrez en dire plus.';

  @override
  String get splashTagline =>
      'Découvrez et partagez des itinéraires de voyage\ncréés par de vrais explorateurs';

  @override
  String get splashMotto => 'Explorez le monde, une route à la fois';

  @override
  String get tripsPillLabel => 'voyages';

  @override
  String get stopsPillLabel => 'étapes';

  @override
  String get travelledPillLabel => 'de voyage';

  @override
  String get stopFallbackName => 'Étape';

  @override
  String get undoLabel => 'Annuler';

  @override
  String get updateYourRating => 'Modifier votre évaluation';

  @override
  String get moveActionLabel => 'déplacer';

  @override
  String get reorderActionLabel => 'réorganiser';

  @override
  String get aStopFallback => 'Une étape';

  @override
  String get locationLabel => 'Localisation';

  @override
  String get noLocationSet => 'Aucune localisation définie';

  @override
  String get detailsSection => 'Détails';

  @override
  String get addLanguageTitle => 'Ajouter une langue';

  @override
  String alreadyInItinerary(String name) {
    return '$name est déjà dans cet itinéraire.';
  }

  @override
  String stopNumberOfTotal(int n, int total) {
    return 'Étape $n sur $total';
  }

  @override
  String shareCaption(String title, String stops, String duration) {
    return 'Découvrez « $title » sur Ntripi — $stops, $duration';
  }

  @override
  String get apiErrorNotAuthenticated => 'Vous n\'êtes pas connecté.';

  @override
  String get apiErrorAccountDeactivated => 'Votre compte a été désactivé.';

  @override
  String get apiErrorEmailUnverified =>
      'Vérifiez votre e-mail via Google pour effectuer cette action.';

  @override
  String get apiErrorItineraryNotFound => 'Itinéraire introuvable.';

  @override
  String get apiErrorItineraryNotOwner =>
      'Vous n\'avez pas la permission de modifier cet itinéraire.';

  @override
  String get apiErrorIfMatchRequired =>
      'Cette modification n\'a pas pu être enregistrée — rechargez et réessayez.';

  @override
  String get apiErrorItineraryStale =>
      'L\'itinéraire a été modifié — veuillez recharger.';

  @override
  String get apiErrorWaitlistContactRequired =>
      'Indiquez au moins un e-mail ou un numéro WhatsApp.';

  @override
  String get apiErrorGoogleTokenInvalid => 'Jeton Google invalide.';

  @override
  String get apiErrorInvalidGrant =>
      'Votre session a expiré. Veuillez vous reconnecter.';

  @override
  String get apiErrorStopNotFound => 'Étape introuvable.';

  @override
  String get apiErrorTrackNotFound =>
      'Piste introuvable ou n\'appartenant pas à cet itinéraire.';

  @override
  String get apiErrorSegmentNotFound => 'Segment de transit introuvable.';

  @override
  String get apiErrorLegNotFound => 'Tronçon de transport introuvable.';

  @override
  String get apiErrorItineraryAccessDenied =>
      'Vous n\'avez pas accès à cet itinéraire.';

  @override
  String get apiErrorAllowlistRestrictedOnly =>
      'La liste d\'accès ne s\'applique qu\'aux itinéraires restreints.';

  @override
  String get apiErrorUserNotFound => 'Utilisateur introuvable.';

  @override
  String get apiErrorAllowlistUserExists => 'Cet utilisateur a déjà accès.';

  @override
  String get apiErrorAllowlistUserNotFound =>
      'Utilisateur introuvable dans la liste d\'accès.';

  @override
  String get apiErrorRankCollision => 'Conflit d\'ordre — veuillez réessayer.';

  @override
  String get apiErrorAnnotationNotFound => 'Annotation introuvable.';

  @override
  String get apiErrorRatingNotFound =>
      'Vous n\'avez pas évalué cet itinéraire.';

  @override
  String get apiErrorSegmentAlreadyExists =>
      'Un segment relie déjà ces deux étapes.';

  @override
  String get apiErrorIncorrectPassword => 'Mot de passe incorrect.';

  @override
  String get apiErrorLoginInvalid =>
      'E-mail/identifiant ou mot de passe incorrect.';

  @override
  String get apiErrorCannotFollowSelf =>
      'Vous ne pouvez pas vous suivre vous-même.';

  @override
  String get apiErrorNotFollowing => 'Vous ne suivez pas cet utilisateur.';

  @override
  String get apiErrorFollowRequestNotFound =>
      'Demande d\'abonnement introuvable.';

  @override
  String get apiErrorFollowRequestAlreadyAccepted =>
      'Cette demande d\'abonnement a déjà été acceptée.';

  @override
  String get apiErrorCannotRejectRequest =>
      'Vous ne pouvez pas refuser cette demande d\'abonnement.';

  @override
  String get apiErrorAccountPrivate => 'Ce compte est privé.';

  @override
  String get apiErrorTosRequired =>
      'Vous devez accepter les Conditions d\'utilisation pour vous inscrire.';

  @override
  String get apiErrorUsernameTaken => 'Cet identifiant est déjà pris.';

  @override
  String get apiErrorEmailTaken => 'Un compte existe déjà avec cet e-mail.';
}
