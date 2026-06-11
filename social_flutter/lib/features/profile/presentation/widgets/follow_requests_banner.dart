import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class FollowRequestsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const FollowRequestsBanner(
      {super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD0EBDA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_rounded, size: 20, color: kForest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.followRequestsBannerTitle(count),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kForest,
                    ),
                  ),
                  Text(
                    l10n.tapToReview,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kForest,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kForest, size: 20),
          ],
        ),
      ),
    );
  }
}
