// test/support/follow_counts.dart — what a follow write answers, for fakes
// whose test is not about the numbers.

import 'package:ntripi/shared/models/follow.dart';

/// Both accounts' counts, all zero.
const kZeroCounts = FollowCounts(
  me: UserCounts(followersCount: 0, followingCount: 0),
  them: UserCounts(followersCount: 0, followingCount: 0),
);
