import '../../domain/services/remote_push_client.dart';
import 'noop_remote_push_client.dart';

RemotePushClient buildPlatformRemotePushClient() {
  return const NoopRemotePushClient();
}
