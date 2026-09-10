import 'package:flutter_test/flutter_test.dart';
import '../../e2e/runner.dart';

void main() {
  test('two-App grant alias selects two-App execution, never App plus CLI', () {
    expect(
      DesktopE2eCase.parse('multi-device-app-pair-later-admin-grant'),
      DesktopE2eCase.multiDeviceAppPair,
    );
    expect(DesktopE2eCase.parse('root-transfer'), DesktopE2eCase.rootTransfer);
    expect(
      DesktopE2eCase.multiDeviceAppPair.caseIds,
      contains('ROOT-TRANSFER-APP-PAIR-E2E-001'),
    );
  });
}
