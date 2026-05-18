import '../models/common.dart';
import '../models/group_models.dart';
import 'outbox_api.dart';
import 'message_api.dart';

abstract class ImDirectSecureApi {
  Future<ImDirectSecureStatusDto> status({String? peerDidOrHandle});
  Future<ImDirectSecureInitResultDto> init(ImDirectSecurePeerRequest request);
  Future<ImDirectSecureRepairResultDto> repair(
    ImDirectSecurePeerRequest request,
  );
  Future<ImPage<ImOutboxItemDto>> failed(ImListOutboxRequest request);
  Future<ImSendResultDto> retry(String outboxId);
  Future<void> drop(String outboxId);
}

class ImDirectSecurePeerRequest {
  const ImDirectSecurePeerRequest({required this.peerDidOrHandle});

  final String peerDidOrHandle;
}

class ImDirectSecureStatusDto {
  const ImDirectSecureStatusDto({
    this.peerDid,
    required this.state,
    required this.queuedOutboxCount,
    required this.failedOutboxCount,
    this.repairHint,
  });

  final String? peerDid;
  final String state;
  final int queuedOutboxCount;
  final int failedOutboxCount;
  final String? repairHint;
}

class ImDirectSecureInitResultDto {
  const ImDirectSecureInitResultDto({required this.status});

  final ImDirectSecureStatusDto status;
}

class ImDirectSecureRepairResultDto {
  const ImDirectSecureRepairResultDto({required this.status});

  final ImDirectSecureStatusDto status;
}

abstract class ImGroupE2eeApi {
  Future<ImGroupE2eeStatusDto> status(ImGroupE2eeStatusRequest request);
  Future<ImGroupE2eeKeyPackageResultDto> publishKeyPackage(
    ImGroupE2eePublishKeyPackageRequest request,
  );
  Future<ImPage<ImGroupE2eeNoticeDto>> pending(
    ImGroupE2eeNoticeRequest request,
  );
  Future<ImGroupE2eeRepairResultDto> repair(ImGroupE2eeNoticeRequest request);
  Future<ImGroupE2eeMutationResultDto> recoverMember(
    ImGroupE2eeMemberRequest request,
  );
  Future<ImGroupE2eeMutationResultDto> processLeaveRequest(
    ImGroupE2eeProcessLeaveRequest request,
  );
  Future<ImGroupE2eeMutationResultDto> updateKey(
    ImGroupE2eeMemberRequest request,
  );
  Future<ImGroupE2eeMutationResultDto> rejoin(ImGroupE2eeRejoinRequest request);
}

class ImGroupE2eeStatusRequest {
  const ImGroupE2eeStatusRequest({this.groupId});

  final String? groupId;
}

class ImGroupE2eeStatusDto {
  const ImGroupE2eeStatusDto({this.groupId, required this.state});

  final String? groupId;
  final String state;
}

class ImGroupE2eePublishKeyPackageRequest {
  const ImGroupE2eePublishKeyPackageRequest({
    this.groupId,
    this.deviceId = 'default',
    this.purpose = 'normal',
  });

  final String? groupId;
  final String deviceId;
  final String purpose;
}

class ImGroupE2eeKeyPackageResultDto {
  const ImGroupE2eeKeyPackageResultDto({required this.packageId});

  final String packageId;
}

class ImGroupE2eeNoticeRequest {
  const ImGroupE2eeNoticeRequest({this.groupId});

  final String? groupId;
}

class ImGroupE2eeNoticeDto {
  const ImGroupE2eeNoticeDto({required this.noticeId, this.groupId});

  final String noticeId;
  final String? groupId;
}

class ImGroupE2eeRepairResultDto {
  const ImGroupE2eeRepairResultDto({required this.repairedCount});

  final int repairedCount;
}

class ImGroupE2eeMemberRequest {
  const ImGroupE2eeMemberRequest({
    required this.groupId,
    required this.memberDidOrHandle,
    this.deviceId = 'default',
  });

  final String groupId;
  final String memberDidOrHandle;
  final String deviceId;
}

class ImGroupE2eeProcessLeaveRequest {
  const ImGroupE2eeProcessLeaveRequest({
    required this.groupId,
    required this.memberDidOrHandle,
    this.leaveRequestId,
    this.reason,
  });

  final String groupId;
  final String memberDidOrHandle;
  final String? leaveRequestId;
  final String? reason;
}

class ImGroupE2eeRejoinRequest {
  const ImGroupE2eeRejoinRequest({
    required this.groupId,
    required this.memberDidOrHandle,
    this.role = 'member',
  });

  final String groupId;
  final String memberDidOrHandle;
  final String role;
}

class ImGroupE2eeMutationResultDto {
  const ImGroupE2eeMutationResultDto({required this.group});

  final ImGroupDto group;
}

abstract class ImMigrationApi {
  Future<ImMigrationPlanDto> plan(ImMigrationPlanRequest request);
  Future<ImMigrationResultDto> run(ImMigrationRunRequest request);
  Future<ImSyncStateDto> syncState();
  Future<ImSyncRepairResultDto> repairSync(ImSyncRepairRequest request);
  Future<ImExportResultDto> exportStore(ImExportStoreRequest request);
  Future<ImImportResultDto> importStore(ImImportStoreRequest request);
}

class ImMigrationPlanRequest {
  const ImMigrationPlanRequest({this.ownerDid, this.dryRun = true});

  final String? ownerDid;
  final bool dryRun;
}

class ImMigrationPlanDto {
  const ImMigrationPlanDto({required this.itemCount, required this.canRun});

  final int itemCount;
  final bool canRun;
}

class ImMigrationRunRequest {
  const ImMigrationRunRequest({this.ownerDid, this.dryRun = true});

  final String? ownerDid;
  final bool dryRun;
}

class ImMigrationResultDto {
  const ImMigrationResultDto({required this.migratedCount});

  final int migratedCount;
}

class ImSyncStateDto {
  const ImSyncStateDto({required this.checkpoint});

  final String checkpoint;
}

class ImSyncRepairRequest {
  const ImSyncRepairRequest({this.threadId});

  final String? threadId;
}

class ImSyncRepairResultDto {
  const ImSyncRepairResultDto({required this.repairedCount});

  final int repairedCount;
}

class ImExportStoreRequest {
  const ImExportStoreRequest({required this.outputPath});

  final String outputPath;
}

class ImExportResultDto {
  const ImExportResultDto({required this.outputPath, required this.itemCount});

  final String outputPath;
  final int itemCount;
}

class ImImportStoreRequest {
  const ImImportStoreRequest({required this.inputPath, this.dryRun = true});

  final String inputPath;
  final bool dryRun;
}

class ImImportResultDto {
  const ImImportResultDto({required this.importedCount});

  final int importedCount;
}

abstract class ImAdvancedAttachmentApi {
  Future<ImAttachmentUploadSessionDto> createUploadSession(
    ImAttachmentUploadSessionRequest request,
  );
  Future<ImAttachmentTransferResultDto> resumeTransfer(String transferId);
  Future<void> cancelTransfer(String transferId);
}

class ImAttachmentUploadSessionRequest {
  const ImAttachmentUploadSessionRequest({
    required this.fileName,
    this.sizeBytes,
  });

  final String fileName;
  final int? sizeBytes;
}

class ImAttachmentUploadSessionDto {
  const ImAttachmentUploadSessionDto({required this.transferId});

  final String transferId;
}

class ImAttachmentTransferResultDto {
  const ImAttachmentTransferResultDto({
    required this.transferId,
    required this.state,
  });

  final String transferId;
  final String state;
}
