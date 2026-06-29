import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AttachmentOpenService {
  AttachmentOpenService({
    MethodChannel? channel,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launchUrl,
    bool Function()? isAndroid,
  }) : _channel =
           channel ?? const MethodChannel('ai.awiki.awikime/attachment_viewer'),
       _launchUrl = launchUrl ?? launchAttachmentUrl,
       _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final MethodChannel _channel;
  final Future<bool> Function(Uri uri, {LaunchMode mode}) _launchUrl;
  final bool Function() _isAndroid;

  Future<void> open(String pathOrUri) async {
    final value = pathOrUri.trim();
    if (value.isEmpty) {
      throw StateError('附件路径为空，无法打开。');
    }
    if (_isAndroid()) {
      await _openAndroid(value);
      return;
    }
    final uri = _attachmentUri(value);
    final launched = await _launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('无法使用本机应用打开附件：$value');
    }
  }

  Future<void> _openAndroid(String pathOrUri) async {
    try {
      await _channel.invokeMethod<void>('openAttachment', <String, Object?>{
        'path': pathOrUri,
      });
    } on PlatformException catch (error) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        throw StateError(message);
      }
      throw StateError('无法使用本机应用打开附件：$pathOrUri');
    }
  }

  Uri _attachmentUri(String pathOrUri) {
    final parsed = Uri.tryParse(pathOrUri);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    return Uri.file(pathOrUri);
  }
}

Future<bool> launchAttachmentUrl(
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) {
  return launchUrl(uri, mode: mode);
}
