import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AppMessage {
  const AppMessage._(
    this.id, {
    this.path,
    this.value,
    this.detail,
  });

  final String id;
  final String? path;
  final String? value;
  final String? detail;

  factory AppMessage.profileUpdated() => const AppMessage._('profileUpdated');

  factory AppMessage.exportedTo(String path) =>
      AppMessage._('exportedTo', path: path);

  factory AppMessage.importSuccessSelectCredential() =>
      const AppMessage._('importSuccessSelectCredential');

  factory AppMessage.newMessageArrived() =>
      const AppMessage._('newMessageArrived');

  factory AppMessage.requestTimeoutRetry() =>
      const AppMessage._('requestTimeoutRetry');

  factory AppMessage.operationFailedRetry() =>
      const AppMessage._('operationFailedRetry');

  factory AppMessage.emailNotActivatedClickLink() =>
      const AppMessage._('emailNotActivatedClickLink');

  factory AppMessage.sessionExpiredRelogin() =>
      const AppMessage._('sessionExpiredRelogin');

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

  factory AppMessage.localCredentialIndexInvalid() =>
      const AppMessage._('localCredentialIndexInvalid');

  factory AppMessage.localCredentialIndexMissingCredentials() =>
      const AppMessage._('localCredentialIndexMissingCredentials');

  factory AppMessage.credentialIndexEntryInvalid(String key) =>
      AppMessage._('credentialIndexEntryInvalid', value: key);

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

  factory AppMessage.fromError(Object error) {
    final raw = _normalize(error);
    if (raw.isEmpty) {
      return AppMessage.operationFailedRetry();
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return AppMessage.requestTimeoutRetry();
    }

    if (raw == '邮箱尚未激活，请先点击邮件中的激活链接。') {
      return AppMessage.emailNotActivatedClickLink();
    }
    if (raw == '登录状态已失效，请重新登录。') {
      return AppMessage.sessionExpiredRelogin();
    }
    if (raw.startsWith('本地未找到凭证：')) {
      return AppMessage.localCredentialNotFound(
          raw.substring('本地未找到凭证：'.length));
    }
    if (raw ==
        '当前仓库未内置 setup_identity.py，请通过 AWIKI_SETUP_IDENTITY_SCRIPT 显式配置脚本路径后再删除凭证。') {
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
    if (raw == '本地凭证索引格式不正确。') {
      return AppMessage.localCredentialIndexInvalid();
    }
    if (raw == '本地凭证索引缺少 credentials。') {
      return AppMessage.localCredentialIndexMissingCredentials();
    }
    if (raw.startsWith('凭证索引项格式不正确：')) {
      return AppMessage.credentialIndexEntryInvalid(
        raw.substring('凭证索引项格式不正确：'.length),
      );
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
    if (raw == '手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000') {
      return AppMessage.phoneInvalidIntlExample();
    }
    if (raw == '手机号格式不正确，请输入国际格式或中国大陆 11 位手机号') {
      return AppMessage.phoneInvalidIntlOrCn();
    }
    if (raw == 'handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线') {
      return AppMessage.handleInvalidPattern();
    }
    if (raw.startsWith('AWiki Me 当前未接入 DID 注册插件（') &&
        raw.endsWith('或接入原生插件后再在 App 内完成注册。')) {
      final start = raw.indexOf('（');
      final end = raw.indexOf('注册）');
      final authHint =
          start >= 0 && end > start ? raw.substring(start + 1, end) : '手机号+验证码';
      return AppMessage.didRegistrationPluginMissing(authHint);
    }
    if (raw == 'AWiki Me 当前未接入 DID 注册插件，无法自动刷新 token。') {
      return AppMessage.didRegistrationRefreshUnsupported();
    }
    if (raw == 'AWiki Me 当前未启用 E2EE，请接入原生插件实现') {
      return AppMessage.e2eePluginMissing();
    }
    if (raw == '文件选择失败，请稍后重试。') {
      return AppMessage.documentPickerFailed();
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
      case 'newMessageArrived':
        return l10n.newMessageArrived;
      case 'requestTimeoutRetry':
        return l10n.requestTimeoutRetry;
      case 'operationFailedRetry':
        return l10n.operationFailedRetry;
      case 'emailNotActivatedClickLink':
        return l10n.emailNotActivatedClickLink;
      case 'sessionExpiredRelogin':
        return l10n.sessionExpiredRelogin;
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
      case 'localCredentialIndexInvalid':
        return l10n.localCredentialIndexInvalid;
      case 'localCredentialIndexMissingCredentials':
        return l10n.localCredentialIndexMissingCredentials;
      case 'credentialIndexEntryInvalid':
        return l10n.credentialIndexEntryInvalid(value ?? '');
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
      case 'linkOpenFailed':
        return detail == null || detail!.isEmpty
            ? l10n.linkOpenFailed
            : l10n.linkOpenFailedWithDetail(detail!);
      case 'groupNameRequired':
        return l10n.groupNameRequired;
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
      case 'operationFailedRetry':
        return 'The operation failed. Please try again later.';
      case 'raw':
        return detail ?? 'The operation failed. Please try again later.';
      default:
        return detail ?? 'The operation failed. Please try again later.';
    }
  }

  static String _normalize(Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    if (raw.startsWith('StateError: ')) {
      return raw.substring('StateError: '.length);
    }
    if (raw.startsWith('Unsupported operation: ')) {
      return raw.substring('Unsupported operation: '.length);
    }
    if (raw.startsWith('UnsupportedError: ')) {
      return raw.substring('UnsupportedError: '.length);
    }
    if (raw.startsWith('ArgumentError: ')) {
      return raw.substring('ArgumentError: '.length);
    }
    return raw;
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
