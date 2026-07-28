// features/profile/domain/violation.dart — One moderation action taken against
// the signed-in user, as shown on the Account status screen.
//
// The server sends only a title from its snapshot, never the moderated content
// itself, so this model deliberately has nowhere to put the original text.

/// What a moderator did. Unknown values (a future action type) fall back to
/// [ModerationAction.unknown] rather than throwing — same tolerance as
/// PlaceType.fromString.
enum ModerationAction { hide, delete, warn, ban, unknown }

/// Where an appeal stands. Null on the model means no appeal was ever filed.
enum AppealStatus { pending, upheld, restored, reduced, unknown }

class Violation {
  final String id;
  final ModerationAction action;
  final String targetType;
  final String? targetId;

  /// Title captured at action time; null for account-level actions.
  final String? itemTitle;
  final DateTime createdAt;

  /// False once the penalty was lifted (unhidden, unbanned, appeal restored).
  final bool active;

  /// Server's verdict on whether an appeal can be opened right now — it owns
  /// the one-open-appeal and 30-day-cooldown rules, the client only renders them.
  final bool appealable;
  final AppealStatus? appealStatus;

  /// Set while a rejected appeal still blocks re-appealing.
  final DateTime? cooldownUntil;

  const Violation({
    required this.id,
    required this.action,
    required this.targetType,
    this.targetId,
    this.itemTitle,
    required this.createdAt,
    required this.active,
    required this.appealable,
    this.appealStatus,
    this.cooldownUntil,
  });

  factory Violation.fromJson(Map<String, dynamic> json) => Violation(
        id: json['id'] as String,
        action: _actionFromString(json['action'] as String?),
        targetType: json['target_type'] as String? ?? 'itinerary',
        targetId: json['target_id'] as String?,
        itemTitle: json['item_title'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        active: json['active'] as bool? ?? true,
        appealable: json['appealable'] as bool? ?? false,
        appealStatus: _statusFromString(json['appeal_status'] as String?),
        cooldownUntil: json['cooldown_until'] == null
            ? null
            : DateTime.parse(json['cooldown_until'] as String),
      );

  static ModerationAction _actionFromString(String? raw) => switch (raw) {
        'hide' => ModerationAction.hide,
        'delete' => ModerationAction.delete,
        'warn' => ModerationAction.warn,
        'ban' => ModerationAction.ban,
        _ => ModerationAction.unknown,
      };

  static AppealStatus? _statusFromString(String? raw) => switch (raw) {
        'pending' => AppealStatus.pending,
        'upheld' => AppealStatus.upheld,
        'restored' => AppealStatus.restored,
        'reduced' => AppealStatus.reduced,
        null => null,
        _ => AppealStatus.unknown,
      };
}
