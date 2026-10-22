// test/support/held_claim.dart — an edit claim this device holds, without the
// network or the heartbeat.
//
// Every trip save carries the claim, so a test of a save needs one. Override
// with `editLockProvider.overrideWith2(HeldClaim.new)`; subclass it to watch
// what the screen does with the claim.

import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';

/// The token every save in these tests sends as `X-Edit-Lock`.
const kHeldClaimToken = 'lock-token';

class HeldClaim extends EditLockNotifier {
  HeldClaim(super.arg);

  @override
  EditSession build() {
    // super.build registers the real teardown, which cancels the detach grace
    // timer when the container goes.
    super.build();
    return const EditSession(token: kHeldClaimToken);
  }
}
