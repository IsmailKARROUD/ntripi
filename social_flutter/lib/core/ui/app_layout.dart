// ─────────────────────────────────────────────────────────────────────────────
// The one width rule, on every device. Width decides, never the platform: a
// phone fills the column, while a tablet, a browser window or a tablet in
// Split View centres it with plain space on both sides. Once that space can
// hold the tabs' side bar, the tabs move into it (the shell in
// core/router/app_router.dart). Screens take the rule through ContentColumn /
// ContentPage (shared/widgets/content_column.dart);
// test/content_column_guard_test.dart holds it.
// ─────────────────────────────────────────────────────────────────────────────

/// The widest any screen's content gets — sheets included.
const double kContentMaxWidth = 600;

/// The side bar the tabs move into on a wide window.
const double kSideBarWidth = 80;

/// Whether the tabs' side bar fits beside the column on a window this wide.
///
/// Both sides must hold a bar's width, so the column stays centred on the
/// window and never shrinks: a trip page, which has no bar, puts its column in
/// exactly the same place.
bool sideBarFits(double windowWidth) =>
    windowWidth >= kContentMaxWidth + 2 * kSideBarWidth;
