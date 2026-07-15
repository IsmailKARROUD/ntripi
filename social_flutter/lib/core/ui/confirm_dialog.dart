import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

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
    this.confirmLabel,
    this.cancelLabel,
    this.tone = ConfirmTone.defaultTone,
  });

  final String title;
  final String? message;
  final IconData icon;

  /// Defaults to the localized Confirm / Cancel labels when null.
  final String? confirmLabel;
  final String? cancelLabel;
  final ConfirmTone tone;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    IconData icon = Icons.help_outline,
    String? confirmLabel,
    String? cancelLabel,
    ConfirmTone tone = ConfirmTone.defaultTone,
  }) async {
    // showGeneralDialog (not showDialog) so we control the scrim tint and the
    // fade + scale + translate entrance the design calls for.
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: context.nt.scrim,
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
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final isDanger = tone == ConfirmTone.danger;
    final accent = isDanger ? nt.danger : nt.forest;
    final badgeBg = isDanger ? nt.dangerTint : nt.mist;

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 296,
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 18),
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: nt.bark.withValues(alpha: 0.18),
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
                  color: nt.bark,
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
                    color: nt.text2,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _ConfirmButton(
                      label: cancelLabel ?? l10n.cancel,
                      // calm/safe action: sand fill, bordered, dark text
                      background: nt.sand,
                      foreground: nt.bark,
                      borderColor: nt.border,
                      fontWeight: FontWeight.w600,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ConfirmButton(
                      label: confirmLabel ?? l10n.confirmButton,
                      // committing action: tone-accent fill; on-colors keep
                      // contrast when dark mode lightens the accents
                      background: accent,
                      foreground: isDanger
                          ? Theme.of(context).colorScheme.onError
                          : Theme.of(context).colorScheme.onPrimary,
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
