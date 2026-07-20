// [INPUT]: A Group DID selected by the product and an explicit retry intent.
// [OUTPUT]: Secret-free local-device group encryption readiness.
// [POS]: AWiki Me boundary to IM Core; MLS operations and private state never cross it.

import '../../domain/entities/group_encryption_status.dart';

abstract interface class GroupEncryptionCorePort {
  Future<GroupEncryptionStatus> status(String groupDid);

  Future<GroupEncryptionStatus> retry(String groupDid);
}
