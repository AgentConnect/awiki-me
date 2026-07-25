import '../../domain/services/remote_push_client.dart';
import 'remote_push_client_factory_stub.dart'
    if (dart.library.io) 'remote_push_client_factory_io.dart';

RemotePushClient buildRemotePushClient() => buildPlatformRemotePushClient();
