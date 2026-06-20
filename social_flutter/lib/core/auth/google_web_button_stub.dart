// Non-web stub for [GoogleWebButton]. Never displayed on mobile/desktop —
// those platforms use the interactive authenticate() flow instead.
import 'package:flutter/widgets.dart';

class GoogleWebButton extends StatelessWidget {
  final void Function(String idToken) onIdToken;
  final void Function(Object error)? onError;
  const GoogleWebButton({super.key, required this.onIdToken, this.onError});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
