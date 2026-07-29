// core/utils/appeal_link.dart — opens the moderation appeal page.
//
// Shared by SuspendedScreen and the login error banner: a suspended account
// can't call the API at all, so the appeal has to happen on the web, authorized
// by an emailed signed link. The page asks for the account email and sends it.

import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the public, tokenless appeal request form in a browser.
/// The suspension email also carries a direct link to the same flow.
Future<void> openAppealPage() async {
  await launchUrl(
    Uri.parse('$kApiBaseUrl/appeal'),
    mode: LaunchMode.externalApplication,
  );
}
