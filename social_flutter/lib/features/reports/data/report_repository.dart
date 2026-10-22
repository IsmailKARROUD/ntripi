// features/reports/data/report_repository.dart — reporting and blocking.
//
// Both are safety actions the user takes about someone else, so they share a
// repository. Reports are fire-and-forget (the backend decides what happens);
// a block answers with the follow counts it moved, which callers adopt, and
// changes what the current user can see, which callers invalidate.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/reports/domain/report_target.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

class ReportRepository {
  final Dio _dio;

  ReportRepository(this._dio);

  Future<void> report({
    required ReportTarget target,
    required String reason,
    String? notes,
  }) async {
    final withContext = target.notesWithContext(notes);
    await _dio.post(kReportsEndpoint, data: {
      'target_type': target.wireKind,
      'target_id': target.id,
      'reason': reason,
      if (withContext != null) 'notes': withContext,
    });
  }

  /// Blocking severs any follow both ways, so it answers with the signed-in
  /// user's counts as it left them (`them` is null: the profile is gone).
  Future<FollowCounts> block(String userId) async {
    final response = await _dio.post(
      kBlockEndpoint(userId),
      queryParameters: kReturnFollowCounts,
    );
    return FollowCounts.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> unblock(String userId) async {
    await _dio.delete(kBlockEndpoint(userId));
  }

  Future<List<User>> blockedUsers() async {
    final response = await _dio.get(kMyBlocksEndpoint);
    final rows = (response.data as List).cast<Map<String, dynamic>>();
    return rows.map(User.fromJson).toList();
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(dio);
});

/// The accounts the current user has blocked. Invalidated after block/unblock
/// so the settings list and any client-side filtering stay in step.
final blockedUsersProvider = FutureProvider<List<User>>((ref) async {
  return ref.watch(reportRepositoryProvider).blockedUsers();
});

/// Just the ids — used to filter lists client-side so blocked content never
/// flashes before a refresh. The server is still the authority.
final blockedUserIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(blockedUsersProvider).maybeWhen(
        data: (users) => users.map((user) => user.id).toSet(),
        orElse: () => const <String>{},
      );
});
