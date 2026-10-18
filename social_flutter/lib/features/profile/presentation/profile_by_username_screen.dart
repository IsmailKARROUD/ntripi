// features/profile/presentation/profile_by_username_screen.dart
//
// A shared profile link names a handle (/share/u/<name>) — handles are
// immutable, so the link cannot rot — while every profile route in the app
// takes an account id. This screen turns the one into the other, then simply
// is the profile screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_error_codes.dart';
import 'package:ntripi/core/router/navigation_ext.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_unavailable_view.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

class ProfileByUsernameScreen extends ConsumerWidget {
  final String username;

  const ProfileByUsernameScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final resolved = ref.watch(profileIdByUsernameProvider(username));
    final me = ref.watch(myProfileProvider);
    void leave() => context.popOr('/profile/me');

    Widget page(Widget body) =>
        Scaffold(backgroundColor: nt.surface, body: body);
    final loading = page(const Center(child: NTripiCompassLoader()));

    return resolved.when(
      loading: () => loading,
      // The same 404 for an unknown, deleted or suspended account and across a
      // block — so the same words, and no Retry that could never help.
      error: (error, _) => page(
        isGoneError(error)
            ? ProfileUnavailableView(onBack: leave)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        extractErrorMessage(error, l10n),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(
                            profileIdByUsernameProvider(username)),
                        child: Text(l10n.retry),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: leave,
                        child: Text(l10n.goBack),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      data: (id) {
        // Your own handle opens your own profile, not a stranger's view of it
        // with a Follow button aimed at yourself — so wait to know who you are.
        final myId = me.value?.id;
        if (myId == null && me.isLoading) return loading;
        return id == myId ? const ProfileScreen() : ProfileScreen(userId: id);
      },
    );
  }
}
