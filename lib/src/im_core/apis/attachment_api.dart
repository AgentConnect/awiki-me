import '../models/common.dart';
import '../models/message_models.dart';
import 'message_api.dart';

abstract class ImAttachmentApi {
  Future<ImSendResultDto> sendAttachment(ImSendMessageRequest request);
  Future<ImAttachmentDownloadResultDto> download(
    ImAttachmentDownloadRequest request,
  );
  Stream<ImAttachmentTransferEventDto> transferEvents(String transferId);
}

class ImAttachmentDownloadRequest {
  const ImAttachmentDownloadRequest({
    required this.thread,
    required this.messageId,
    this.attachmentId,
    required this.outputPath,
  });

  final ImThreadRef thread;
  final String messageId;
  final String? attachmentId;
  final String outputPath;
}

class ImAttachmentDownloadResultDto {
  const ImAttachmentDownloadResultDto({
    required this.transferId,
    required this.outputPath,
    required this.attachment,
  });

  final String transferId;
  final String outputPath;
  final ImAttachmentDto attachment;
}

class ImAttachmentTransferEventDto {
  const ImAttachmentTransferEventDto({
    required this.transferId,
    required this.state,
    this.bytesTransferred,
    this.totalBytes,
    this.errorCode,
  });

  final String transferId;
  final String state;
  final int? bytesTransferred;
  final int? totalBytes;
  final String? errorCode;
}
