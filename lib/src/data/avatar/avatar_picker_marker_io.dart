import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _marker() async => File(
  '${(await getApplicationCacheDirectory()).path}/avatar-picker-owner.json',
);
Future<void> writeAvatarPickerMarker(Map<String, Object?> marker) async {
  final file = await _marker();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.part');
  await temporary.writeAsString(jsonEncode(marker), flush: true);
  await temporary.rename(file.path);
}

Future<Map<String, Object?>?> readAvatarPickerMarker() async {
  try {
    final file = await _marker();
    if (await file.length() > 2048) return null;
    return (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

Future<void> clearAvatarPickerMarker(String token) async {
  final current = await readAvatarPickerMarker();
  if (current?['token'] == token) {
    try {
      await (await _marker()).delete();
    } catch (_) {}
  }
}
