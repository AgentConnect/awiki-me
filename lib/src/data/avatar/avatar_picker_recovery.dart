import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'avatar_picker_marker.dart';

/// Android's picker may outlive the process. Only an explicit owner marker can
/// reconnect the result to this feature; recovery never uploads automatically.
class AvatarPickerRecovery {
  AvatarPickerRecovery._();
  static final instance = AvatarPickerRecovery._();
  Future<void>? _initialization;
  XFile? _recovered;
  String? _owner;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String _hash(String owner) => sha256.convert(utf8.encode(owner)).toString();

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!_android) return;
    try {
      final marker = await readAvatarPickerMarker();
      final result = await ImagePicker().retrieveLostData();
      if (marker == null) return;
      final token = marker['token'];
      if (token is String) await clearAvatarPickerMarker(token);
      final created = marker['created'];
      final owner = marker['owner'];
      if (created is! int ||
          owner is! String ||
          DateTime.now().millisecondsSinceEpoch - created >
              const Duration(days: 1).inMilliseconds ||
          result.files?.length != 1) {
        return;
      }
      _owner = owner;
      _recovered = result.files!.single;
    } catch (_) {
      /* Failed/cancelled picks do not affect startup. */
    }
  }

  Future<String?> begin(String owner) async {
    if (!_android) return null;
    await initialize();
    final token = '${DateTime.now().microsecondsSinceEpoch}-${_hash(owner)}';
    await writeAvatarPickerMarker({
      'owner': _hash(owner),
      'token': token,
      'created': DateTime.now().millisecondsSinceEpoch,
    });
    return token;
  }

  Future<void> finish(String? token) async {
    if (token != null) await clearAvatarPickerMarker(token);
  }

  Future<XFile?> takeForOwner(String owner) async {
    await initialize();
    final file = _owner == _hash(owner) ? _recovered : null;
    _owner = null;
    _recovered = null;
    return file;
  }
}
