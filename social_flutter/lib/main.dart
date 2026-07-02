import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/auth/token_manager.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock the app to portrait — landscape layouts are unsupported.
  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

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
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: MaterialApp.router(
        title: 'NTripi',
        debugShowCheckedModeBanner: false,
        routerConfig: appRouter,
        theme: buildNtripiTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
