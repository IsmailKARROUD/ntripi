// features/bug_report/data/diagnostics_service.dart
//
// Gathers everything an operator needs to reproduce a report without a
// back-and-forth. Every lookup is wrapped: a platform channel that throws (an
// unsupported platform, a stripped build) yields null, never a failed report.

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/features/bug_report/domain/bug_report_diagnostics.dart';

/// Read once per launch — PackageInfo hits a platform channel and never changes.
final packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

/// Snapshot the app's state for a bug report. Safe to call from a shake handler
/// — nothing here needs a BuildContext.
Future<BugReportDiagnostics> collectDiagnostics(WidgetRef ref) async {
  final info = await ref.read(packageInfoProvider.future);

  return BugReportDiagnostics(
    appVersion: info == null ? null : '${info.version}+${info.buildNumber}',
    platform: _platform(),
    osVersion: await _osVersion(),
    deviceModel: await _deviceModel(),
    route: _currentRoute(),
    locale: ref.read(localeProvider).languageCode,
    themeMode: ref.read(themeModeProvider).name,
  );
}

// Wire values — must match BUG_PLATFORMS in the backend model, which drops
// anything it does not recognise.
String? _platform() {
  if (kIsWeb) return 'web';
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return null;
  }
}

/// The go_router path the user was on. Read off the delegate rather than a
/// BuildContext so a shake outside the widget tree can still call it.
String? _currentRoute() {
  try {
    return appRouter.routerDelegate.currentConfiguration.uri.path;
  } catch (_) {
    return null;
  }
}

Future<String?> _osVersion() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      return web.userAgent;
    }
    if (Platform.isIOS) {
      final ios = await plugin.iosInfo;
      return '${ios.systemName} ${ios.systemVersion}';
    }
    if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
    }
    return Platform.operatingSystemVersion;
  } catch (_) {
    return null;
  }
}

Future<String?> _deviceModel() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      return web.browserName.name;
    }
    if (Platform.isIOS) {
      // utsname.machine is the hardware id ("iPhone15,2"); `model` is only
      // ever the generic "iPhone", which does not narrow a layout bug at all.
      final ios = await plugin.iosInfo;
      return ios.utsname.machine;
    }
    if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return '${android.manufacturer} ${android.model}';
    }
    return null;
  } catch (_) {
    return null;
  }
}
