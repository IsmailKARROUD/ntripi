// test_driver/integration_test.dart — the host side of `flutter drive`, which
// runs an integration test as a profile build on a phone (real timings).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
