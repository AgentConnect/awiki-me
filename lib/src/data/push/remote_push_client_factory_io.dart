import 'dart:io';

import '../../domain/services/remote_push_client.dart';
import 'aliyun_emas_remote_push_client.dart';
import 'noop_remote_push_client.dart';

RemotePushClient buildPlatformRemotePushClient() {
  if (!Platform.isAndroid) {
    return const NoopRemotePushClient();
  }
  return AliyunEmasRemotePushClient();
}
