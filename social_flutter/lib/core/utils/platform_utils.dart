import 'package:flutter/foundation.dart';

/// True only when running in a desktop web browser (macOS, Windows, Linux).
/// Returns false on native iOS/Android and on mobile web browsers.
const double kDesktopMaxWidth = 480;

bool isDesktopWeb() =>
    kIsWeb &&
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;
