import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Visual intent of a [ConfirmDialog] — drives the accent + icon-badge colors.
enum ConfirmTone { defaultTone, danger }

/// Reusable, presentational confirmation modal. Callers decide what confirm /
/// cancel mean; this widget holds no state and only reports the choice.
///
/// Use [ConfirmDialog.show] to display it — it returns `true` when confirmed,
/// and `false` when cancelled or dismissed (scrim tap / back).
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.help_outline,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.tone = ConfirmTone.defaultTone,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String confirmLabel;
  final String cancelLabel;
  final ConfirmTone tone;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    IconData icon = Icons.help_outline,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    ConfirmTone tone = ConfirmTone.defaultTone,
  }) async {
    // showGeneralDialog (not showDialog) so we control the scrim tint and the
    // fade + scale + translate entrance the design calls for.
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x75142018), // ≈ rgba(20,32,24,0.46)
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ConfirmDialog(
        title: title,
        message: message,
        icon: icon,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        tone: tone,
      ),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: Transform.translate(
            // slight upward settle as it appears
            offset: Offset(0, (1 - curved.value) * 10),
            child: Transform.scale(
              scale: 0.94 + curved.value * 0.06, // 0.94 → 1.0
              child: child,
            ),
          ),
        );
      },
    );
    return result ?? false; // scrim tap / back dismiss → cancelled
  }

  @override
  Widget build(BuildContext context) {
    final isDanger = tone == ConfirmTone.danger;
    final accent = isDanger ? kDanger : kForest;
    final badgeBg = isDanger ? kDangerTint : kMist;

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 296,
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: kBark.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 13.5,
                    height: 1.5,
                    color: kText2,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _ConfirmButton(
                      label: cancelLabel,
                      // calm/safe action: sand fill, bordered, dark text
                      background: kSand,
                      foreground: kBark,
                      borderColor: kBorder,
                      fontWeight: FontWeight.w600,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ConfirmButton(
                      label: confirmLabel,
                      // committing action: filled with tone accent, white text
                      background: accent,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadowColor: accent.withValues(alpha: 0.30),
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Equal-width 46-high pill used for both dialog actions; styling is fully
/// driven by the caller so the same widget renders calm and accent variants.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.fontWeight,
    required this.onTap,
    this.borderColor,
    this.shadowColor,
  });

  final String label;
  final Color background;
  final Color foreground;
  final FontWeight fontWeight;
  final VoidCallback onTap;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadowColor == null
            ? null
            : [
                BoxShadow(
                  color: shadowColor!,
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: background,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: borderColor == null
                ? null
                : BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: borderColor!),
                  ),
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: fontWeight,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
