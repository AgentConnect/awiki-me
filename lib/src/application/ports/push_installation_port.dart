import '../../domain/services/remote_push_client.dart';
import '../models/push_installation.dart';

abstract interface class PushInstallationPort {
  Future<PushInstallation> upsert(RemotePushRegistration registration);

  Future<PushInstallation> disable(String installationId);
}
