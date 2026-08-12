import 'daemon_upgrade_failure_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daemon upgrade failure keeps the App-facing contract', () {
    verifyDaemonUpgradeFailureContract();
  });
}
