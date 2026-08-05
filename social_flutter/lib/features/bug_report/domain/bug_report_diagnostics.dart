// features/bug_report/domain/bug_report_diagnostics.dart
//
// What the app knows about itself when a bug is reported. Everything here is
// best-effort: a platform channel that throws yields null rather than costing
// the user their report, and the backend drops any value it does not recognise
// instead of 422-ing the whole submission.

/// Problem kinds offered in the compose sheet. Wire values — must stay in sync
/// with BUG_CATEGORIES in social_api/app/models/bug_report.py.
const kBugCategories = <String>['crash', 'visual', 'data', 'slow', 'other'];

class BugReportDiagnostics {
  final String? appVersion;
  final String? platform;
  final String? osVersion;
  final String? deviceModel;
  final String? route;
  final String? locale;
  final String? themeMode;

  const BugReportDiagnostics({
    this.appVersion,
    this.platform,
    this.osVersion,
    this.deviceModel,
    this.route,
    this.locale,
    this.themeMode,
  });

  /// Multipart form fields. Nulls are omitted rather than sent as empty strings
  /// so "we could not read this" and "this is blank" stay distinguishable.
  Map<String, String> toFields() => {
        if (appVersion != null) 'app_version': appVersion!,
        if (platform != null) 'platform': platform!,
        if (osVersion != null) 'os_version': osVersion!,
        if (deviceModel != null) 'device_model': deviceModel!,
        if (route != null) 'route': route!,
        if (locale != null) 'locale': locale!,
        if (themeMode != null) 'theme_mode': themeMode!,
      };
}
