import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive-backed cache store for Dio responses. Web has no application
  // support directory, so caching is mobile/desktop-only.
  HiveCacheStore? cacheStore;
  if (!kIsWeb) {
    final dir = await getApplicationSupportDirectory();
    cacheStore = HiveCacheStore(dir.path);
  }

  dio = createDioClient(cacheStore: cacheStore);
  runApp(
    const ProviderScope(
      child: NtripiApp(),
    ),
  );
}

class NtripiApp extends StatelessWidget {
  const NtripiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: MaterialApp.router(
        title: 'NTripi',
        debugShowCheckedModeBanner: false,
        routerConfig: appRouter,
        theme: buildNtripiTheme(),
      ),
    );
  }
}
