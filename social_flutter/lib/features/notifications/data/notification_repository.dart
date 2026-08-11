// features/notifications/data/notification_repository.dart — notification API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';

class NotificationRepository {
  final Dio _dio;

  const NotificationRepository(this._dio);

  /// GET /notifications — one page plus the unread count.
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get(
      kNotificationsEndpoint,
      queryParameters: {'limit': limit, 'offset': offset},
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return NotificationsPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// GET /notifications/unread-count — just the badge: the count plus the
  /// arrival timestamp the new-notification cue keys off.
  Future<NotificationBadge> getBadge({bool forceRefresh = false}) async {
    final response = await _dio.get(
      kNotificationsUnreadCountEndpoint,
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return NotificationBadge.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /notifications/read — `ids` null marks every unread notification read.
  Future<void> markRead({List<String>? ids}) async {
    await _dio.post(
      kNotificationsReadEndpoint,
      data: ids == null ? <String, dynamic>{} : {'ids': ids},
    );
  }

  /// DELETE /notifications/{id} — idempotent, so a resend after the row is
  /// already gone is not an error.
  Future<void> deleteNotification(String id) async {
    await _dio.delete(notificationEndpoint(id));
  }

  /// DELETE /notifications — empty the feed.
  Future<void> clearAll() async {
    await _dio.delete(kNotificationsEndpoint);
  }
}
