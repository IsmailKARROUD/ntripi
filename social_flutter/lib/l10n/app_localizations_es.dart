// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get required => 'Obligatorio';

  @override
  String get retry => 'Reintentar';

  @override
  String get dismiss => 'Descartar';

  @override
  String get seeAll => 'Ver todo';

  @override
  String get back => 'Atrás';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navProfile => 'Perfil';

  @override
  String get navItineraries => 'Itinerarios';

  @override
  String get navFeed => 'Feed';

  @override
  String get navSaved => 'Guardados';

  @override
  String get saveItineraryTooltip => 'Guardar itinerario';

  @override
  String get unsaveItineraryTooltip => 'Quitar de guardados';

  @override
  String get savedItinerariesTitle => 'Guardados';

  @override
  String get noSavedItinerariesYet =>
      'Aún no tienes itinerarios guardados. Toca el marcador en cualquier itinerario para guardarlo aquí.';

  @override
  String get searchSavedHint => 'Buscar en guardados…';

  @override
  String get savedSearchNoResults =>
      'Ningún itinerario guardado coincide con tu búsqueda.';

  @override
  String get feedTitle => 'Descubrir';

  @override
  String get feedTabTop => 'Destacados';

  @override
  String get feedTabRecent => 'Recientes';

  @override
  String get feedEmpty => 'Aún no hay itinerarios públicos. ¡Vuelve pronto!';

  @override
  String get feedTopEmpty =>
      'Aún no hay suficientes viajes valorados: consulta Recientes.';

  @override
  String get offlineBanner =>
      '¡Estás sin conexión! Algunas funciones pueden no estar disponibles.';

  @override
  String get offlineActionTitle => 'Estás sin conexión';

  @override
  String get offlineActionMessage =>
      'No se pueden hacer cambios sin conexión a internet. Vuelve a conectarte e inténtalo de nuevo.';

  @override
  String get downloadBanner =>
      'Para una mejor experiencia, descarga la app de Ntripi.';

  @override
  String get downloadBannerButton => 'Descargar';

  @override
  String get loginTitle => 'Bienvenido de nuevo';

  @override
  String get loginSubtitle => 'Inicia sesión para continuar tu viaje';

  @override
  String get loginEmailLabel => 'Correo o nombre de usuario';

  @override
  String get loginEmailHelp =>
      'Inicia sesión con el correo con el que te registraste o con tu @usuario.';

  @override
  String get loginEmailHint => 'tu@ejemplo.com o @usuario';

  @override
  String get loginPasswordLabel => 'Contraseña';

  @override
  String get loginPasswordHelp =>
      'La contraseña de tu cuenta. Toca el icono del ojo para mostrarla u ocultarla.';

  @override
  String get loginForgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get loginSignIn => 'Iniciar sesión';

  @override
  String get loginNoAccount => '¿No tienes cuenta? ';

  @override
  String get loginSignUp => 'Regístrate';

  @override
  String get loginOrContinueWith => 'o continúa con';

  @override
  String get registerTitle => 'Crear cuenta';

  @override
  String get registerSubtitle =>
      'Únete a miles de exploradores que comparten rutas';

  @override
  String get registerDisplayName => 'Nombre visible';

  @override
  String get registerDisplayNameHelp =>
      'Cómo aparece tu nombre ante los demás. Hasta 50 caracteres, cualquier idioma y emojis. Si lo dejas vacío, se usa @usuario.';

  @override
  String get registerDisplayNameHint => 'Tu nombre';

  @override
  String get registerUsername => 'Nombre de usuario *';

  @override
  String get registerUsernameHelp =>
      'Tu @usuario único. Solo minúsculas, números y guiones bajos. No se puede cambiar después.';

  @override
  String get registerUsernameHint => 'tuusuario';

  @override
  String get registerDob => 'Fecha de nacimiento *';

  @override
  String get registerDobHelp =>
      'Ntripi es para personas de 16 años o más. Te la pedimos una sola vez, nunca aparece en tu perfil y los demás usuarios nunca la ven.';

  @override
  String get registerDobHint => 'Selecciona tu fecha de nacimiento';

  @override
  String get registerDobRequired => 'Tu fecha de nacimiento es obligatoria.';

  @override
  String registerDobTooYoung(int age) {
    return 'Debes tener al menos $age años para usar Ntripi.';
  }

  @override
  String get dobPickerHelp => 'Selecciona tu fecha de nacimiento';

  @override
  String get dobFromGoogle => 'Obtenida de tu cuenta de Google';

  @override
  String get googleConsentDobLabel => 'Fecha de nacimiento';

  @override
  String get acceptTermsDobPrompt =>
      'También necesitamos tu fecha de nacimiento. Ntripi es para personas de 16 años o más.';

  @override
  String get errorUnderage => 'Debes tener al menos 16 años para usar Ntripi.';

  @override
  String get errorDobRequired =>
      'Se necesita una fecha de nacimiento para continuar.';

  @override
  String get registerEmail => 'Correo *';

  @override
  String get registerEmailHelp =>
      'Se usa para iniciar sesión y recuperar tu cuenta. Nunca lo mostramos públicamente.';

  @override
  String get registerEmailHint => 'tu@ejemplo.com';

  @override
  String get registerEmailRequired => 'El correo es obligatorio.';

  @override
  String get registerEmailInvalid => 'Introduce un correo válido.';

  @override
  String get registerPassword => 'Contraseña *';

  @override
  String get registerPasswordHelp =>
      'Al menos 8 caracteres con al menos un número.';

  @override
  String get registerPasswordHint => 'Mín. 8 caracteres';

  @override
  String get registerPasswordRequired => 'La contraseña es obligatoria.';

  @override
  String get registerPasswordTooShort => 'Debe tener al menos 8 caracteres.';

  @override
  String get registerPasswordNoDigit => 'Debe contener al menos un número.';

  @override
  String get passwordTooLong =>
      'La contraseña es demasiado larga: hasta 72 caracteres (menos con letras no latinas).';

  @override
  String get registerConfirmPassword => 'Confirmar contraseña *';

  @override
  String get registerConfirmPasswordHelp =>
      'Escribe tu contraseña de nuevo para asegurarte de que coincide.';

  @override
  String get registerConfirmRequired => 'Confirma tu contraseña.';

  @override
  String get registerConfirmMismatch => 'Las contraseñas no coinciden.';

  @override
  String get registerTosAgree => 'Acepto los ';

  @override
  String get registerTos => 'Términos del servicio';

  @override
  String get registerTosComma => ', las ';

  @override
  String get registerGuidelines => 'Normas de la comunidad';

  @override
  String get registerTosAnd => ' y la ';

  @override
  String get registerPrivacyPolicy => 'Política de privacidad';

  @override
  String get registerTosSuffix => '. ';

  @override
  String get registerTosProhibited =>
      'Entiendo que el contenido objetable y el comportamiento abusivo están terminantemente prohibidos.';

  @override
  String get registerTosHelp =>
      'Debes aceptar los Términos del servicio, las Normas de la comunidad y la Política de privacidad para crear una cuenta. Toca los enlaces destacados para leerlos.';

  @override
  String get registerTosRequired =>
      'Debes aceptar los Términos del servicio y las Normas de la comunidad.';

  @override
  String get registerTosTitle => 'Términos del servicio';

  @override
  String get registerGuidelinesTitle => 'Normas de la comunidad';

  @override
  String get legalDocLoadFailed =>
      'No hemos podido cargar este documento. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get legalDocOpenInBrowser => 'Abrir en el navegador';

  @override
  String get googleTosTitle => 'Un paso más';

  @override
  String get googleTosSubtitle =>
      'Estás creando una cuenta nueva de Ntripi. Acepta nuestras condiciones para continuar.';

  @override
  String get googleTosAccept => 'Aceptar y continuar';

  @override
  String get acceptTermsTitle => 'Nuestras condiciones han cambiado';

  @override
  String get acceptTermsBody =>
      'Hemos actualizado nuestras Condiciones de uso, Normas de la comunidad y Política de privacidad. Léelas y acéptalas para seguir usando Ntripi.';

  @override
  String get acceptTermsButton => 'Aceptar y continuar';

  @override
  String get registerCreateAccount => 'Crear cuenta';

  @override
  String get registerAlreadyHaveAccount => '¿Ya tienes cuenta? ';

  @override
  String get registerSignIn => 'Inicia sesión';

  @override
  String get followers => 'Seguidores';

  @override
  String get following => 'Siguiendo';

  @override
  String get latestTrip => 'ÚLTIMO VIAJE';

  @override
  String get whereIveBeen => 'DÓNDE HE ESTADO';

  @override
  String get noStopsYet => 'Aún no hay paradas';

  @override
  String get addFirstStop => 'Añadir la primera parada';

  @override
  String get addStopHintTitle => 'Añade tus paradas';

  @override
  String get addStopHintMessage =>
      'Para añadir paradas, toca Editar ✎ en la parte superior.';

  @override
  String get addCoverHintMessage =>
      'Para añadir una imagen de portada, toca este botón en la parte superior.';

  @override
  String get longPressEditHintTitle => 'Mantén pulsado para editar';

  @override
  String get longPressEditHintMessage =>
      'Mantén pulsada cualquier parte de tu viaje — la portada, una anotación, una parada — para editarla directamente.';

  @override
  String get addProfilePhoto => 'Añade una foto de perfil';

  @override
  String get addAvatarHintMessage =>
      'Para añadir una foto de perfil, toca este botón en la parte superior.';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paradas',
      one: '$count parada',
    );
    return '$_temp0';
  }

  @override
  String get expand => 'Expandir';

  @override
  String get tapToSeeStops => 'Toca para ver las paradas';

  @override
  String get coverImageSection => 'Imagen de portada';

  @override
  String get coverImageUrlLabel => 'URL de la imagen de portada';

  @override
  String get uploadCoverImage => 'Subir imagen de portada';

  @override
  String followRequestsBannerTitle(int count) {
    return 'Solicitudes de seguimiento ($count)';
  }

  @override
  String get tapToReview => 'Toca para revisar';

  @override
  String get editProfileTooltip => 'Editar perfil';

  @override
  String get settingsTooltip => 'Ajustes';

  @override
  String get shareProfileTooltip => 'Compartir perfil';

  @override
  String get couldNotLoadItineraries =>
      'No se pudieron cargar los itinerarios.';

  @override
  String get whereTheyveBeen => 'DÓNDE HA ESTADO';

  @override
  String get itinerariesSectionHeader => 'ITINERARIOS';

  @override
  String get noPublicItinerariesYet => 'Aún no hay itinerarios públicos.';

  @override
  String get accountIsPrivateTitle => 'Esta cuenta es privada';

  @override
  String get followRequestSentTitle => 'Solicitud enviada';

  @override
  String get followRequestPendingMessage =>
      'Cuando acepte tu solicitud, verás sus itinerarios, paradas y mapa de viajes.';

  @override
  String followToSeeMessage(String handle) {
    return 'Sigue a $handle para ver sus itinerarios, paradas y mapa de viajes.';
  }

  @override
  String get editProfileTitle => 'Editar perfil';

  @override
  String get uploadPhoto => 'Subir foto';

  @override
  String get identitySection => 'Identidad';

  @override
  String get displayNameLabel => 'Nombre visible';

  @override
  String get usernameLabel => 'Nombre de usuario';

  @override
  String get bioLabel => 'BIOGRAFÍA';

  @override
  String get bioHelpMessage =>
      'Una breve descripción. Admite markdown **negrita** y emojis.';

  @override
  String get addBioLabel => 'Añade una biografía';

  @override
  String get avatarUrlLabel => 'URL del avatar';

  @override
  String get travelIdentitySection => 'Identidad de viajero';

  @override
  String get passportLabel => 'Pasaporte';

  @override
  String get livesInLabel => 'Vive en';

  @override
  String get languagesLabel => 'Idiomas';

  @override
  String maxLanguagesReached(int count) {
    return 'Puedes añadir hasta $count idiomas.';
  }

  @override
  String get privacySection => 'Privacidad';

  @override
  String get securitySection => 'Seguridad';

  @override
  String get dangerZoneSection => 'Zona de peligro';

  @override
  String get privateAccountLabel => 'Cuenta privada';

  @override
  String get privateAccountSubtitle =>
      'Las personas deben solicitar seguirte para ver tus itinerarios.';

  @override
  String get switchToPublicTitle => '¿Cambiar a pública?';

  @override
  String switchToPublicMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Tienes $count solicitudes de seguimiento pendientes. Al cambiar a pública, se aceptarán todas automáticamente. ¿Continuar?',
      one:
          'Tienes 1 solicitud de seguimiento pendiente. Al cambiar a pública, se aceptará automáticamente. ¿Continuar?',
    );
    return '$_temp0';
  }

  @override
  String get switchToPublicButton => 'Cambiar a pública';

  @override
  String get planFirstJourney => 'Planifica tu primer viaje';

  @override
  String get planFirstJourneyHint =>
      'Añade paradas, tramos de transporte y notas. Compártelo con amigos o mantenlo privado.';

  @override
  String get createItinerary => 'Crear itinerario';

  @override
  String get needInspiration => '¿Necesitas inspiración?';

  @override
  String get browseForIdeas =>
      'Explora el feed de la comunidad en busca de ideas.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsNotifications => 'Notificaciones';

  @override
  String get settingsNotificationsOn => 'Activadas';

  @override
  String get settingsNotificationsOff => 'Desactivadas';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsSoundEffects => 'Efectos de sonido';

  @override
  String get settingsSoundEffectsDetail =>
      'Reproducir un sonido al abrir un itinerario';

  @override
  String get settingsSupport => 'Ayuda';

  @override
  String get settingsHelpCenter => 'Centro de ayuda';

  @override
  String get settingsAbout => 'Acerca de Ntripi';

  @override
  String get settingsTerms => 'Términos y privacidad';

  @override
  String get settingsLogout => 'Cerrar sesión';

  @override
  String get settingsDeleteAccount => 'Eliminar cuenta';

  @override
  String get logoutConfirmTitle => 'Cerrar sesión';

  @override
  String get logoutConfirmMessage => '¿Seguro que quieres cerrar sesión?';

  @override
  String get logoutConfirmButton => 'Cerrar sesión';

  @override
  String get languagePickerTitle => 'Idioma';

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
  String get themePickerTitle => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get followRequestsTitle => 'Solicitudes de seguimiento';

  @override
  String get noRequests => 'No hay solicitudes pendientes';

  @override
  String requestsCountLabel(int count) {
    return 'Solicitudes · $count';
  }

  @override
  String get acceptButton => 'Aceptar';

  @override
  String get rejectButton => 'Rechazar';

  @override
  String followersTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seguidores',
      zero: 'Seguidores',
    );
    return '$_temp0';
  }

  @override
  String followingTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Siguiendo a $count',
      zero: 'Siguiendo',
    );
    return '$_temp0';
  }

  @override
  String followRequestsSectionLabel(int count) {
    return 'Solicitudes de seguimiento · $count';
  }

  @override
  String get allFollowersSection => 'Todos los seguidores';

  @override
  String get noFollowersYet => 'Aún no tienes seguidores.';

  @override
  String get notFollowingAnyone => 'Aún no sigues a nadie.';

  @override
  String get peopleYouFollow => 'Personas que sigues';

  @override
  String get confirmButton => 'Confirmar';

  @override
  String get searchPeoplePlaceholder => 'Buscar personas…';

  @override
  String get searchForPeople => 'Busca personas a las que seguir';

  @override
  String get noUsersFound => 'No se encontraron usuarios.';

  @override
  String searchResultsCount(int count) {
    return 'Resultados · $count';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seguidores',
      one: '$count seguidor',
    );
    return '$_temp0';
  }

  @override
  String get searchUsersHelp =>
      'Encuentra personas por su @usuario o por su nombre visible. Toca un resultado para ver su perfil.';

  @override
  String get myItineraries => 'Mis itinerarios';

  @override
  String get noItinerariesYet => 'Aún no hay itinerarios.';

  @override
  String get tapToCreateFirst => 'Toca + para crear tu primer viaje.';

  @override
  String get deleteItineraryTitle => '¿Eliminar este itinerario?';

  @override
  String get deleteItineraryMessage =>
      'Se destruirán permanentemente todas las paradas, anotaciones, segmentos, valoraciones y enlaces compartidos. Esto no se puede deshacer.';

  @override
  String get deleteItineraryButton => 'Eliminar itinerario';

  @override
  String get newItinerary => 'Nuevo itinerario';

  @override
  String get editItinerary => 'Editar itinerario';

  @override
  String get coverImageLabel => 'Imagen de portada';

  @override
  String get coverImageHelp =>
      'Una imagen de 1200×630 que se muestra en la tarjeta del itinerario y en las vistas previas de enlaces. Arrastra dentro del recuadro para reposicionar.';

  @override
  String get itineraryTitleLabel => 'Título *';

  @override
  String get itineraryTitleHint => 'p. ej. 10 días en Kioto y Osaka';

  @override
  String get itineraryTitleHelp =>
      'Un nombre corto y claro para este viaje. Se muestra en la tarjeta del itinerario y en las vistas previas al compartir.';

  @override
  String get itineraryTitleRequired => 'El título es obligatorio';

  @override
  String get descriptionLabel => 'Descripción';

  @override
  String get descriptionHelp =>
      'Opcional. Un resumen del viaje. Usa la barra de herramientas para poner el texto en negrita o cursiva, añadir títulos y crear listas con viñetas o numeradas. Cambia a la pestaña Vista previa para ver cómo lo verán los lectores.';

  @override
  String get addDescriptionLabel => 'Añade una descripción';

  @override
  String get currencyLabel => 'Moneda';

  @override
  String get currencyHelp =>
      'Moneda predeterminada para todos los costes de paradas y de transporte en este itinerario.';

  @override
  String get visibilityLabel => 'Visibilidad';

  @override
  String get visibilityHelp =>
      'Público: cualquiera puede verlo. Seguidores: solo quienes te siguen. Restringido: solo los usuarios que añadas a la lista. Solo yo: privado para ti.';

  @override
  String get visibilityPublic => 'Público';

  @override
  String get visibilityFollowers => 'Seguidores';

  @override
  String get visibilityRestricted => 'Restringido';

  @override
  String get visibilityOnlyMe => 'Solo yo';

  @override
  String get imageSaveButUploadFailed =>
      'Itinerario guardado, pero falló la subida de la imagen. Inténtalo de nuevo desde la pantalla de edición.';

  @override
  String get formSectionBasics => 'BÁSICOS';

  @override
  String get formLabelCurrency => 'MONEDA';

  @override
  String get formLabelWhoCanSee => '¿QUIÉN PUEDE VER ESTO?';

  @override
  String get formSectionDangerZone => 'ZONA DE PELIGRO';

  @override
  String get formLabelDeleteItinerary => 'ELIMINAR ITINERARIO';

  @override
  String get formDeleteItineraryHint => 'Escribe el título para confirmar';

  @override
  String get currencySearchHint => 'Buscar moneda…';

  @override
  String get bestTimeToVisit => 'Mejor época para viajar';

  @override
  String get addBestTimeToVisit => 'Añadir la mejor época para viajar';

  @override
  String get formLabelBestTime => 'MEJOR ÉPOCA PARA VIAJAR';

  @override
  String get periodNotSet => 'Sin definir';

  @override
  String get periodSectionMonths => 'MEJORES MESES';

  @override
  String get periodSectionWindows => 'PERIODOS';

  @override
  String get periodSectionWeekdays => 'DÍAS DE LA SEMANA';

  @override
  String get periodSectionWhy => '¿POR QUÉ ESTA ÉPOCA?';

  @override
  String get periodMonthsHelp =>
      'Toca cada mes que merezca el viaje. Los meses contiguos forman un solo periodo.';

  @override
  String get periodNoMonthsSelected => 'Aún no has elegido meses';

  @override
  String get periodExactDays => 'Días exactos';

  @override
  String get periodStartsOn => 'Empieza el';

  @override
  String get periodEndsOn => 'Termina el';

  @override
  String get periodWholeMonth => 'Mes completo';

  @override
  String get periodWeekdays => 'Entre semana';

  @override
  String get periodWeekends => 'Fines de semana';

  @override
  String get periodWhyHint =>
      'p. ej. cerezos en flor, clima suave, menos gente';

  @override
  String get periodClear => 'Borrar';

  @override
  String get periodClearConfirmTitle => '¿Borrar la mejor época?';

  @override
  String get periodClearConfirmMessage =>
      'Se eliminarán los meses, los días exactos, los días de la semana y la nota que elegiste.';

  @override
  String currenciesLoadFailed(String error) {
    return 'No se pudieron cargar las monedas: $error';
  }

  @override
  String get deleteItineraryFormTitle => 'Eliminar itinerario';

  @override
  String deleteItineraryFormMessage(String title) {
    return 'Esto eliminará permanentemente \"$title\" y todas sus paradas. Escribe el título para confirmar.';
  }

  @override
  String get followButton => 'Seguir';

  @override
  String get followingButton => 'Siguiendo';

  @override
  String get requestedButton => 'Solicitado';

  @override
  String unfollowTitle(String username) {
    return '¿Dejar de seguir a @$username?';
  }

  @override
  String get unfollowMessage => 'Dejarás de ver sus itinerarios en tu feed.';

  @override
  String get unfollowConfirm => 'Dejar de seguir';

  @override
  String get unfollowKeep => 'Mantener';

  @override
  String unfollowedSnackbar(String username) {
    return 'Dejaste de seguir a @$username';
  }

  @override
  String get cancelRequestTitle => '¿Cancelar solicitud?';

  @override
  String cancelRequestMessage(String username) {
    return '¿Cancelar tu solicitud de seguimiento a @$username?';
  }

  @override
  String get cancelRequestConfirm => 'Cancelar solicitud';

  @override
  String get cancelRequestKeep => 'Mantener';

  @override
  String get declineRequestTitle => '¿Rechazar solicitud?';

  @override
  String declineRequestMessage(String username) {
    return '¿Rechazar la solicitud de seguimiento de @$username? Esta persona podrá enviar una nueva más tarde.';
  }

  @override
  String get declineRequestConfirm => 'Rechazar';

  @override
  String get undoButton => 'DESHACER';

  @override
  String couldNotUndo(String error) {
    return 'No se pudo deshacer: $error';
  }

  @override
  String get errorNoInternet =>
      'Sin conexión a internet. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get errorGenericRetry => 'Se produjo un error. Inténtalo de nuevo.';

  @override
  String get errorGeneric => 'Se produjo un error.';

  @override
  String get fieldHelpTooltip => '¿Qué es esto?';

  @override
  String typeToConfirmInstruction(String text) {
    return 'Escribe \"$text\" para confirmar:';
  }

  @override
  String get daysLabel => 'd';

  @override
  String get noneOption => 'Ninguno';

  @override
  String get discardButton => 'Descartar';

  @override
  String get discardChangesTitle => '¿Descartar cambios?';

  @override
  String get discardChangesMessage => 'Tus cambios no se guardarán.';

  @override
  String get keepEditingButton => 'Seguir editando';

  @override
  String get orderSavedMessage => 'Orden guardado';

  @override
  String get segmentSelectBothStops =>
      'Selecciona una parada de origen y una de destino.';

  @override
  String get segmentStopsMustDiffer =>
      'Las paradas de origen y destino deben ser distintas.';

  @override
  String get segmentAddLegFirst => 'Añade al menos un tramo antes de guardar.';

  @override
  String get segmentAlreadyExistsTitle => 'El segmento ya existe';

  @override
  String get segmentAlreadyExistsMessage =>
      'Ya hay un segmento que conecta estas dos paradas. ¿Qué quieres hacer?';

  @override
  String get segmentJoin => 'Unir';

  @override
  String get segmentReplace => 'Reemplazar';

  @override
  String get segmentFromStopLabel => 'Parada de origen';

  @override
  String get segmentToStopLabel => 'Parada de destino';

  @override
  String get visibilityScreenTitle => '¿Quién puede ver esto?';

  @override
  String get visibilityAddPerson => 'Añadir persona';

  @override
  String get visibilitySearchByUsername => 'Buscar por nombre de usuario…';

  @override
  String get couldNotLoadRatings => 'No se pudieron cargar las valoraciones';

  @override
  String get stopNotFound => 'Parada no encontrada.';

  @override
  String get mapPickLocationTitle => 'Elegir ubicación';

  @override
  String get mapConfirmLocation => 'Confirmar ubicación';

  @override
  String get stopCostHint => 'p. ej. 20';

  @override
  String get ratingsTitle => 'Valoraciones';

  @override
  String get noRatingsYet => 'Aún no hay valoraciones';

  @override
  String get ratingsOverallLabel => 'GENERAL';

  @override
  String get rateThisTrip => 'Valora este viaje';

  @override
  String get editYourItinerary => 'Edita tu itinerario';

  @override
  String get deletedUser => 'Usuario eliminado';

  @override
  String get annotationContentHint => '¿Qué deberían saber los viajeros?';

  @override
  String get countryPickerTitle => 'Seleccionar país';

  @override
  String get countrySearchHint => 'Buscar países…';

  @override
  String get countryNoneClear => 'Ninguno / Borrar';

  @override
  String get languageSearchHint => 'Buscar idiomas…';

  @override
  String get coverChangeButton => 'Cambiar';

  @override
  String get coverEditCropButton => 'Editar recorte';

  @override
  String get coverAdjustTitle => 'Ajustar foto de portada';

  @override
  String get mdBoldTooltip => 'Negrita';

  @override
  String get mdItalicTooltip => 'Cursiva';

  @override
  String get mdHeading1Tooltip => 'Título 1';

  @override
  String get mdHeading2Tooltip => 'Título 2';

  @override
  String get mdBulletListTooltip => 'Lista con viñetas';

  @override
  String get mdNumberedListTooltip => 'Lista numerada';

  @override
  String get mdEditTab => 'Editar';

  @override
  String get mdPreviewTab => 'Vista previa';

  @override
  String get legCostHint => 'p. ej. 12,50';

  @override
  String get addLegButton => 'Añadir tramo';

  @override
  String get totalLabel => 'Total';

  @override
  String get reorderOrphanTitle => '¿Guardar el nuevo orden?';

  @override
  String reorderOrphanMessage(int count, String segments) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminarán $count segmentos de transporte porque sus paradas ya no estarán en columnas adyacentes:\n\n$segments',
      one:
          'Se eliminará $count segmento de transporte porque sus paradas ya no estarán en columnas adyacentes:\n\n$segments',
    );
    return '$_temp0';
  }

  @override
  String get loadingLabel => 'Cargando…';

  @override
  String get usernameRequired => 'El nombre de usuario es obligatorio';

  @override
  String get usernameTooShort =>
      'El nombre de usuario debe tener al menos 4 caracteres';

  @override
  String get usernameTooLong =>
      'El nombre de usuario no puede superar los 30 caracteres';

  @override
  String get usernameInvalidFormat =>
      'Solo letras, números, puntos y guiones bajos. Debe empezar por una letra y terminar en letra o número.';

  @override
  String get usernameConsecutiveSpecial =>
      'No puede tener puntos o guiones bajos consecutivos';

  @override
  String get displayNameTooLong =>
      'El nombre visible no puede superar los 50 caracteres';

  @override
  String get comingSoon => 'Próximamente';

  @override
  String get verifyEmailTitle => 'Verifica tu correo';

  @override
  String get verifyEmailMessage =>
      'Verifica tu correo para desbloquear la creación de viajes, las valoraciones y seguir a otras personas.';

  @override
  String get verifyEmailButton => 'Verificar con Google';

  @override
  String get emailVerifiedSuccess => 'Correo verificado: ¡todo listo!';

  @override
  String get resendVerificationButton => 'Reenviar correo de verificación';

  @override
  String get verificationEmailSent =>
      'Correo de verificación enviado: revisa tu bandeja de entrada.';

  @override
  String get forgotPasswordTitle => 'Restablece tu contraseña';

  @override
  String get forgotPasswordSubtitle =>
      'Introduce el correo de tu cuenta y te enviaremos un enlace para establecer una nueva contraseña.';

  @override
  String get forgotPasswordEmailLabel => 'Correo';

  @override
  String get forgotPasswordSubmit => 'Enviar enlace de restablecimiento';

  @override
  String get forgotPasswordSentTitle => 'Revisa tu correo';

  @override
  String get forgotPasswordSentBody =>
      'Si existe una cuenta con ese correo, te hemos enviado un enlace para restablecer la contraseña. Revisa tu bandeja de entrada y la carpeta de spam.';

  @override
  String get changePasswordTitle => 'Cambiar contraseña';

  @override
  String get changePasswordSubtitle =>
      'Introduce tu contraseña actual y elige una nueva. Al cambiarla, se cerrará la sesión en todos los demás dispositivos.';

  @override
  String get changePasswordCurrentLabel => 'Contraseña actual';

  @override
  String get changePasswordNewLabel => 'Nueva contraseña';

  @override
  String get changePasswordConfirmLabel => 'Confirmar nueva contraseña';

  @override
  String get changePasswordMismatch => 'Las contraseñas no coinciden.';

  @override
  String get changePasswordSameAsOld =>
      'La nueva contraseña debe ser distinta de la actual.';

  @override
  String get changePasswordSubmit => 'Cambiar contraseña';

  @override
  String get changePasswordConfirmMessage =>
      'Esto cerrará tu sesión en todos los demás dispositivos. ¿Continuar?';

  @override
  String get changePasswordSuccess =>
      'Contraseña cambiada. Se cerró la sesión en los demás dispositivos.';

  @override
  String get backToSignIn => 'Volver a iniciar sesión';

  @override
  String get speaksLabel => 'Habla';

  @override
  String get removeButton => 'Quitar';

  @override
  String get doneTooltip => 'Listo';

  @override
  String get addButton => 'Añadir';

  @override
  String get deleteButton => 'Eliminar';

  @override
  String get deleteAccountTitle => 'Eliminar cuenta';

  @override
  String get deleteAccountConfirmTitle => '¿Eliminar tu cuenta?';

  @override
  String get deleteAccountConfirmMessage =>
      'Tu cuenta, itinerarios, seguidos y valoraciones se anonimizarán o eliminarán según nuestra política de privacidad. Se cerrará tu sesión de inmediato. Esto no se puede deshacer.';

  @override
  String get deleteAccountRequiredText => 'ELIMINAR MI CUENTA';

  @override
  String get deleteAccountConfirmLabel => 'Eliminar mi cuenta';

  @override
  String get deleteAccountPasswordError =>
      'Contraseña incorrecta. Inténtalo de nuevo.';

  @override
  String get deleteAccountGenericError => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get deleteAccountCannotUndo => 'Esto no se puede deshacer';

  @override
  String get deleteAccountWillRemove =>
      'Eliminar tu cuenta borrará permanentemente:';

  @override
  String get deleteAccountBullet1 => 'Tu perfil y todos tus datos personales';

  @override
  String get deleteAccountBullet2 => 'Todos tus itinerarios y paradas';

  @override
  String get deleteAccountBullet3 => 'Tus relaciones de seguimiento';

  @override
  String get deleteAccountNote =>
      'Las valoraciones que diste a otros itinerarios se conservarán de forma anónima como datos de la comunidad.';

  @override
  String get deleteAccountEnterPassword =>
      'Introduce tu contraseña para confirmar';

  @override
  String get deleteAccountEnterPasswordError =>
      'Introduce tu contraseña para continuar.';

  @override
  String get deleteAccountPasswordLabel => 'Contraseña';

  @override
  String get deleteAccountPasswordHelpTitle => 'Confirmar contraseña';

  @override
  String get deleteAccountPasswordHelpMessage =>
      'Vuelve a introducir tu contraseña para confirmar la eliminación. La eliminación de la cuenta es permanente y no se puede deshacer.';

  @override
  String get deleteAccountButton => 'Eliminar mi cuenta';

  @override
  String get deleteAccountGoogleExplain =>
      'Esta cuenta usa el inicio de sesión con Google. Vuelve a autenticarte con Google para confirmar la eliminación.';

  @override
  String get deleteAccountGoogleButton => 'Continuar con Google';

  @override
  String get deleteAccountOrDivider => 'O';

  @override
  String get deleteAccountGoogleAlternative =>
      '¿Prefieres Google? Vuelve a autenticarte con Google en su lugar.';

  @override
  String get deleteAnnotationTitle => '¿Eliminar anotación?';

  @override
  String get deleteAnnotationMessage =>
      'Esto eliminará permanentemente esta anotación del itinerario.';

  @override
  String get deleteAnnotationStopMessage =>
      'Esta anotación se eliminará permanentemente.';

  @override
  String get removeTransitTitle => '¿Quitar el transporte entre paradas?';

  @override
  String get removeTransitMessage =>
      'Se borrará la conexión entre estas dos paradas. Puedes añadir una nueva más tarde.';

  @override
  String get reorderTracksTitle => 'Reordenar columnas';

  @override
  String get shareTooltip => 'Compartir';

  @override
  String get editDetailsTooltip => 'Editar detalles e imagen';

  @override
  String get descriptionSection => 'Descripción';

  @override
  String get annotationsSection => 'Anotaciones';

  @override
  String get addAnnotationButton => 'Añadir anotación';

  @override
  String get noAnnotationsYet => 'Aún no hay anotaciones.';

  @override
  String get stopsList => 'Lista de paradas';

  @override
  String get editStopsButton => 'Editar paradas';

  @override
  String get addStopTooltip => 'Añadir parada';

  @override
  String get reorderTracksTooltip => 'Reordenar columnas';

  @override
  String get mapSection => 'Mapa';

  @override
  String get openInMaps => 'Abrir en mapas';

  @override
  String get otherMapsApp => 'Otra app de mapas';

  @override
  String get openRouteInMaps => 'Abrir ruta en Google Maps';

  @override
  String routeTruncated(int count) {
    return 'Google Maps solo puede mostrar las primeras $count paradas';
  }

  @override
  String get openStreetMapContributors => 'Colaboradores de OpenStreetMap';

  @override
  String get poweredByOSM => 'Con tecnología de OpenStreetMap';

  @override
  String get noStopsYetTapPlus => 'Aún no hay paradas. Toca + para añadir una.';

  @override
  String get communityRating => 'Comunidad';

  @override
  String ratingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count valoraciones',
      one: '1 valoración',
    );
    return '$_temp0';
  }

  @override
  String get yourRating => 'Tu valoración';

  @override
  String get rateIt => 'Valorar';

  @override
  String deleteOrphanSegmentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar segmentos de transporte?',
      one: '¿Eliminar segmento de transporte?',
    );
    return '$_temp0';
  }

  @override
  String deleteOrphanSegmentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hay $count segmentos de transporte que conectan estas dos paradas. Añadir una parada entre ellas los ocultará porque las paradas ya no serán adyacentes. ¿Eliminar los segmentos y continuar?',
      one:
          'Hay 1 segmento de transporte que conecta estas dos paradas. Añadir una parada entre ellas lo ocultará porque las paradas ya no serán adyacentes. ¿Eliminar el segmento y continuar?',
    );
    return '$_temp0';
  }

  @override
  String get deleteAndContinue => 'Eliminar y continuar';

  @override
  String get notSet => 'Sin definir';

  @override
  String get stopDetailsView => 'Detalles de la parada';

  @override
  String get editStopTitle => 'Editar parada';

  @override
  String get addStopTitle => 'Añadir parada';

  @override
  String get editStopTooltip => 'Editar parada';

  @override
  String get duplicateStopTitle => 'Parada duplicada';

  @override
  String duplicateStopMessage(String name) {
    return '$name ya está en este itinerario. ¿Añadirlo de nuevo de todos modos?';
  }

  @override
  String get addAnyway => 'Añadir de todos modos';

  @override
  String get itineraryUpdatedTitle => 'Itinerario actualizado en otro lugar';

  @override
  String get itineraryUpdatedMessage =>
      'Este itinerario se editó desde otro dispositivo. Vuelve atrás y recarga para ver la última versión.';

  @override
  String get goBack => 'Volver';

  @override
  String get deleteStopTitle => '¿Eliminar esta parada?';

  @override
  String get deleteStopMessage =>
      'Esto eliminará la parada, sus anotaciones y los segmentos de transporte conectados a ella. Esto no se puede deshacer.';

  @override
  String get viewOnlyTitle => 'Solo lectura';

  @override
  String get viewOnlyMessage => 'Toca el botón Editar para hacer cambios.';

  @override
  String get searchForPlaceLabel => 'Buscar un lugar';

  @override
  String get searchAPlaceHelpTitle => 'Buscar un lugar';

  @override
  String get searchAPlaceHelpMessage =>
      'Escribe el nombre de un lugar, restaurante o monumento. Elige un resultado para autocompletar el nombre del lugar, la dirección y las coordenadas de abajo.';

  @override
  String get searchPlaceHintText => 'p. ej. Torre Eiffel, París';

  @override
  String get stopDetailsSectionLabel => 'Detalles de la parada';

  @override
  String get placeNameLabel => 'Nombre del lugar';

  @override
  String get placeNameHelp =>
      'Nombre del lugar, restaurante, monumento o parada.';

  @override
  String get placeNameRequired => 'El nombre del lugar es obligatorio';

  @override
  String get addressLabel => 'Dirección';

  @override
  String get addressHelp =>
      'Dirección de la calle o descripción de la zona. Opcional.';

  @override
  String get mapLinkLabel => 'Enlace de Google Maps';

  @override
  String get mapLinkHint => 'Pega un enlace de Google Maps';

  @override
  String get mapLinkInvalid => 'Introduce un enlace de Google Maps válido';

  @override
  String get mapLinkPaste => 'Pegar';

  @override
  String get mapLinkClear => 'Borrar';

  @override
  String get locationModeCoordinates => 'Coordenadas';

  @override
  String get locationModeMapLink => 'Enlace de Google Maps';

  @override
  String get linkPreviewOpensInMaps => 'Se abre en Google Maps';

  @override
  String get linkPreviewLoading => 'Cargando vista previa…';

  @override
  String get linkPreviewTitleCopied => 'Título copiado';

  @override
  String get linkPreviewMapMobileOnly =>
      'Vista previa del mapa disponible en la app móvil';

  @override
  String get coordinatesHelp =>
      'La ubicación en el mapa de esta parada. Toca \"Elegir en el mapa\" para establecerla o ajustarla.';

  @override
  String get pickOnMap => 'Elegir en el mapa';

  @override
  String get placeTypeLabel => 'Tipo de lugar';

  @override
  String get placeTypeHelp =>
      'Qué tipo de lugar es (p. ej. comer y beber, dormir, lugar de interés). Se usa para filtrar y para el icono del mapa.';

  @override
  String get selectPlaceType => 'Seleccionar tipo de lugar';

  @override
  String get placeTypeEatDrink => 'Comer y beber';

  @override
  String get placeTypeSleep => 'Dormir';

  @override
  String get placeTypePray => 'Rezar';

  @override
  String get placeTypeLearnSee => 'Aprender y ver';

  @override
  String get placeTypeBuy => 'Comprar';

  @override
  String get placeTypePlayWatch => 'Jugar y ver';

  @override
  String get placeTypeNature => 'Naturaleza';

  @override
  String get placeTypeTransport => 'Transporte';

  @override
  String get placeTypeHealBathe => 'Salud y baño';

  @override
  String get placeTypeEntertainment => 'Entretenimiento';

  @override
  String get placeTypeSight => 'Lugar de interés';

  @override
  String get placeTypeHintEatDrink =>
      'café, restaurante, bar, panadería, food truck';

  @override
  String get placeTypeHintSleep => 'hotel, hostal, camping, posada, refugio';

  @override
  String get placeTypeHintPray =>
      'iglesia, mezquita, templo, sinagoga, santuario';

  @override
  String get placeTypeHintLearnSee =>
      'museo, galería, biblioteca, acuario, observatorio';

  @override
  String get placeTypeHintBuy =>
      'tienda, mercado, centro comercial, boutique, puesto';

  @override
  String get placeTypeHintPlayWatch =>
      'estadio, gimnasio, pabellón, cancha, bolera';

  @override
  String get placeTypeHintNature => 'playa, parque, bosque, montaña, cascada';

  @override
  String get placeTypeHintTransport =>
      'aeropuerto, estación de tren, parada de autobús, terminal de ferry';

  @override
  String get placeTypeHintHealBathe =>
      'spa, aguas termales, piscina, sauna, casa de baños';

  @override
  String get placeTypeHintEntertainment =>
      'teatro, cine, sala de conciertos, discoteca';

  @override
  String get placeTypeHintSight => 'monumento, mirador, castillo, plaza, ruina';

  @override
  String get recommendedTimeLabel => 'Tiempo recomendado de estancia';

  @override
  String get timeToSpendHelp =>
      'Aproximadamente cuánto tiempo esperas quedarte aquí. Toca para establecer días, horas y minutos.';

  @override
  String get stopIsFree => 'Esta parada es gratuita';

  @override
  String get freeHelp => 'Actívalo si visitar este lugar no cuesta nada.';

  @override
  String get costLabel => 'Coste';

  @override
  String get costHelp =>
      'Coste aproximado por persona, en la moneda del itinerario.';

  @override
  String get enterValidNumber => 'Introduce un número válido';

  @override
  String get thoughtsLabel => 'Impresiones';

  @override
  String get thoughtsHelp =>
      'Tu opinión personal sobre esta parada: qué esperar, qué te encantó, qué saltarte, consejos de horarios. Usa la barra de herramientas para añadir negrita, cursiva, títulos o listas con viñetas.';

  @override
  String get annotationsLabel => 'Anotaciones';

  @override
  String get annotationsHelp =>
      'Notas breves etiquetadas (consejo, precaución, evitar, información) asociadas a esta parada. Útiles para advertencias o consejos.';

  @override
  String get saveChangesButton => 'Guardar cambios';

  @override
  String get addStopButton => 'Añadir parada';

  @override
  String get deleteStopButton => 'Eliminar parada';

  @override
  String get timeToSpendModalTitle => 'Tiempo de estancia';

  @override
  String get editTransitTitle => 'Editar transporte';

  @override
  String get addTransitTitle => 'Añadir transporte';

  @override
  String get updateTransitButton => 'Actualizar transporte';

  @override
  String get transportModeLabel => 'Modo';

  @override
  String get transportModeHelp =>
      'Cómo viajas en este tramo (a pie, autobús, tren, ferry, etc.). Algunos modos muestran campos adicionales para línea y dirección.';

  @override
  String get transitLineLabel => 'Línea (opcional)';

  @override
  String get transitLineHelp =>
      'Opcional. El número o nombre de la línea (p. ej. \"Bus 42\", \"M1\").';

  @override
  String get transitDirectionLabel => 'Dirección (opcional)';

  @override
  String get transitDirectionHelp =>
      'Opcional. Hacia dónde va la línea (p. ej. \"Sentido norte\", \"Châtelet\").';

  @override
  String get durationLabel => 'Duración';

  @override
  String get durationHelp => 'Cuánto dura este tramo, en horas y minutos.';

  @override
  String get legCostHelp =>
      'Coste aproximado en la moneda del itinerario. Desactivado cuando \"Gratis\" está activado.';

  @override
  String get hoursLabel => 'h';

  @override
  String get minutesLabel => 'min';

  @override
  String get freeLegLabel => 'Gratis';

  @override
  String get freeLegHelp =>
      'Actívalo si este tramo no cuesta nada (a pie, transbordo incluido, etc.).';

  @override
  String get legThoughtsLabel => 'Impresiones (opcional)';

  @override
  String get legThoughtsHelp =>
      'Opcional. Cualquier cosa útil que saber sobre este tramo: consejos de reserva, instrucciones de transbordo, dónde sentarse, sorpresas en el precio del billete.';

  @override
  String get annotationTypeLabel => 'Tipo';

  @override
  String get annotationTypeHelp =>
      'Consejo: una recomendación útil. Precaución: ten cuidado. Evitar: no vayas. Información: una nota neutral.';

  @override
  String get annotationAdvice => 'Consejo';

  @override
  String get annotationCaution => 'Precaución';

  @override
  String get annotationAvoid => 'Evitar';

  @override
  String get annotationInfo => 'Información';

  @override
  String get annotationContentLabel => 'Contenido *';

  @override
  String get annotationContentHelp =>
      'Describe tu consejo, precaución, advertencia o nota en una o dos frases.';

  @override
  String get annotationContentRequired => 'El contenido es obligatorio';

  @override
  String get editAnnotationTitle => 'Editar anotación';

  @override
  String get addAnnotationDialogTitle => 'Añadir anotación';

  @override
  String get saveButton => 'Guardar';

  @override
  String get moveStopTitle => 'Mover parada';

  @override
  String moveStopDescription(int max) {
    return 'Elige una columna existente, un hueco para crear una nueva columna o extráela a su propia columna. Las columnas con el máximo de $max paradas están desactivadas.';
  }

  @override
  String get extractIntoOwnTrack => 'Extraer a su propia columna nueva';

  @override
  String get moveButton => 'Mover';

  @override
  String moveStopMoved(String destination) {
    return 'Movido a $destination';
  }

  @override
  String get itineraryChangedElsewhere =>
      'El itinerario cambió en otro lugar: cierra y vuelve a abrir para ver el orden más reciente.';

  @override
  String get moveStopOrphan1 =>
      'Esta es la última parada de su columna: la columna se eliminará del itinerario.';

  @override
  String moveStopOrphanSegments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminarán $count segmentos de transporte porque sus paradas ya no estarán en columnas adyacentes.',
      one:
          'Se eliminará 1 segmento de transporte porque sus paradas ya no estarán en columnas adyacentes.',
    );
    return '$_temp0';
  }

  @override
  String get moveStopNewTrack => 'Nueva columna';

  @override
  String moveStopNewTrackBefore(int n) {
    return 'Nueva columna antes de la columna $n';
  }

  @override
  String moveStopNewTrackAfter(int n) {
    return 'Nueva columna después de la columna $n';
  }

  @override
  String moveStopNewTrackBetween(int a, int b) {
    return 'Nueva columna entre la columna $a y la columna $b';
  }

  @override
  String get moveStopCurrentSuffix => '  •  actual';

  @override
  String moveStopFull(int max) {
    return 'Llena $max/$max';
  }

  @override
  String extractSubtitle(String trackName) {
    return 'Separa esta parada de \"$trackName\": la nueva columna aparece justo después.';
  }

  @override
  String get removeRatingTitle => '¿Quitar tu valoración?';

  @override
  String get removeRatingMessage =>
      'Tu valoración se eliminará y la media se actualizará para todos los que vean este itinerario.';

  @override
  String get rateItineraryTitle => 'Valorar este itinerario';

  @override
  String get overallRatingLabel => 'General *';

  @override
  String get overallRatingHelp =>
      'Obligatorio. Tu valoración general de este itinerario, de 1 a 5 estrellas.';

  @override
  String get ratingThanksMessage =>
      '¡Gracias! Tu valoración ayuda a los demás.';

  @override
  String get yourImpressionLabel => 'Tu impresión (opcional)';

  @override
  String get yourImpressionHelp =>
      'Opcional. Comparte lo que destacó: lo mejor, lo que lamentaste, a quién se lo recomendarías. Usa la barra de herramientas para añadir negrita, cursiva, títulos o listas con viñetas.';

  @override
  String get removeMyRatingTooltip => 'Quitar mi valoración';

  @override
  String get wantToShareMore => '¿Quieres compartir más? (opcional)';

  @override
  String get safetyLabel => 'Seguridad';

  @override
  String get safetyHelp =>
      'Opcional. Qué tan seguro te sentiste durante este viaje.';

  @override
  String get experienceLabel => 'Experiencia';

  @override
  String get experienceHelp =>
      'Opcional. Qué tan agradable y memorable fue el viaje.';

  @override
  String get accessibilityLabel => 'Accesibilidad';

  @override
  String get accessibilityHelp =>
      'Opcional. Qué tan accesible es el itinerario (movilidad, idioma, señalización).';

  @override
  String get familyFriendlyLabel => 'Apto para familias';

  @override
  String get familyFriendlyHelp =>
      'Opcional. Qué tan adecuado es el viaje para familias con niños.';

  @override
  String get crowdednessLabel => 'Sin aglomeraciones';

  @override
  String get crowdednessHelp =>
      'Opcional. Qué tan poco concurrido y espacioso se sintió: 5 = agradablemente tranquilo, 1 = abarrotado.';

  @override
  String get showOptionalFields => 'Mostrar campos opcionales';

  @override
  String get hideOptionalFields => 'Ocultar campos opcionales';

  @override
  String get transportModeWalk => 'A pie';

  @override
  String get transportModeBus => 'Autobús';

  @override
  String get transportModeTram => 'Tranvía';

  @override
  String get transportModeMetro => 'Metro';

  @override
  String get transportModeTrain => 'Tren';

  @override
  String get transportModeTaxi => 'Taxi';

  @override
  String get transportModeUber => 'Uber';

  @override
  String get transportModeBike => 'Bici';

  @override
  String get transportModeFerry => 'Ferry';

  @override
  String get transportModeCar => 'Coche';

  @override
  String get transportModeAirplane => 'Avión';

  @override
  String get dimensionOverall => 'General';

  @override
  String get dimensionOverallDesc => 'Impresión general';

  @override
  String get dimensionSafetyDesc =>
      'Qué tan seguro te sentiste en todo momento';

  @override
  String get dimensionExperienceDesc => 'Calidad de la experiencia general';

  @override
  String get dimensionAccessibilityDesc =>
      'Facilidad de acceso para todas las capacidades';

  @override
  String get dimensionFamilyFriendlyDesc => 'Idoneidad para niños y familias';

  @override
  String get dimensionCrowdednessDesc =>
      'Qué tan poco concurrido y espacioso se sintió';

  @override
  String dimensionRatingTitle(String label) {
    return 'Valoración: $label';
  }

  @override
  String noRatingsYetFor(String label) {
    return 'Aún no hay valoraciones para $label';
  }

  @override
  String basedOnRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Basado en $count valoraciones',
      one: 'Basado en $count valoración',
    );
    return '$_temp0';
  }

  @override
  String get ratersLabel => 'Evaluadores';

  @override
  String get annotationAdviceDesc => 'Algo útil o un consejo experto.';

  @override
  String get annotationCautionDesc => 'Presta atención: puede haber sorpresas.';

  @override
  String get annotationAvoidDesc => 'No hagas esto. Ahorra tiempo.';

  @override
  String get annotationInfoDesc => 'Un dato neutral que conviene saber.';

  @override
  String get unknownUser => 'Desconocido';

  @override
  String timeAgoMonths(int count) {
    return 'hace $count meses';
  }

  @override
  String timeAgoDays(int count) {
    return 'hace $count d';
  }

  @override
  String timeAgoHours(int count) {
    return 'hace $count h';
  }

  @override
  String timeAgoMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String get timeJustNow => 'Justo ahora';

  @override
  String get yearsAbbrev => 'a';

  @override
  String get timeLabel => 'Hora';

  @override
  String get transitLabel => 'Transporte';

  @override
  String get noLegsYetTapAdd => 'Aún no hay tramos. Toca ＋ para añadir.';

  @override
  String get segmentNeedsOneLeg =>
      'Un segmento necesita al menos un tramo. Elimina el segmento en su lugar.';

  @override
  String fromStopName(String name) {
    return 'Desde $name';
  }

  @override
  String toStopName(String name) {
    return 'Hasta $name';
  }

  @override
  String get visibilityPublicDesc => 'Cualquiera con el enlace puede verlo.';

  @override
  String get visibilityFollowersDesc => 'Solo las personas que te siguen.';

  @override
  String get visibilityRestrictedDesc => 'Solo las personas que permitas.';

  @override
  String get visibilityOnlyMeDesc => 'Solo tú.';

  @override
  String get saveItineraryFirstAllowlist =>
      'Guarda primero el itinerario y luego gestiona tu lista de permitidos desde la pantalla de edición.';

  @override
  String get allowlistLabel => 'Lista de permitidos';

  @override
  String personCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas',
      one: '$count persona',
    );
    return '$_temp0';
  }

  @override
  String removedFromAllowlist(String name) {
    return 'Se eliminó a $name de la lista de permitidos';
  }

  @override
  String get addPeople => 'Añadir personas';

  @override
  String get otherOption => 'Otro';

  @override
  String get thisItineraryFallback => 'este itinerario';

  @override
  String get discardReorderMessage => 'Tu nuevo orden no se guardará.';

  @override
  String get emptyTrackName => '(vacía)';

  @override
  String get unnamedStop => '(sin nombre)';

  @override
  String get unknownStop => '(desconocida)';

  @override
  String get dragToChangeTrackOrder =>
      'Arrastra para cambiar el orden de las columnas';

  @override
  String transitSegmentsWillBeDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminarán $count segmentos de transporte',
      one: 'Se eliminará 1 segmento de transporte',
    );
    return '$_temp0';
  }

  @override
  String andMoreCount(int count) {
    return '… y $count más';
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
    return '→ $name  —  se eliminará el segmento';
  }

  @override
  String get reorderAlternativesTitle => 'Reordenar alternativas';

  @override
  String get reorderAlternativesHint =>
      'Arrastra para cambiar qué opción aparece primero. Toca Guardar para aplicar.';

  @override
  String get emptyTrackLabel => '(columna vacía)';

  @override
  String get moveStopToLabel => 'Mover parada a';

  @override
  String get messageLabel => 'Mensaje';

  @override
  String get annotationKeepShortHint =>
      'Sé breve: menos de 200 caracteres se lee mejor en pantallas pequeñas.';

  @override
  String get transportModeSection => 'Modo de transporte';

  @override
  String get lineDirectionSection => 'Línea y dirección';

  @override
  String get durationCostSection => 'Duración y coste';

  @override
  String get allRatersLabel => 'Todos los evaluadores';

  @override
  String travelersRatedThis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viajeros valoraron esto',
      one: '$count viajero valoró esto',
    );
    return '$_temp0';
  }

  @override
  String get byDimensionLabel => 'Por dimensión';

  @override
  String get notEnoughRatings => 'No hay suficientes valoraciones';

  @override
  String get youRatedThis => 'Valoraste esto';

  @override
  String get changeButton => 'Cambiar';

  @override
  String get hideReview => 'Ocultar reseña';

  @override
  String get readReview => 'Leer reseña';

  @override
  String get notesLabel => 'Notas';

  @override
  String get viewLess => 'ver menos';

  @override
  String get viewMore => '... ver más';

  @override
  String get imageTooLarge => 'La imagen es demasiado grande (máx. 10 MB).';

  @override
  String get couldNotLoadImage =>
      'No se pudo cargar la imagen. Prueba con otra.';

  @override
  String get pinchToZoomHint =>
      'Pellizca para ampliar · Arrastra para reposicionar';

  @override
  String get addCoverImage => 'Añade una imagen de portada';

  @override
  String get coverOptionalMapFallback =>
      'Opcional: de lo contrario, se usará el mapa.';

  @override
  String get noCoverImage => 'Sin imagen de portada';

  @override
  String get mapTapToPlacePin => 'Toca el mapa para colocar un marcador';

  @override
  String get mapTapToMovePin =>
      'Toca en otro lugar para mover el marcador y luego toca Confirmar';

  @override
  String get mapMyLocation => 'Mi ubicación';

  @override
  String get mapUseMyLocation => 'Usar mi ubicación';

  @override
  String get mapSearchNoResults => 'No se encontraron lugares.';

  @override
  String get mapSearchThisArea => 'Buscar en esta zona';

  @override
  String get mapUnnamedPlace => 'Ubicación sin nombre';

  @override
  String get locationPermissionDenied => 'Permiso de ubicación denegado';

  @override
  String get locationServiceDisabled =>
      'Los servicios de ubicación están desactivados';

  @override
  String get locationUnavailable => 'No se pudo obtener tu ubicación';

  @override
  String get locationOpenSettings => 'Abrir ajustes';

  @override
  String get nothingToPreview => 'Aún no hay nada que previsualizar.';

  @override
  String get rateOverallFirstHint =>
      'Valora tu impresión general. Una vez lo hagas, podrás compartir más.';

  @override
  String get splashTagline =>
      'Descubre y comparte itinerarios de viaje\ncreados por exploradores reales';

  @override
  String get splashMotto => 'Explora el mundo, una ruta a la vez';

  @override
  String get tripsPillLabel => 'viajes';

  @override
  String get stopsPillLabel => 'paradas';

  @override
  String get travelledPillLabel => 'recorrido';

  @override
  String get stopFallbackName => 'Parada';

  @override
  String stopWithNumber(int n) {
    return 'Parada $n';
  }

  @override
  String get undoLabel => 'Deshacer';

  @override
  String get updateYourRating => 'Actualiza tu valoración';

  @override
  String get moveActionLabel => 'mover';

  @override
  String get reorderActionLabel => 'reordenar';

  @override
  String get addParallelStopLabel => '// parada';

  @override
  String get aStopFallback => 'Una parada';

  @override
  String get locationLabel => 'Ubicación';

  @override
  String get noLocationSet => 'Sin ubicación definida';

  @override
  String get latitudeLabel => 'Latitud';

  @override
  String get longitudeLabel => 'Longitud';

  @override
  String get invalidLatitudeError =>
      'La latitud debe ser un número entre -90 y 90';

  @override
  String get invalidLongitudeError =>
      'La longitud debe ser un número entre -180 y 180';

  @override
  String get coordinatesPairRequiredError =>
      'Introduce la latitud y la longitud';

  @override
  String get detailsSection => 'Detalles';

  @override
  String get selectLanguagesTitle => 'Seleccionar idiomas';

  @override
  String get done => 'Listo';

  @override
  String alreadyInItinerary(String name) {
    return '$name ya está en este itinerario.';
  }

  @override
  String stopNumberOfTotal(int n, int total) {
    return 'Parada $n de $total';
  }

  @override
  String shareCaption(String title, String stops, String duration) {
    return 'Mira \"$title\" en Ntripi — $stops, $duration';
  }

  @override
  String shareProfileCaption(String name) {
    return '$name en Ntripi — mira dónde ha estado';
  }

  @override
  String get apiErrorNotAuthenticated => 'No has iniciado sesión.';

  @override
  String get apiErrorAccountDeactivated => 'Tu cuenta ha sido desactivada.';

  @override
  String get apiErrorEmailUnverified =>
      'Verifica tu correo con Google para hacer esto.';

  @override
  String get apiErrorItineraryNotFound => 'Itinerario no encontrado.';

  @override
  String get apiErrorItineraryNotOwner =>
      'No tienes permiso para modificar este itinerario.';

  @override
  String get apiErrorIfMatchRequired =>
      'No se pudo guardar este cambio: recarga e inténtalo de nuevo.';

  @override
  String get apiErrorItineraryStale =>
      'El itinerario fue modificado: recarga la página.';

  @override
  String get apiErrorWaitlistContactRequired =>
      'Proporciona al menos un correo o un número de WhatsApp.';

  @override
  String get apiErrorGoogleTokenInvalid => 'Token de Google no válido.';

  @override
  String get apiErrorInvalidGrant =>
      'Tu sesión expiró. Inicia sesión de nuevo.';

  @override
  String get apiErrorStopNotFound => 'Parada no encontrada.';

  @override
  String get apiErrorTrackNotFound =>
      'Columna no encontrada o no pertenece a este itinerario.';

  @override
  String get apiErrorSegmentNotFound => 'Segmento de transporte no encontrado.';

  @override
  String get apiErrorLegNotFound => 'Tramo de transporte no encontrado.';

  @override
  String get apiErrorItineraryAccessDenied =>
      'No tienes acceso a este itinerario.';

  @override
  String get apiErrorAllowlistRestrictedOnly =>
      'La lista de permitidos solo se aplica a itinerarios restringidos.';

  @override
  String get apiErrorUserNotFound => 'Usuario no encontrado.';

  @override
  String get apiErrorAllowlistUserExists => 'Este usuario ya tiene acceso.';

  @override
  String get apiErrorAllowlistUserNotFound =>
      'Usuario no encontrado en la lista de permitidos.';

  @override
  String get apiErrorRankCollision =>
      'Conflicto de orden: vuelve a intentarlo.';

  @override
  String get apiErrorAnnotationNotFound => 'Anotación no encontrada.';

  @override
  String get apiErrorRatingNotFound => 'No has valorado este itinerario.';

  @override
  String get apiErrorSegmentAlreadyExists =>
      'Ya hay un segmento que conecta estas dos paradas.';

  @override
  String get apiErrorIncorrectPassword => 'Contraseña incorrecta.';

  @override
  String get apiErrorLoginInvalid => 'Correo/usuario o contraseña incorrectos.';

  @override
  String get apiErrorCannotFollowSelf => 'No puedes seguirte a ti mismo.';

  @override
  String get apiErrorNotFollowing => 'No sigues a este usuario.';

  @override
  String get apiErrorFollowRequestNotFound =>
      'Solicitud de seguimiento no encontrada.';

  @override
  String get apiErrorFollowRequestAlreadyAccepted =>
      'Esta solicitud de seguimiento ya ha sido aceptada.';

  @override
  String get apiErrorCannotRejectRequest =>
      'No puedes rechazar esta solicitud de seguimiento.';

  @override
  String get apiErrorAccountPrivate => 'Esta cuenta es privada.';

  @override
  String get apiErrorTosRequired =>
      'Debes aceptar los Términos del servicio para registrarte.';

  @override
  String get apiErrorUsernameTaken => 'Este nombre de usuario ya está en uso.';

  @override
  String get apiErrorEmailTaken => 'Ya existe una cuenta con este correo.';

  @override
  String get reportItineraryTitle => 'Denunciar este itinerario';

  @override
  String get reportItineraryTooltip => 'Denunciar';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonNsfw => 'Desnudez o contenido sexual';

  @override
  String get reportReasonViolence => 'Violencia';

  @override
  String get reportReasonHateSpeech => 'Discurso de odio';

  @override
  String get reportReasonHarassment => 'Acoso';

  @override
  String get reportReasonCopyright => 'Infracción de derechos de autor';

  @override
  String get reportReasonOther => 'Otro';

  @override
  String get reportNotesHint => 'Añadir detalles (opcional)';

  @override
  String get reportSubmit => 'Enviar denuncia';

  @override
  String get reportThanks => 'Gracias. Revisaremos esta denuncia.';

  @override
  String get apiErrorReportOwnContent =>
      'No puedes denunciar tu propio contenido.';

  @override
  String get apiErrorReportRateLimited =>
      'Demasiadas denuncias. Inténtalo de nuevo más tarde.';

  @override
  String get imageBlockedNsfw =>
      'Esta imagen parece contener contenido no permitido.';

  @override
  String get apiErrorImageModerationRejected =>
      'Esta imagen no se puede subir porque puede contener contenido prohibido.';

  @override
  String get suspendedTitle => 'Tu cuenta está suspendida';

  @override
  String get suspendedMessage =>
      'Un moderador ha suspendido esta cuenta por incumplir nuestras normas de la comunidad. No puedes iniciar sesión mientras la suspensión esté activa.';

  @override
  String get suspendedAppealButton => 'Apelar esta decisión';

  @override
  String get suspendedBackToLogin => 'Volver al inicio de sesión';

  @override
  String get hiddenBannerTitle => 'Ocultado por un moderador';

  @override
  String get hiddenBannerMessage =>
      'Solo tú puedes ver este itinerario. No aparecerá en el feed, en la búsqueda ni en su página para compartir. Puedes apelar desde Estado de la cuenta en los ajustes.';

  @override
  String get hiddenReviewMessage =>
      'Solo tú puedes ver esta reseña. No aparecerá en el itinerario ni contará para su valoración.';

  @override
  String get hiddenProfileMessage =>
      'Solo tú puedes ver tu nombre visible y tu biografía. Los demás ven tu @nombre de usuario en su lugar.';

  @override
  String get accountStatusTitle => 'Estado de la cuenta';

  @override
  String get violationsEmpty => 'No hay acciones de moderación en tu cuenta.';

  @override
  String get violationHidden => 'Oculto';

  @override
  String get violationRemoved => 'Eliminado';

  @override
  String get violationWarned => 'Advertencia';

  @override
  String get violationBanned => 'Suspensión';

  @override
  String get violationOther => 'Acción de moderación';

  @override
  String get violationLifted => 'Levantada';

  @override
  String get appealPending => 'Apelación en revisión';

  @override
  String get appealRejected => 'Apelación rechazada';

  @override
  String get appealRestored => 'Restaurado';

  @override
  String get appealReduced => 'Sanción reducida';

  @override
  String get appealAvailable => 'Puedes apelar';

  @override
  String get appealSubmit => 'Apelar';

  @override
  String get appealSubmitted =>
      'Apelación enviada. Te enviaremos el resultado por correo.';

  @override
  String get appealFormTitle => 'Apelar esta decisión';

  @override
  String get appealFormMessage =>
      'Explica por qué crees que fue un error. Un moderador la revisará.';

  @override
  String get appealReasonLabel => 'Tu explicación';

  @override
  String get appealReasonRequired => 'Explica por qué apelas.';

  @override
  String appealCooldownUntil(String date) {
    return 'Podrás apelar de nuevo después del $date.';
  }

  @override
  String get apiErrorAppealPending =>
      'Ya tienes una apelación pendiente para este elemento.';

  @override
  String get apiErrorAppealCooldown =>
      'Solo puedes volver a apelar este elemento 30 días después de un rechazo.';

  @override
  String get apiErrorAppealTargetNotFound =>
      'Aquí no hay ninguna acción de moderación que apelar.';

  @override
  String get apiErrorTextModerationRejected =>
      'Este texto puede infringir las normas de la comunidad, así que no se guardó. Edítalo e inténtalo de nuevo.';

  @override
  String get apiErrorCannotBlockSelf => 'No puedes bloquearte a ti mismo.';

  @override
  String moderationRejectedBecause(String reason) {
    return 'Este texto no se guardó porque puede contener $reason. Edítalo e inténtalo de nuevo.';
  }

  @override
  String get moderationCategoryMinors => 'contenido que involucra a menores';

  @override
  String get moderationCategorySexual => 'contenido sexual';

  @override
  String get moderationCategoryHate => 'discurso de odio';

  @override
  String get moderationCategoryHarassment => 'acoso';

  @override
  String get moderationCategoryViolence => 'contenido violento';

  @override
  String get moderationCategorySelfHarm => 'contenido sobre autolesiones';

  @override
  String get moderationCategoryIllicit => 'actividad ilegal';

  @override
  String get reportReasonCsam => 'Material de abuso sexual infantil';

  @override
  String get reportReasonSexualContent => 'Desnudez o contenido sexual';

  @override
  String get reportReasonViolenceThreat => 'Violencia o amenazas';

  @override
  String get reportContent => 'Denunciar';

  @override
  String get reportUser => 'Denunciar esta cuenta';

  @override
  String get reportStop => 'Denunciar esta parada';

  @override
  String get reportReview => 'Denunciar esta reseña';

  @override
  String get reportAnnotation => 'Denunciar esta anotación';

  @override
  String get blockUser => 'Bloquear';

  @override
  String get unblockUser => 'Desbloquear';

  @override
  String blockUserTitle(String username) {
    return '¿Bloquear a @$username?';
  }

  @override
  String get blockUserMessage =>
      'No veréis los itinerarios ni los perfiles del otro, y ninguno podrá seguir al otro. No se le informará.';

  @override
  String get blockedUsers => 'Cuentas bloqueadas';

  @override
  String get blockedUsersEmpty => 'No has bloqueado a nadie.';

  @override
  String blockedUserRemoved(String username) {
    return '@$username desbloqueado.';
  }

  @override
  String blockedUserAdded(String username) {
    return '@$username bloqueado.';
  }

  @override
  String get abuseContact => 'Denunciar abuso';

  @override
  String get abuseContactSubtitle => 'Escríbenos sobre contenido dañino';

  @override
  String get communityGuidelines => 'Normas de la comunidad';

  @override
  String get moderationHintTitle => 'Esto podría leerse como ofensivo';

  @override
  String get moderationHintBody =>
      'Puedes publicarlo igualmente: esto es solo un aviso, no un bloqueo.';

  @override
  String get hiddenAppealAction => 'Pedir una revisión';

  @override
  String hiddenBannerReason(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get bugReportTitle => 'Informar de un problema';

  @override
  String get bugReportHint => '¿Qué ha pasado?';

  @override
  String get bugReportSubmit => 'Enviar informe';

  @override
  String get bugReportThanks => 'Gracias. Lo revisaremos.';

  @override
  String get bugReportAttachmentNotice =>
      'Se adjuntan tu captura de pantalla y los datos del dispositivo.';

  @override
  String get bugReportCategoryCrash => 'La app se bloqueó o se cerró';

  @override
  String get bugReportCategoryVisual => 'Algo se ve mal';

  @override
  String get bugReportCategoryData => 'Información incorrecta o ausente';

  @override
  String get bugReportCategorySlow => 'Demasiado lento';

  @override
  String get bugReportCategoryOther => 'Otra cosa';

  @override
  String get bugReportNavigate => 'Navegar';

  @override
  String get bugReportDraw => 'Dibujar';

  @override
  String get settingsReportBug => 'Informar de un error';

  @override
  String get settingsShakeToReport => 'Agitar para informar';

  @override
  String get settingsShakeToReportDetail =>
      'Agita el teléfono para informar de un problema';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsEmpty =>
      'Aún no hay nada.\nSeguidores, valoraciones y guardados aparecerán aquí.';

  @override
  String notificationsCountLabel(int count) {
    return 'Recientes · $count';
  }

  @override
  String get notificationSomeone => 'Alguien';

  @override
  String get notificationGeneric => 'Tienes una notificación nueva.';

  @override
  String get notificationTapForDetails => 'Toca para ver los detalles y apelar';

  @override
  String notificationFollowRequest(String name) {
    return '$name quiere seguirte';
  }

  @override
  String notificationNewFollower(String name) {
    return '$name empezó a seguirte';
  }

  @override
  String notificationFollowAccepted(String name) {
    return '$name aceptó tu solicitud de seguimiento';
  }

  @override
  String notificationRated(String name) {
    return '$name valoró uno de tus itinerarios';
  }

  @override
  String notificationSaved(String name) {
    return '$name guardó uno de tus itinerarios';
  }

  @override
  String notificationHidden(String title) {
    return '«$title» se ocultó';
  }

  @override
  String get notificationHiddenUntitled => 'Uno de tus itinerarios se ocultó';

  @override
  String notificationRemoved(String title) {
    return '«$title» se eliminó';
  }

  @override
  String get notificationRemovedUntitled => 'Uno de tus itinerarios se eliminó';

  @override
  String get notificationSettingsOptionalLabel => 'Opcionales';

  @override
  String get notificationSettingsRatings => 'Valoraciones';

  @override
  String get notificationSettingsRatingsDetail =>
      'Cuando alguien valora tu itinerario';

  @override
  String get notificationSettingsSaves => 'Guardados';

  @override
  String get notificationSettingsSavesDetail =>
      'Cuando alguien guarda tu itinerario';

  @override
  String get notificationSettingsFollowAccepted => 'Solicitud aceptada';

  @override
  String get notificationSettingsFollowAcceptedDetail =>
      'Cuando alguien acepta tu solicitud de seguimiento';

  @override
  String get notificationSettingsAlwaysOnNote =>
      'Las solicitudes de seguimiento y los avisos de moderación siempre están activados. Una solicitud que nunca ves no se puede responder, y necesitas saber cuándo se oculta tu contenido para poder apelar a tiempo.';

  @override
  String settingsNotificationsOnCount(int count) {
    return '$count de 3 activadas';
  }

  @override
  String get notificationWarned => 'Has recibido una advertencia de moderación';

  @override
  String get notificationWarnedDetail => 'Toca para ver por qué y apelar';

  @override
  String get notificationDelete => 'Eliminar notificación';

  @override
  String get notificationDeleted => 'Notificación eliminada';

  @override
  String get notificationsClearAll => 'Borrar todo';

  @override
  String get notificationsClearAllTitle => '¿Borrar todas las notificaciones?';

  @override
  String get notificationsClearAllMessage =>
      'Se eliminarán todas las notificaciones de tu lista. Los avisos de moderación permanecen en tu página Estado de la cuenta.';
}
