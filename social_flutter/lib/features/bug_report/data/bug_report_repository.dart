// features/bug_report/data/bug_report_repository.dart
//
// Fire-and-forget submission of an in-app bug report. Multipart rather than
// JSON + a second upload: two requests would orphan the screenshot in R2
// whenever the second failed.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/bug_report/domain/bug_report_diagnostics.dart';

class BugReportRepository {
  final Dio _dio;

  BugReportRepository(this._dio);

  Future<void> submit({
    required String message,
    String? category,
    required BugReportDiagnostics diagnostics,
    Uint8List? screenshot,
  }) async {
    final form = FormData.fromMap({
      ...diagnostics.toFields(),
      'message': message,
      if (category != null) 'category': category,
      // The `feedback` package hands back raw PNG bytes; the backend re-encodes
      // to JPEG and strips metadata in process_screenshot_image.
      if (screenshot != null)
        'screenshot': MultipartFile.fromBytes(
          screenshot,
          filename: 'screenshot.png',
        ),
    });
    await _dio.post(kBugReportsEndpoint, data: form);
  }
}

final bugReportRepositoryProvider = Provider<BugReportRepository>((ref) {
  return BugReportRepository(dio);
});
