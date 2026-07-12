import 'dart:io';

const bool _awikiE2eEnabled = bool.fromEnvironment('AWIKI_E2E');
const String _awikiE2eAppStateRoot = String.fromEnvironment(
  'AWIKI_E2E_APP_STATE_ROOT',
);

bool awikiE2eEnabledForBuild() => _awikiE2eEnabled;

String? awikiE2eAppStateRoot() {
  if (!_awikiE2eEnabled) return null;
  final root = _awikiE2eAppStateRoot.trim();
  return root.isEmpty ? null : normalizeAwikiE2eAppStateRootForLaunch(root);
}

String normalizeAwikiE2eAppStateRootForLaunch(
  String root, {
  String? currentDirectory,
  String? homeDirectory,
  bool? isMacOS,
  String? temporaryDirectory,
}) {
  final trimmed = root.trim();
  if (trimmed.isEmpty || _isAbsolutePath(trimmed)) return trimmed;
  final expandedHome = _expandHomeRelativePath(trimmed, homeDirectory);
  if (expandedHome != null) return expandedHome;
  final cwd = (currentDirectory ?? Directory.current.path).trim();
  if (_canAnchorRelativeE2eRootToCurrentDirectory(cwd)) {
    return _joinAll(<String>[cwd, trimmed]);
  }
  final appSupportFallback = _appSupportFallbackRoot(
    homeDirectory ?? Platform.environment['HOME'],
    isMacOS: isMacOS ?? Platform.isMacOS,
  );
  if (appSupportFallback != null) {
    return _joinAll(<String>[appSupportFallback, trimmed]);
  }
  final temp = (temporaryDirectory ?? Directory.systemTemp.path).trim();
  return _joinAll(<String>[temp, 'ai.awiki.awikime', trimmed]);
}

String? explicitAwikiAppStateRoot(String? appStateRoot) {
  final explicit = appStateRoot?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  return awikiE2eAppStateRoot();
}

bool _isAbsolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

String? _expandHomeRelativePath(String path, String? homeDirectory) {
  if (path != '~' && !path.startsWith('~/')) return null;
  final home = homeDirectory?.trim() ?? Platform.environment['HOME']?.trim();
  if (home == null || home.isEmpty) return null;
  return path == '~' ? home : _joinAll(<String>[home, path.substring(2)]);
}

bool _canAnchorRelativeE2eRootToCurrentDirectory(String currentDirectory) {
  if (currentDirectory.isEmpty ||
      currentDirectory == '/' ||
      currentDirectory == r'\') {
    return false;
  }
  return !currentDirectory.toLowerCase().contains('.app/contents');
}

String? _appSupportFallbackRoot(
  String? homeDirectory, {
  required bool isMacOS,
}) {
  final home = homeDirectory?.trim();
  if (home == null || home.isEmpty) return null;
  return isMacOS
      ? _joinAll(<String>[
          home,
          'Library',
          'Application Support',
          'ai.awiki.awikime',
        ])
      : _joinAll(<String>[home, '.awiki-me']);
}

String _joinAll(List<String> parts) {
  final normalized = parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) => part.replaceAll(RegExp(r'/+$'), ''))
      .toList();
  if (normalized.isEmpty) return '';
  return <String>[
    normalized.first,
    ...normalized.skip(1).map((part) => part.replaceAll(RegExp(r'^/+'), '')),
  ].join('/');
}
