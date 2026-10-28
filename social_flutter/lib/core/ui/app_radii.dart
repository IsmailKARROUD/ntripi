// ─────────────────────────────────────────────────────────────────────────────
// This file is the single source of truth for EVERY corner radius in the app.
// Rule: no number may be passed to Radius.circular / BorderRadius.circular
// outside this file — a corner takes the token of its job, so two boxes that
// do the same job cannot drift apart. test/radius_scale_guard_test.dart holds
// the rule; artwork drawn to scale (the logo, the loaders) is its only
// exception.
//
// The web pages mirror this scale as CSS variables in
// social_api/app/templates/_radius_tokens.html, and social_api's
// test_radius_scale.py fails when the two disagree — change both together.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class NtripiRadius {
  /// Grouping cards (SectionCard), large boxes on the page ground (the trip
  /// page's map, its edit-mode info boxes), icon tiles of 56 px and up.
  static const double card = 18;

  /// Text fields, and the rows that stand in for one.
  static const double field = 14;

  /// Every button — filled, elevated, outlined — and the FAB.
  static const double button = 14;

  /// Small boxes: banners and notices, small tiles, boxes inside a card,
  /// image clips, map overlays, the snackbar, menus and popovers.
  static const double tile = 12;

  /// Icon badges and icon tiles up to 48 px, square icon buttons.
  static const double icon = 10;

  /// A segmented toggle's track — the custom ones and SegmentedButton.
  static const double toggle = 12;

  /// A box inside another's padding: a toggle's thumb, a menu's item.
  static const double inset = 8;

  /// Always a full pill: chips, tags, badges, round buttons, drag handles,
  /// bars.
  static const double pill = 999;

  /// The top corners of a bottom sheet; every corner of a dialog.
  static const double modal = 28;

  static const double checkbox = 4;
}
