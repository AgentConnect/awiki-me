import 'dart:io';

import 'package:path/path.dart' as p;

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
  p.Context? pathContext,
}) {
  final trimmed = root.trim();
  final context =
      pathContext ??
      awikiPathContextFor(<String?>[
        trimmed,
        currentDirectory,
        homeDirectory,
        temporaryDirectory,
      ]);
  if (trimmed.isEmpty || context.isAbsolute(trimmed)) {
    return trimmed.isEmpty ? trimmed : context.normalize(trimmed);
  }
  final expandedHome = _expandHomeRelativePath(trimmed, homeDirectory, context);
  if (expandedHome != null) return expandedHome;
  final cwd = (currentDirectory ?? Directory.current.path).trim();
  if (_canAnchorRelativeE2eRootToCurrentDirectory(cwd)) {
    return context.normalize(context.join(cwd, trimmed));
  }
  final appSupportFallback = _appSupportFallbackRoot(
    homeDirectory ?? Platform.environment['HOME'],
    isMacOS: isMacOS ?? Platform.isMacOS,
    pathContext: context,
  );
  if (appSupportFallback != null) {
    return context.normalize(context.join(appSupportFallback, trimmed));
  }
  final temp = (temporaryDirectory ?? Directory.systemTemp.path).trim();
  return context.normalize(context.join(temp, 'ai.awiki.awikime', trimmed));
}

String? explicitAwikiAppStateRoot(String? appStateRoot) {
  final explicit = appStateRoot?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  return awikiE2eAppStateRoot();
}

String? _expandHomeRelativePath(
  String path,
  String? homeDirectory,
  p.Context pathContext,
) {
  if (path != '~' && !path.startsWith('~/') && !path.startsWith('~\\')) {
    return null;
  }
  final home = homeDirectory?.trim() ?? Platform.environment['HOME']?.trim();
  if (home == null || home.isEmpty) return null;
  return path == '~'
      ? pathContext.normalize(home)
      : pathContext.normalize(pathContext.join(home, path.substring(2)));
}

bool _canAnchorRelativeE2eRootToCurrentDirectory(String currentDirectory) {
  if (currentDirectory.isEmpty ||
      currentDirectory == '/' ||
      currentDirectory == '\\') {
    return false;
  }
  final normalized = currentDirectory.replaceAll('\\', '/').toLowerCase();
  return !normalized.contains('.app/contents');
}

String? _appSupportFallbackRoot(
  String? homeDirectory, {
  required bool isMacOS,
  required p.Context pathContext,
}) {
  final home = homeDirectory?.trim();
  if (home == null || home.isEmpty) return null;
  return isMacOS
      ? pathContext.join(
          home,
          'Library',
          'Application Support',
          'ai.awiki.awikime',
        )
      : pathContext.join(home, '.awiki-me');
}

p.Context awikiPathContextFor(
  Iterable<String?> candidates, {
  p.Context? fallback,
}) {
  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value == null || value.isEmpty) {
      continue;
    }
    final isWindowsPath =
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
        value.startsWith(r'\\') ||
        value.startsWith('//') ||
        value.contains('\\');
    if (isWindowsPath) {
      return p.windows;
    }
    if (p.posix.isAbsolute(value)) {
      return p.posix;
    }
  }
  return fallback ?? p.context;
}

String joinAwikiPath(String root, Iterable<String> parts) {
  final context = awikiPathContextFor(<String?>[root]);
  return context.normalize(context.joinAll(<String>[root, ...parts]));
}
