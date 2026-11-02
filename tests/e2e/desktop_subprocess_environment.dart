import 'dart:io';

/// Preserve an isolated test HOME while supplying the Windows OS environment
/// required by Winsock DNS and native child-process discovery. Never inherit
/// the operator's profile or unrelated credentials.
Map<String, String> desktopSubprocessEnvironment(
  Map<String, String> environment, {
  String? operatingSystem,
  Map<String, String>? parentEnvironment,
}) {
  final result = Map<String, String>.of(environment);
  if ((operatingSystem ?? Platform.operatingSystem) != 'windows') return result;
  final parent = parentEnvironment ?? Platform.environment;
  final systemRoot = parent['SystemRoot'] ?? parent['SYSTEMROOT'];
  if (systemRoot == null || systemRoot.trim().isEmpty) {
    throw StateError('Windows E2E subprocess requires SystemRoot.');
  }
  result['SystemRoot'] = systemRoot;
  for (final name in ['WINDIR', 'ComSpec']) {
    final value = parent[name];
    if (value != null && value.isNotEmpty) result[name] = value;
  }
  final home = result['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('Windows E2E subprocess requires an isolated HOME.');
  }
  for (final name in [
    'USERPROFILE',
    'TEMP',
    'TMP',
    'APPDATA',
    'LOCALAPPDATA',
  ]) {
    result[name] = home;
  }
  return result;
}
