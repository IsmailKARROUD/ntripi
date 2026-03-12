// main.dart — Flutter app entry point.
//
// Responsibilities:
//   1. Initialise the Dio HTTP client (with auth interceptor).
//   2. Wrap the app in ProviderScope (required by Riverpod).
//   3. Configure the MaterialApp with go_router.
//
// Why ProviderScope at the root?
//   Riverpod's ProviderScope stores all provider state.
//   It must be an ancestor of every widget that reads a provider.
//   Placing it at the very root ensures no widget is ever outside it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/router/app_router.dart';

void main() {
  // Ensure Flutter bindings are initialised before any platform channel calls.
  // Required when calling native APIs (like secure storage) before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the global Dio client.
  // This sets up the base URL and attaches the auth interceptor.
  dio = createDioClient();

  runApp(
    // ProviderScope is the Riverpod state container.
    // All providers are lazily initialized inside this scope.
    const ProviderScope(
      child: NtripiApp(),
    ),
  );
}

class NtripiApp extends StatelessWidget {
  const NtripiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ntripi',
      debugShowCheckedModeBanner: false,

      // go_router integration: MaterialApp.router takes a RouterConfig.
      routerConfig: appRouter,

      // Material 3 theme with a purple seed color.
      // In a real app, you'd define a full custom ColorScheme.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
    );
  }
}
