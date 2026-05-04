import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  dio = createDioClient();
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
