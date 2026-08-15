// features/itineraries/domain/edit_lock.dart — the server's view of who is
// editing an itinerary right now.
//
// Every field here is the server's answer. The client formats and counts down;
// it never decides whether a claim is stale, whether it may be taken, or
// whether this device still holds it. Two clocks would disagree, and the one
// that matters is the one the write path uses.

/// How alive a claim looks. Ordered weakest-claim-last.
enum EditLockState {
  /// Heartbeat is current — somebody is there.
  active,

  /// Gone quiet, but the claim still stands. Presentational only: nobody but
  /// the owner may take it.
  idle,

  /// Silent past the TTL. Any editor may take over now.
  takeable;

  /// Unknown values degrade to [active] — the conservative direction. A newer
  /// backend must never make an older client offer a takeover it does not
  /// understand. Same rule as ModerationStatus.fromString.
  static EditLockState fromString(String? raw) => switch (raw) {
        'idle' => EditLockState.idle,
        'takeable' => EditLockState.takeable,
        _ => EditLockState.active,
      };
}

/// A live editing claim, as anyone who can view the itinerary may see it.
class EditLock {
  const EditLock({
    required this.holderId,
    required this.holderUsername,
    this.holderDisplayName,
    this.holderAvatarUrl,
    required this.isYou,
    required this.state,
    required this.acquiredAt,
    required this.lastHeartbeatAt,
    required this.idleAt,
    required this.takeoverAvailableAt,
  });

  final String holderId;
  final String holderUsername;
  final String? holderDisplayName;
  final String? holderAvatarUrl;

  /// Whether the holder is the signed-in user — on some other device. True here
  /// is what lets the UI say "you're editing this elsewhere" instead of naming
  /// the person back to themselves.
  final bool isYou;

  final EditLockState state;
  final DateTime acquiredAt;
  final DateTime lastHeartbeatAt;

  /// When the holder starts rendering as inactive.
  final DateTime idleAt;

  /// When any editor may take the claim. Absolute, not a remaining-seconds
  /// count: the server sends timestamps so its GET body stays byte-identical
  /// between polls and costs a 304 instead of a payload.
  final DateTime takeoverAvailableAt;

  String get displayLabel =>
      (holderDisplayName?.isNotEmpty ?? false) ? holderDisplayName! : '@$holderUsername';

  /// How long until anyone may take over. Never negative.
  Duration remainingUntilTakeover([DateTime? now]) {
    final delta = takeoverAvailableAt.difference(now ?? DateTime.now());
    return delta.isNegative ? Duration.zero : delta;
  }

  factory EditLock.fromJson(Map<String, dynamic> json) => EditLock(
        holderId: json['holder_id'] as String,
        holderUsername: json['holder_username'] as String? ?? '',
        holderDisplayName: json['holder_display_name'] as String?,
        holderAvatarUrl: json['holder_avatar_url'] as String?,
        isYou: json['is_you'] as bool? ?? false,
        state: EditLockState.fromString(json['state'] as String?),
        acquiredAt: DateTime.parse(json['acquired_at'] as String).toLocal(),
        lastHeartbeatAt:
            DateTime.parse(json['last_heartbeat_at'] as String).toLocal(),
        idleAt: DateTime.parse(json['idle_at'] as String).toLocal(),
        takeoverAvailableAt:
            DateTime.parse(json['takeover_available_at'] as String).toLocal(),
      );
}

/// The answer to `GET /itineraries/{id}/lock` — who is editing, and whether
/// this viewer could.
class EditLockStatus {
  const EditLockStatus({
    required this.canEdit,
    required this.lock,
    required this.heartbeatInterval,
    required this.ttl,
  });

  final bool canEdit;
  final EditLock? lock;

  /// How often the server wants to be pinged while editing. Server-supplied so
  /// the cadence can be tuned without shipping a client.
  final Duration heartbeatInterval;
  final Duration ttl;

  factory EditLockStatus.fromJson(Map<String, dynamic> json) => EditLockStatus(
        canEdit: json['can_edit'] as bool? ?? false,
        lock: json['lock'] is Map<String, dynamic>
            ? EditLock.fromJson(json['lock'] as Map<String, dynamic>)
            : null,
        heartbeatInterval:
            Duration(seconds: json['heartbeat_interval_seconds'] as int? ?? 30),
        ttl: Duration(seconds: json['ttl_seconds'] as int? ?? 300),
      );
}

/// The response to a successful claim. [token] is the only copy the client will
/// ever get; every takeover mints a new one and invalidates this.
class EditLockClaim {
  const EditLockClaim({
    required this.token,
    required this.lock,
    required this.heartbeatInterval,
    required this.ttl,
  });

  final String token;
  final EditLock lock;
  final Duration heartbeatInterval;
  final Duration ttl;

  factory EditLockClaim.fromJson(Map<String, dynamic> json) => EditLockClaim(
        token: json['token'] as String,
        lock: EditLock.fromJson(json['lock'] as Map<String, dynamic>),
        heartbeatInterval:
            Duration(seconds: json['heartbeat_interval_seconds'] as int? ?? 30),
        ttl: Duration(seconds: json['ttl_seconds'] as int? ?? 300),
      );
}
