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
      throw StateError('attachment_open_empty_path');
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
      throw StateError('attachment_open_failed');
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
        throw StateError('attachment_open_failed: $message');
      }
      throw StateError('attachment_open_failed');
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
