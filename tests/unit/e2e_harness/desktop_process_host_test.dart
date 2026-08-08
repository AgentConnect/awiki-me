import 'package:flutter_test/flutter_test.dart';

import '../../e2e/desktop_process_host.dart';

void main() {
  test('macOS foreground CLI keeps argv structured', () {
    const host = DesktopProcessHost(DesktopHostPlatform.macos);

    expect(
      host.foregroundArguments('/opt/awiki cli', <String>['a b', "c'd"]),
      <String>['-q', '/dev/null', '/opt/awiki cli', 'a b', "c'd"],
    );
  });

  test('Linux foreground CLI quotes every shell word for script command', () {
    const host = DesktopProcessHost(DesktopHostPlatform.linux);

    expect(
      host.foregroundArguments('/opt/awiki cli', <String>['a b', "c'd"]),
      <String>[
        '-q',
        '-e',
        '-c',
        "'/opt/awiki cli' 'a b' 'c'\"'\"'d'",
        '/dev/null',
      ],
    );
  });

  test('foreground CLI rejects an ambiguous executable', () {
    const host = DesktopProcessHost(DesktopHostPlatform.linux);

    expect(
      () => host.foregroundArguments(' /opt/awiki', const <String>[]),
      throwsArgumentError,
    );
  });
}
