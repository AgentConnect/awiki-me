import 'package:awiki_me/l10n/app_localizations.dart';

import '../core/app_error_classifier.dart';

class AppMessage {
  const AppMessage._(this.id, {this.path, this.value, this.detail});

  final String id;
  final String? path;
  final String? value;
  final String? detail;

  factory AppMessage.profileUpdated() => const AppMessage._('profileUpdated');

  factory AppMessage.exportedTo(String path) =>
      AppMessage._('exportedTo', path: path);

  factory AppMessage.importSuccessSelectCredential() =>
      const AppMessage._('importSuccessSelectCredential');

  factory AppMessage.localCredentialsRefreshed(int count) =>
      AppMessage._('localCredentialsRefreshed', value: '$count');

  factory AppMessage.noLocalCredentialsFound() =>
      const AppMessage._('noLocalCredentialsFound');

  factory AppMessage.newMessageArrived() =>
      const AppMessage._('newMessageArrived');

  factory AppMessage.updateAlreadyLatest() =>
      const AppMessage._('updateAlreadyLatest');

  factory AppMessage.updateCheckFailed() =>
      const AppMessage._('updateCheckFailed');

  factory AppMessage.updateOpenReleaseNotesFailed() =>
      const AppMessage._('updateOpenReleaseNotesFailed');

  factory AppMessage.updateOpenDownloadFailed() =>
      const AppMessage._('updateOpenDownloadFailed');

  factory AppMessage.updateReadyToInstall() =>
      const AppMessage._('updateReadyToInstall');

  factory AppMessage.updatePermissionRequired() =>
      const AppMessage._('updatePermissionRequired');

  factory AppMessage.updateInstallFailed() =>
      const AppMessage._('updateInstallFailed');

  factory AppMessage.daemonUpgradeStarted() =>
      const AppMessage._('daemonUpgradeStarted');

  factory AppMessage.requestTimeoutRetry() =>
      const AppMessage._('requestTimeoutRetry');

  factory AppMessage.networkUnavailableRetry() =>
      const AppMessage._('networkUnavailableRetry');

  factory AppMessage.operationFailedRetry() =>
      const AppMessage._('operationFailedRetry');

  factory AppMessage.featureNotImplemented() =>
      const AppMessage._('featureNotImplemented');

  factory AppMessage.otpSent() => const AppMessage._('otpSent');

  factory AppMessage.activationEmailSent() =>
      const AppMessage._('activationEmailSent');

  factory AppMessage.emailLoginUnsupportedForRegisteredHandle() =>
      const AppMessage._('emailLoginUnsupportedForRegisteredHandle');

  factory AppMessage.emailNotActivatedClickLink() =>
      const AppMessage._('emailNotActivatedClickLink');

  factory AppMessage.handleAlreadyRegisteredImportCredential() =>
      const AppMessage._('handleAlreadyRegisteredImportCredential');

  factory AppMessage.registrationMethodUnavailable() =>
      const AppMessage._('registrationMethodUnavailable');

  factory AppMessage.sessionExpiredRelogin() =>
      const AppMessage._('sessionExpiredRelogin');

  factory AppMessage.didNotFoundOrRevoked() =>
      const AppMessage._('didNotFoundOrRevoked');

  factory AppMessage.localCredentialNotFound(String credentialName) =>
      AppMessage._('localCredentialNotFound', value: credentialName);

  factory AppMessage.setupIdentityScriptMissing() =>
      const AppMessage._('setupIdentityScriptMissing');

  factory AppMessage.deleteCredentialFailed(String credentialName) =>
      AppMessage._('deleteCredentialFailed', value: credentialName);

  factory AppMessage.noCredentialToExport() =>
      const AppMessage._('noCredentialToExport');

  factory AppMessage.credentialPackFailed() =>
      const AppMessage._('credentialPackFailed');

  factory AppMessage.localCredentialDirectoryMissing() =>
      const AppMessage._('localCredentialDirectoryMissing');

  factory AppMessage.exportUnsupportedOnPlatform() =>
      const AppMessage._('exportUnsupportedOnPlatform');

  factory AppMessage.importUnsupportedOnPlatform() =>
      const AppMessage._('importUnsupportedOnPlatform');

  factory AppMessage.currentCredentialIndexMissing() =>
      const AppMessage._('currentCredentialIndexMissing');

  factory AppMessage.currentCredentialDidInvalid() =>
      const AppMessage._('currentCredentialDidInvalid');

  factory AppMessage.zipMissingMetadata() =>
      const AppMessage._('zipMissingMetadata');

  factory AppMessage.zipCredentialIncomplete() =>
      const AppMessage._('zipCredentialIncomplete');

  factory AppMessage.invalidFileFormat(String path) =>
      AppMessage._('invalidFileFormat', path: path);

  factory AppMessage.phoneInvalidIntlExample() =>
      const AppMessage._('phoneInvalidIntlExample');

  factory AppMessage.phoneInvalidIntlOrCn() =>
      const AppMessage._('phoneInvalidIntlOrCn');

  factory AppMessage.handleInvalidPattern() =>
      const AppMessage._('handleInvalidPattern');

  factory AppMessage.didRegistrationPluginMissing(String authHint) =>
      AppMessage._('didRegistrationPluginMissing', value: authHint);

  factory AppMessage.didRegistrationRefreshUnsupported() =>
      const AppMessage._('didRegistrationRefreshUnsupported');

  factory AppMessage.e2eePluginMissing() =>
      const AppMessage._('e2eePluginMissing');

  factory AppMessage.documentPickerFailed() =>
      const AppMessage._('documentPickerFailed');

  factory AppMessage.linkOpenFailed([String? detail]) =>
      AppMessage._('linkOpenFailed', detail: detail);

  factory AppMessage.groupNameRequired() =>
      const AppMessage._('groupNameRequired');

  factory AppMessage.groupRecoveryCompleted() =>
      const AppMessage._('groupRecoveryCompleted');

  factory AppMessage.groupRecoveryPending(int count) =>
      AppMessage._('groupRecoveryPending', value: '$count');

  factory AppMessage.groupRecoveryBlocked(int count) =>
      AppMessage._('groupRecoveryBlocked', value: '$count');

  factory AppMessage.groupRecoveryStatusUnavailable() =>
      const AppMessage._('groupRecoveryStatusUnavailable');

  factory AppMessage.identityQueryRequired() =>
      const AppMessage._('identityQueryRequired');

  factory AppMessage.identityResolveFailed() =>
      const AppMessage._('identityResolveFailed');

  factory AppMessage.identityInvalidContact() =>
      const AppMessage._('identityInvalidContact');

  factory AppMessage.identityMissingDid() =>
      const AppMessage._('identityMissingDid');

  factory AppMessage.followContactAlreadyFollowing() =>
      const AppMessage._('followContactAlreadyFollowing');

  factory AppMessage.followContactSucceeded() =>
      const AppMessage._('followContactSucceeded');

  factory AppMessage.peerProfileThreadDeleted() =>
      const AppMessage._('peerProfileThreadDeleted');

  factory AppMessage.conversationRemovedFromRecents() =>
      const AppMessage._('conversationRemovedFromRecents');

  factory AppMessage.attachmentUnavailable() =>
      const AppMessage._('attachmentUnavailable');

  factory AppMessage.attachmentOpenFailed() =>
      const AppMessage._('attachmentOpenFailed');

  factory AppMessage.fromError(Object error) {
    final raw = normalizeAppError(error);
    if (raw.isEmpty) {
      return AppMessage.operationFailedRetry();
    }
    switch (classifyAppError(error)) {
      case AppErrorKind.timeout:
        return AppMessage.requestTimeoutRetry();
      case AppErrorKind.networkUnavailable:
        return AppMessage.networkUnavailableRetry();
      case AppErrorKind.authentication:
        return AppMessage.sessionExpiredRelogin();
      case AppErrorKind.didNotFoundOrRevoked:
        return AppMessage.didNotFoundOrRevoked();
      case AppErrorKind.other:
        break;
    }

    if (raw == 'email_not_activated' || raw == '邮箱尚未激活，请先点击邮件中的激活链接。') {
      return AppMessage.emailNotActivatedClickLink();
    }
    if (raw == 'email_login_unsupported_for_registered_handle' ||
        raw == '该 handle 已注册。邮箱当前仅支持新注册，请使用手机号验证码登录或导入身份凭证。') {
      return AppMessage.emailLoginUnsupportedForRegisteredHandle();
    }
    if (raw == 'handle_already_registered_import_credential') {
      return AppMessage.handleAlreadyRegisteredImportCredential();
    }
    if (raw == 'handle_recovery_unsupported' ||
        raw == 'registration_method_unavailable') {
      return AppMessage.registrationMethodUnavailable();
    }
    if (raw == 'session_expired' || raw == '登录状态已失效，请重新登录。') {
      return AppMessage.sessionExpiredRelogin();
    }
    if (raw.startsWith('本地未找到凭证：')) {
      return AppMessage.localCredentialNotFound(
        raw.substring('本地未找到凭证：'.length),
      );
    }
    if (raw == '当前版本不再支持旧版脚本凭证，请重新创建或导入新版 e1 DID 凭证。') {
      return AppMessage.setupIdentityScriptMissing();
    }
    if (raw.startsWith('删除凭证失败：')) {
      return AppMessage.deleteCredentialFailed(raw.substring('删除凭证失败：'.length));
    }
    if (raw == '当前没有已登录凭证可导出。') {
      return AppMessage.noCredentialToExport();
    }
    if (raw == '凭证打包失败，请稍后重试。') {
      return AppMessage.credentialPackFailed();
    }
    if (raw == '无法定位本地凭证目录。') {
      return AppMessage.localCredentialDirectoryMissing();
    }
    if (raw == '当前平台暂不支持导出身份凭证。') {
      return AppMessage.exportUnsupportedOnPlatform();
    }
    if (raw == '当前平台暂不支持导入身份凭证。') {
      return AppMessage.importUnsupportedOnPlatform();
    }
    if (raw == '未找到当前凭证的本地索引信息。') {
      return AppMessage.currentCredentialIndexMissing();
    }
    if (raw == '当前凭证的 DID 文档格式不正确。') {
      return AppMessage.currentCredentialDidInvalid();
    }
    if (raw == 'ZIP 包缺少必要的凭证元信息。') {
      return AppMessage.zipMissingMetadata();
    }
    if (raw == 'ZIP 包中的凭证内容不完整。') {
      return AppMessage.zipCredentialIncomplete();
    }
    if (raw.startsWith('文件格式不正确：')) {
      return AppMessage.invalidFileFormat(raw.substring('文件格式不正确：'.length));
    }
    if (raw == 'phone_invalid_intl_example' ||
        raw == '手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000') {
      return AppMessage.phoneInvalidIntlExample();
    }
    if (raw == 'phone_invalid_intl_or_cn' ||
        raw == '手机号格式不正确，请输入国际格式或中国大陆 11 位手机号') {
      return AppMessage.phoneInvalidIntlOrCn();
    }
    if (raw == 'handle_invalid_pattern' ||
        raw == 'handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线') {
      return AppMessage.handleInvalidPattern();
    }
    if (raw == 'identity_query_required') {
      return AppMessage.identityQueryRequired();
    }
    if (raw == 'identity_resolve_failed') {
      return AppMessage.identityResolveFailed();
    }
    if (raw == 'identity_invalid_contact') {
      return AppMessage.identityInvalidContact();
    }
    if (raw == 'identity_missing_did') {
      return AppMessage.identityMissingDid();
    }
    if (raw.startsWith('AWiki Me 当前未接入 DID 注册插件（') &&
        raw.endsWith('或接入原生插件后再在 App 内完成注册。')) {
      final start = raw.indexOf('（');
      final end = raw.indexOf('注册）');
      final authHint = start >= 0 && end > start
          ? raw.substring(start + 1, end)
          : '手机号+验证码';
      return AppMessage.didRegistrationPluginMissing(authHint);
    }
    if (raw == 'AWiki Me 当前未接入 DID 注册插件，无法自动刷新 token。') {
      return AppMessage.didRegistrationRefreshUnsupported();
    }
    if (raw == 'e2ee_plugin_missing' ||
        raw == 'AWiki Me 当前未启用 E2EE，请接入原生插件实现') {
      return AppMessage.e2eePluginMissing();
    }
    if (raw == 'attachment_picker_empty_result' ||
        raw == 'attachment_picker_failed') {
      return AppMessage.documentPickerFailed();
    }
    if (raw == 'attachment_save_failed') {
      return const AppMessage._('documentSaveFailed');
    }
    if (raw == 'attachment_open_empty_path' ||
        raw == 'attachment_open_failed' ||
        raw.startsWith('attachment_open_failed:')) {
      return AppMessage.attachmentOpenFailed();
    }
    if (raw == 'document_picker_failed') {
      return AppMessage.documentPickerFailed();
    }
    if (raw == '文件选择失败，请稍后重试。') {
      return AppMessage.documentPickerFailed();
    }
    if (raw == '文件保存失败，请稍后重试。') {
      return const AppMessage._('documentSaveFailed');
    }
    if (raw == '附件下载结果为空。') {
      return const AppMessage._('attachmentDownloadEmpty');
    }
    return AppMessage._('raw', detail: raw);
  }

  String resolve(AppLocalizations l10n) {
    switch (id) {
      case 'profileUpdated':
        return l10n.profileUpdated;
      case 'exportedTo':
        return l10n.exportedTo(path ?? '');
      case 'importSuccessSelectCredential':
        return l10n.importSuccessSelectCredential;
      case 'localCredentialsRefreshed':
        return l10n.localCredentialsRefreshed(value ?? '0');
      case 'noLocalCredentialsFound':
        return l10n.noLocalCredentialsFound;
      case 'newMessageArrived':
        return l10n.newMessageArrived;
      case 'updateAlreadyLatest':
        return l10n.updateAlreadyLatest;
      case 'updateCheckFailed':
        return l10n.updateCheckFailed;
      case 'updateOpenReleaseNotesFailed':
        return l10n.updateOpenReleaseNotesFailed;
      case 'updateOpenDownloadFailed':
        return l10n.updateOpenDownloadFailed;
      case 'updateReadyToInstall':
        return l10n.updateReadyToInstall;
      case 'updatePermissionRequired':
        return l10n.updatePermissionRequired;
      case 'updateInstallFailed':
        return l10n.updateInstallFailed;
      case 'daemonUpgradeStarted':
        return l10n.daemonUpgradeStarted;
      case 'requestTimeoutRetry':
        return l10n.requestTimeoutRetry;
      case 'networkUnavailableRetry':
        return l10n.networkUnavailableRetry;
      case 'operationFailedRetry':
        return l10n.operationFailedRetry;
      case 'featureNotImplemented':
        return l10n.featureNotImplemented;
      case 'otpSent':
        return l10n.otpSent;
      case 'activationEmailSent':
        return l10n.activationEmailSent;
      case 'emailLoginUnsupportedForRegisteredHandle':
        return l10n.emailLoginUnsupportedForRegisteredHandle;
      case 'emailNotActivatedClickLink':
        return l10n.emailNotActivatedClickLink;
      case 'handleAlreadyRegisteredImportCredential':
        return l10n.handleAlreadyRegisteredImportCredential;
      case 'registrationMethodUnavailable':
        return l10n.registrationMethodUnavailable;
      case 'sessionExpiredRelogin':
        return l10n.sessionExpiredRelogin;
      case 'didNotFoundOrRevoked':
        return l10n.didNotFoundOrRevoked;
      case 'localCredentialNotFound':
        return l10n.localCredentialNotFound(value ?? '');
      case 'setupIdentityScriptMissing':
        return l10n.setupIdentityScriptMissing;
      case 'deleteCredentialFailed':
        return l10n.deleteCredentialFailed(value ?? '');
      case 'noCredentialToExport':
        return l10n.noCredentialToExport;
      case 'credentialPackFailed':
        return l10n.credentialPackFailed;
      case 'localCredentialDirectoryMissing':
        return l10n.localCredentialDirectoryMissing;
      case 'exportUnsupportedOnPlatform':
        return l10n.exportUnsupportedOnPlatform;
      case 'importUnsupportedOnPlatform':
        return l10n.importUnsupportedOnPlatform;
      case 'currentCredentialIndexMissing':
        return l10n.currentCredentialIndexMissing;
      case 'currentCredentialDidInvalid':
        return l10n.currentCredentialDidInvalid;
      case 'zipMissingMetadata':
        return l10n.zipMissingMetadata;
      case 'zipCredentialIncomplete':
        return l10n.zipCredentialIncomplete;
      case 'invalidFileFormat':
        return l10n.invalidFileFormat(path ?? '');
      case 'phoneInvalidIntlExample':
        return l10n.phoneInvalidIntlExample;
      case 'phoneInvalidIntlOrCn':
        return l10n.phoneInvalidIntlOrCn;
      case 'handleInvalidPattern':
        return l10n.handleInvalidPattern;
      case 'didRegistrationPluginMissing':
        return l10n.didRegistrationPluginMissing(value ?? '');
      case 'didRegistrationRefreshUnsupported':
        return l10n.didRegistrationRefreshUnsupported;
      case 'e2eePluginMissing':
        return l10n.e2eePluginMissing;
      case 'documentPickerFailed':
        return l10n.documentPickerFailed;
      case 'documentSaveFailed':
        return l10n.documentSaveFailed;
      case 'attachmentDownloadEmpty':
        return l10n.attachmentDownloadEmpty;
      case 'linkOpenFailed':
        return detail == null || detail!.isEmpty
            ? l10n.linkOpenFailed
            : l10n.linkOpenFailedWithDetail(detail!);
      case 'groupNameRequired':
        return l10n.groupNameRequired;
      case 'groupRecoveryCompleted':
        return l10n.groupRecoveryCompleted;
      case 'groupRecoveryPending':
        return l10n.groupRecoveryPending(int.tryParse(value ?? '') ?? 0);
      case 'groupRecoveryBlocked':
        return l10n.groupRecoveryBlocked(int.tryParse(value ?? '') ?? 0);
      case 'groupRecoveryStatusUnavailable':
        return l10n.groupRecoveryStatusUnavailable;
      case 'identityQueryRequired':
        return l10n.identityQueryRequired;
      case 'identityResolveFailed':
        return l10n.identityResolveFailed;
      case 'identityInvalidContact':
        return l10n.identityInvalidContact;
      case 'identityMissingDid':
        return l10n.identityMissingDid;
      case 'followContactAlreadyFollowing':
        return l10n.followContactAlreadyFollowing;
      case 'followContactSucceeded':
        return l10n.followContactSucceeded;
      case 'peerProfileThreadDeleted':
        return l10n.peerProfileThreadDeleted;
      case 'conversationRemovedFromRecents':
        return l10n.conversationRemovedFromRecents;
      case 'attachmentUnavailable':
        return l10n.attachmentUnavailable;
      case 'attachmentOpenFailed':
        return l10n.attachmentOpenFailed;
      case 'raw':
        return detail ?? l10n.operationFailedRetry;
      default:
        return l10n.operationFailedRetry;
    }
  }

  String resolveForFallback() {
    switch (id) {
      case 'newMessageArrived':
        return 'You received a new message';
      case 'requestTimeoutRetry':
        return 'The request timed out. Please check your network and try again.';
      case 'daemonUpgradeStarted':
        return 'Daemon upgrade started.';
      case 'networkUnavailableRetry':
        return 'Network connection is temporarily unavailable. Please check your network and try again.';
      case 'operationFailedRetry':
        return 'The operation failed. Please try again later.';
      case 'featureNotImplemented':
        return 'This feature is not available yet.';
      case 'otpSent':
        return 'Verification code sent. Please check your messages.';
      case 'activationEmailSent':
        return 'Activation email sent. Please check your inbox.';
      case 'emailLoginUnsupportedForRegisteredHandle':
        return 'This handle is already registered. Email currently supports new registration only.';
      case 'handleAlreadyRegisteredImportCredential':
        return 'This handle already exists. Import its identity credential or contact the server administrator.';
      case 'registrationMethodUnavailable':
        return 'This server does not support the selected registration method.';
      case 'didNotFoundOrRevoked':
        return 'This DID does not exist or has been revoked. Check the DID and try again, or switch to a valid identity.';
      case 'conversationRemovedFromRecents':
        return 'Conversation removed from recents.';
      case 'attachmentUnavailable':
        return 'The attachment has expired or is not cached on this device. Ask the sender to send it again.';
      case 'attachmentOpenFailed':
        return 'The attachment cannot be opened. Try again later or save it before opening.';
      case 'raw':
        return detail ?? 'The operation failed. Please try again later.';
      default:
        return detail ?? 'The operation failed. Please try again later.';
    }
  }

  @override
  bool operator ==(Object other) {
    return other is AppMessage &&
        other.id == id &&
        other.path == path &&
        other.value == value &&
        other.detail == detail;
  }

  @override
  int get hashCode => Object.hash(id, path, value, detail);
}
