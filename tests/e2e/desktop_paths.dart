import 'dart:io';
import 'package:path/path.dart' as p;

String normalizeDesktopPath(String path) =>
    p.normalize(path).replaceAll('\\', '/');
bool desktopPathIsWithin(String parent, String child) {
  var root = normalizeDesktopPath(parent), target = normalizeDesktopPath(child);
  if (Platform.isWindows) {
    root = root.toLowerCase();
    target = target.toLowerCase();
  }
  return target.startsWith('$root/');
}

String resolveDesktopConfigPath(Directory root, String path) {
  final value = path.trim();
  if (value.isEmpty || value.startsWith('/') || p.windows.isAbsolute(value))
    return value;
  return '${root.path}/$value';
}
