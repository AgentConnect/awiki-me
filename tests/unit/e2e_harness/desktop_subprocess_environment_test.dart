import 'package:flutter_test/flutter_test.dart';
import '../../e2e/desktop_subprocess_environment.dart';

void main() {
  test('Windows supplies DNS environment without leaking operator profile', () {
    final result = desktopSubprocessEnvironment(
      {
        'HOME': r'D:\isolated',
        'AWIKI_CLI_WORKSPACE_HOME_DIR': r'D:\isolated\cli',
      },
      operatingSystem: 'windows',
      parentEnvironment: {
        'SystemRoot': r'C:\Windows',
        'WINDIR': r'C:\Windows',
        'ComSpec': r'C:\Windows\System32\cmd.exe',
        'USERPROFILE': r'C:\Users\operator',
        'API_TOKEN': 'must-not-inherit',
      },
    );
    expect(result['SystemRoot'], r'C:\Windows');
    expect(result['ComSpec'], r'C:\Windows\System32\cmd.exe');
    for (final name in [
      'USERPROFILE',
      'TEMP',
      'TMP',
      'APPDATA',
      'LOCALAPPDATA',
    ]) {
      expect(result[name], r'D:\isolated');
    }
    expect(result.containsKey('API_TOKEN'), isFalse);
  });
  test('Windows rejects missing OS or isolated profile prerequisites', () {
    expect(
      () => desktopSubprocessEnvironment(
        {'HOME': 'test'},
        operatingSystem: 'windows',
        parentEnvironment: {},
      ),
      throwsStateError,
    );
    expect(
      () => desktopSubprocessEnvironment(
        {},
        operatingSystem: 'windows',
        parentEnvironment: {'SystemRoot': r'C:\Windows'},
      ),
      throwsStateError,
    );
  });
  test('Unix environment remains explicitly scoped', () {
    final original = {'HOME': '/isolated', 'PATH': '/bin'};
    expect(
      desktopSubprocessEnvironment(
        original,
        operatingSystem: 'linux',
        parentEnvironment: {'TOKEN': 'not-inherited'},
      ),
      original,
    );
  });
}
