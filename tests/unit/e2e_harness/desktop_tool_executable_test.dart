import 'package:flutter_test/flutter_test.dart';
import '../../e2e/desktop_tool_executable.dart';

void main() {
  test(
    'Windows Python uses an explicit native interpreter and refuses Store aliases',
    () {
      expect(
        desktopToolExecutable(
          'python3',
          operatingSystem: 'windows',
          environment: {'AWIKI_E2E_PYTHON_BIN': r'C:\Native Python\python.exe'},
        ),
        r'C:\Native Python\python.exe',
      );
      for (final value in [
        '',
        'python3',
        r'C:\Users\fixture\AppData\Local\Microsoft\WindowsApps\python.exe',
      ]) {
        expect(
          () => desktopToolExecutable(
            'python3',
            operatingSystem: 'windows',
            environment: {'AWIKI_E2E_PYTHON_BIN': value},
          ),
          throwsStateError,
        );
      }
      expect(
        desktopToolExecutable('python3', operatingSystem: 'linux'),
        'python3',
      );
    },
  );
  test('Windows Flutter/Dart lookup selects native batch entrypoints', () {
    expect(
      desktopToolExecutable('flutter', operatingSystem: 'windows'),
      'flutter.bat',
    );
    expect(
      desktopToolExecutable('dart', operatingSystem: 'windows'),
      'dart.bat',
    );
    expect(
      desktopToolExecutable(
        r'C:\Flutter SDK\bin\flutter',
        operatingSystem: 'windows',
      ),
      r'C:\Flutter SDK\bin\flutter.bat',
    );
    for (final executable in ['flutter.bat', 'dart.exe', 'node', 'cargo']) {
      expect(
        desktopToolExecutable(executable, operatingSystem: 'windows'),
        executable,
      );
    }
    expect(
      desktopToolExecutable('flutter', operatingSystem: 'linux'),
      'flutter',
    );
  });
}
