import 'dart:io';
import 'package:path/path.dart' as p;

/// Dart's Windows process lookup does not expand the Flutter/Dart batch entry
/// names. Keep argv structured and name the batch file explicitly.
String desktopToolExecutable(
  String executable, {
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  if ((operatingSystem ?? Platform.operatingSystem) != 'windows') {
    return executable;
  }
  if (executable == 'python3' || executable == 'python') {
    final python = (environment ?? Platform.environment)['AWIKI_E2E_PYTHON_BIN']
        ?.trim();
    if (python == null ||
        !p.windows.isAbsolute(python) ||
        !python.toLowerCase().endsWith('.exe') ||
        python
            .replaceAll('\\', '/')
            .toLowerCase()
            .contains('/microsoft/windowsapps/')) {
      throw StateError(
        'AWIKI_E2E_PYTHON_BIN must select a native Python executable, outside Windows Store aliases.',
      );
    }
    return python;
  }
  final name = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
  return name == 'flutter' || name == 'dart' ? '$executable.bat' : executable;
}
