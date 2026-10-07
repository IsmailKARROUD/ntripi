// features/itineraries/domain/annotation.dart — Annotation Dart model.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// The four types of annotation a user can attach to a stop.
enum AnnotationType {
  advice,   // Helpful tip
  caution,  // Something to be aware of
  avoid,    // Something to skip
  info;     // Neutral information

  // Single source for the type's name/description — was duplicated (with
  // diverging labels "Tip" vs "Advice") across four presentation files.
  String label(AppLocalizations l10n) => switch (this) {
        advice => l10n.annotationAdvice,
        caution => l10n.annotationCaution,
        avoid => l10n.annotationAvoid,
        info => l10n.annotationInfo,
      };

  /// Server strings go through this, never `values.byName`: an unknown type from
  /// a newer backend degrades to the neutral one instead of failing the whole
  /// itinerary parse.
  static AnnotationType fromString(String? value) =>
      AnnotationType.values.asNameMap()[value] ?? AnnotationType.info;

  String description(AppLocalizations l10n) => switch (this) {
        advice => l10n.annotationAdviceDesc,
        caution => l10n.annotationCautionDesc,
        avoid => l10n.annotationAvoidDesc,
        info => l10n.annotationInfoDesc,
      };

  IconData get icon => switch (this) {
        advice => Icons.lightbulb_rounded,
        caution => Icons.warning_rounded,
        avoid => Icons.block_rounded,
        info => Icons.info_rounded,
      };

  /// Editorial background/foreground pair shared by the annotation screens.
  /// Takes the palette (not a BuildContext) — domain code stays widget-free.
  Color bg(NtripiColors nt) => switch (this) {
        advice => nt.adviceBg,
        caution => nt.cautionBg,
        avoid => nt.avoidBg,
        info => nt.infoBg,
      };

  Color fg(NtripiColors nt) => switch (this) {
        advice => nt.adviceFg,
        caution => nt.cautionFg,
        avoid => nt.avoidFg,
        info => nt.infoFg,
      };
}

/// A user-written note attached to a stop.
class Annotation {
  final String id;
  final String stopId;
  final AnnotationType type;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Language the server detected for this text (ISO 639-1), or null when
  /// it could not tell — decides whether "See translation" is offered.
  final String? sourceLang;

  const Annotation({
    required this.id,
    required this.stopId,
    required this.type,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.sourceLang,
  });

  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'] as String,
      stopId: json['stop_id'] as String,
      type: AnnotationType.fromString(json['type'] as String?),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sourceLang: json['source_lang'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stop_id': stopId,
      'type': type.name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (sourceLang != null) 'source_lang': sourceLang,
    };
  }

  Annotation copyWith({
    AnnotationType? type,
    String? content,
    DateTime? updatedAt,
  }) {
    return Annotation(
      id: id,
      stopId: stopId,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLang: sourceLang,
    );
  }
}
