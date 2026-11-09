import 'dart:async';

import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/auth/token_manager.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/providers/locale_provider.dart';
import 'package:ntripi/core/providers/theme_mode_provider.dart';
import 'package:ntripi/core/push/push_gateway.dart';
import 'package:ntripi/core/push/push_service.dart';
import 'package:ntripi/core/router/app_router.dart';
import 'package:ntripi/core/storage/secure_storage.dart';
import 'package:ntripi/features/auth/presentation/widgets/tos_gate.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/core/ui/orientation_policy.dart';
import 'package:ntripi/features/bug_report/presentation/ntripi_feedback.dart';
import 'package:ntripi/features/bug_report/presentation/shake_to_report.dart';
import 'package:ntripi/features/notifications/presentation/widgets/notification_poller.dart';
import 'package:ntripi/l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The web's address bar shows the screen on top — a pushed trip or profile
  // included — so a reload stays on it and a copied URL opens it. go_router's
  // default shows the screen the pushes sit on. No effect off the web.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // A session from before the share pages' hint existed gets one now.
  if (kIsWeb) unawaited(syncWebSessionHint());

  // Phones stay portrait; a tablet turns and resizes, and the layout follows
  // the width (core/ui/app_layout.dart).
  await OrientationPolicy.start();

  // Hive-backed cache store for Dio responses. Web has no application
  // support directory, so caching is mobile/desktop-only.
  HiveCacheStore? cacheStore;
  if (!kIsWeb) {
    final dir = await getApplicationSupportDirectory();
    cacheStore = HiveCacheStore(dir.path);
  }

  // Auth wiring order matters:
  //   1. bareDio  — plain Dio, no interceptors. Used by TokenManager for
  //      /auth/refresh and by AuthRepository for /auth/logout. Cannot be
  //      the same instance as `dio` or those calls would recurse through
  //      AuthInterceptor.
  //   2. TokenManager — depends on bareDio.
  //   3. dio — main client, AuthInterceptor injected with the TokenManager.
  bareDio = createBareDio();
  final tokenManager = TokenManager(bareDio);
  dio = createDioClient(tokenManager: tokenManager, cacheStore: cacheStore);

  // A kept connection may be dead after a sleep or a network switch.
  WidgetsBinding.instance.addObserver(apiConnectionPool);
  networkChanges().listen((_) => apiConnectionPool.retire());

  // Before runApp so the background message handler is registered before any
  // push can arrive. Never throws — a missing google-services.json leaves the
  // app fully functional, just without push (NotificationPoller still runs).
  await initFirebase();

  runApp(
    ProviderScope(
      // Riverpod 3 auto-retries any provider whose build throws a non-Error
      // (incl. DioException) up to 10× with backoff. The app already renders
      // explicit error states (Retry buttons, lock placeholders), so disable
      // auto-retry to surface AsyncError immediately — matching Riverpod 2.
      retry: (_, _) => null,
      overrides: [
        // Provide the singleton TokenManager so AuthInterceptor and any
        // future consumers share the same in-flight refresh dedup state.
        tokenManagerProvider.overrideWithValue(tokenManager),
      ],
      child: const NtripiApp(),
    ),
  );
}

class NtripiApp extends ConsumerWidget {
  const NtripiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      // Shake-to-report's layer — above MaterialApp, see NtripiFeedback.
      child: NtripiFeedback(
        themeMode: themeMode,
        locale: locale,
        child: MaterialApp.router(
          title: 'NTripi',
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
          theme: buildNtripiTheme(),
          darkTheme: buildNtripiDarkTheme(),
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Theme(
            data: columnSnackBars(
                Theme.of(context), MediaQuery.sizeOf(context).width),
            // AppBar-less screens still need correct status/nav bar icon
            // brightness — reuse the style the theme sets on AppBars.
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: Theme.of(context).appBarTheme.systemOverlayStyle ??
                  SystemUiOverlayStyle.dark,
              // Inside MaterialApp so the shake handler has a ScaffoldMessenger
              // for the confirmation snackbar; BetterFeedback.of() still finds
              // the controller above.
              // TosGate wraps everything routed: many screens are declared at
              // the router's root level and would slip past a shell-mounted gate.
              // NotificationPoller sits here for the same reason, and gates
              // itself on the session so /login and /splash never poll.
              // PushGateway needs the same placement: it navigates with the
              // router, so it must be inside MaterialApp.router's builder.
              child: TosGate(
                child: NotificationPoller(
                  child: PushGateway(child: ShakeToReport(child: child!)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
