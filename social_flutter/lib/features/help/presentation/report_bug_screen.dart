// features/help/presentation/report_bug_screen.dart
//
// Teaches the shake gesture instead of starting a report.
//
// Filing from here would capture *this* screen, which is never the screen that
// broke — the old Settings row popped the sheet and deferred a frame to work
// around exactly that, and still caught the wrong thing. The gesture already
// captures wherever the user is, so this screen's whole job is to say so.
//
// Web is the exception: there is no accelerometer, so the button is the only
// way in and it stays.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/bug_report/presentation/bug_report_entry.dart';
import 'package:social_flutter/features/bug_report/providers/shake_report_enabled_provider.dart';
import 'package:social_flutter/features/help/presentation/widgets/shake_phone_demo.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

class ReportBugScreen extends ConsumerWidget {
  /// Test seam only. `kIsWeb` is a compile-time constant, so the web branch is
  /// otherwise unreachable from a test running on the Flutter test host.
  @visibleForTesting
  final bool? forceWeb;

  const ReportBugScreen({super.key, this.forceWeb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final isWeb = forceWeb ?? kIsWeb;
    final gestureOn = ref.watch(shakeReportEnabledProvider);

    return Scaffold(
      backgroundColor: nt.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: EditorialTopBar(title: l10n.settingsReportBug),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  children: isWeb
                      ? _webBody(ref, nt, l10n)
                      : _shakeBody(ref, nt, l10n, gestureOn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _shakeBody(
    WidgetRef ref,
    NtripiColors nt,
    AppLocalizations l10n,
    bool gestureOn,
  ) =>
      [
        Center(child: ShakePhoneDemo(muted: !gestureOn)),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Text(
                l10n.reportBugShakeHeadline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.reportBugShakeBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: nt.text2, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionLabel(
          icon: Icons.list_alt_rounded,
          label: l10n.reportBugStepsLabel,
        ),
        SectionCard(
          children: [
            _StepRow(number: 1, text: l10n.reportBugShakeStep1),
            _StepRow(number: 2, text: l10n.reportBugShakeStep2),
            _StepRow(number: 3, text: l10n.reportBugShakeStep3, isLast: true),
          ],
        ),
        // Without this the screen would tell someone to shake while the gesture
        // is switched off and nothing would happen. The switch is here as well
        // as in Settings so it can be fixed where the problem is noticed.
        if (!gestureOn) ...[
          const SizedBox(height: 18),
          SectionCard(
            children: [
              EditorialRow(
                icon: Icons.vibration_rounded,
                iconBg: nt.cautionBg,
                iconColor: nt.cautionFg,
                label: l10n.settingsShakeToReport,
                subtitle: l10n.reportBugGestureOff,
                isLast: true,
                trailing: Switch(
                  value: false,
                  onChanged: (value) => ref
                      .read(shakeReportEnabledProvider.notifier)
                      .setEnabled(value),
                ),
                onTap: () => ref
                    .read(shakeReportEnabledProvider.notifier)
                    .setEnabled(true),
              ),
            ],
          ),
        ],
      ];

  List<Widget> _webBody(
    WidgetRef ref,
    NtripiColors nt,
    AppLocalizations l10n,
  ) =>
      [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: nt.mist,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.bug_report_outlined, size: 34, color: nt.forest),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            l10n.reportBugWebBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: nt.text2, height: 1.5),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ElevatedButton(
            // The root context, not this screen's: BetterFeedback wraps
            // MaterialApp, so only a context above the router can find it.
            onPressed: () {
              final root = navigatorKey.currentContext;
              if (root != null) startBugReport(root, ref);
            },
            child: Text(l10n.settingsReportBug),
          ),
        ),
      ];
}

class _StepRow extends StatelessWidget {
  final int number;
  final String text;
  final bool isLast;

  const _StepRow({
    required this.number,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nt.mist,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: nt.forest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: nt.bark,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 50),
            color: nt.border,
          ),
      ],
    );
  }
}
