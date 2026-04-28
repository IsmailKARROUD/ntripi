// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isApplePlatform() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('macintosh') ||
      ua.contains('mac os x');
}
