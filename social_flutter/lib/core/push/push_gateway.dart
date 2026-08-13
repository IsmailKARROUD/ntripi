// core/push/push_gateway.dart — mounts the push listeners inside the app.
//
// push_service.dart owns the FCM plumbing; this owns the two things that need a
// live widget tree: a router to navigate with, and the locale provider to keep
// the server's rendered push text in the language the user actually picked.
//
// Mounted beside NotificationPoller in MaterialApp's builder, and no-ops
// entirely on web or when Firebase never came up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/push/push_service.dart';
import 'package:social_flutter/core/router/app_router.dart';

class PushGateway extends ConsumerStatefulWidget {
  final Widget child;

  const PushGateway({super.key, required this.child});

  @override
  ConsumerState<PushGateway> createState() => _PushGatewayState();
}

class _PushGatewayState extends ConsumerState<PushGateway> {
  /// The locale the server was last told about, so a rebuild that did not
  /// change the language does not spend a request saying so.
  String? _sentLocale;

  @override
  void initState() {
    super.initState();
    attachPushListeners(
      // Read lazily: a token refresh can land long after this frame, by which
      // time the user may have changed language.
      currentLocale: () => ref.read(localeProvider).languageCode,
      onRoute: appRouter.go,
    );

    // A cold start from a terminated app resolves its tap before the router
    // exists, so push_service parks the route rather than dropping it. Drained
    // after the first frame, once appRouter has something to navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = takePendingRoute();
      if (route != null && mounted) appRouter.go(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Follow the in-app language picker: the push body is rendered server-side,
    // so the device row is the only place that knows which language to use.
    final locale = ref.watch(localeProvider).languageCode;
    if (pushRegistered && locale != _sentLocale) {
      _sentLocale = locale;
      // Fire-and-forget, and never from inside build's synchronous phase.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => updatePushLocale(locale),
      );
    }
    return widget.child;
  }
}
