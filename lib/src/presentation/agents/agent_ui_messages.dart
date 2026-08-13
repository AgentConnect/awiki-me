final class AgentUiMessageCodes {
  const AgentUiMessageCodes._();

  static const loginRequired = 'agent.login_required';
  static const handleUnavailable = 'agent.handle_unavailable';
  static const personalAgentDisabled = 'agent.personal_agent_disabled';
  static const tenantUnsupported = 'agent.tenant_unsupported';
  static const selectDaemon = 'agent.select_daemon';
  static const daemonBootstrapMissing = 'agent.daemon_bootstrap_missing';
  static const daemonUnreachableDelete = 'agent.daemon_unreachable_delete';
  static const daemonDeleteNoResponse = 'agent.daemon_delete_no_response';
  static const daemonUnreachableUpgrade = 'agent.daemon_unreachable_upgrade';
  static const personalAgentMissing = 'agent.personal_agent_missing';
  static const statusSyncWaiting = 'agent.status_sync_waiting';
  static const upgradeCancelNoResponse = 'agent.upgrade_cancel_no_response';
  static const scopeMismatch = 'agent.scope_mismatch';
  static const controllerHandleMismatch = 'agent.controller_handle_mismatch';
  static const controllerScopeMissing = 'agent.controller_scope_missing';
  static const installCommandUsed = 'agent.install_command_used';
  static const sessionExpired = 'agent.session_expired';
  static const requestTimeout = 'agent.request_timeout';
  static const networkPreserved = 'agent.network_preserved';
  static const loadFailed = 'agent.load_failed';
  static const statusSessionExpired = 'agent.status_session_expired';
  static const statusTimeout = 'agent.status_timeout';
  static const statusNetworkPreserved = 'agent.status_network_preserved';
  static const statusRefreshFailed = 'agent.status_refresh_failed';
  static const upgradeIncomplete = 'agent.upgrade_incomplete';
  static const upgradeDownloadFailed = 'agent.upgrade_download_failed';
  static const upgradeLegacyDownloadFailed =
      'agent.upgrade_legacy_download_failed';
  static const upgradeIntegrityFailed = 'agent.upgrade_integrity_failed';
  static const upgradeExtractFailed = 'agent.upgrade_extract_failed';
  static const upgradeRestartFailed = 'agent.upgrade_restart_failed';
  static const upgradeInstallFailed = 'agent.upgrade_install_failed';
  static const upgradeRequiresReinstall = 'agent.upgrade_requires_reinstall';
  static const upgradeNotCancellable = 'agent.upgrade_not_cancellable';
  static const upgradeCancelFailed = 'agent.upgrade_cancel_failed';
}

class DaemonUpgradeFailureView {
  const DaemonUpgradeFailureView({
    required this.messageCode,
    this.errorCode,
    this.failedStage,
    this.retryable,
    this.diagnosticSummary,
  });

  final String messageCode;
  final String? errorCode;
  final String? failedStage;
  final bool? retryable;
  final String? diagnosticSummary;

  factory DaemonUpgradeFailureView.fromResult(Map<String, Object?> result) {
    final errorCode = _nonEmptyString(result['error_code']);
    final failedStage = _nonEmptyString(result['failed_stage']);
    final diagnosticSummary =
        _nonEmptyString(result['diagnostic_summary']) ??
        _nonEmptyString(result['last_error_summary']);
    final messageCode = switch (errorCode) {
      'upgrade_download_failed' => AgentUiMessageCodes.upgradeDownloadFailed,
      'upgrade_integrity_failed' => AgentUiMessageCodes.upgradeIntegrityFailed,
      'upgrade_extract_failed' => AgentUiMessageCodes.upgradeExtractFailed,
      'upgrade_restart_failed' => AgentUiMessageCodes.upgradeRestartFailed,
      'upgrade_install_failed' when result['retryable'] == false =>
        AgentUiMessageCodes.upgradeRequiresReinstall,
      'upgrade_install_failed' => AgentUiMessageCodes.upgradeInstallFailed,
      _ => _legacyFailureCode(diagnosticSummary),
    };
    return DaemonUpgradeFailureView(
      messageCode: messageCode,
      errorCode: errorCode,
      failedStage: failedStage,
      retryable: result['retryable'] is bool
          ? result['retryable'] as bool
          : null,
      diagnosticSummary: diagnosticSummary,
    );
  }

  static String _legacyFailureCode(String? summary) {
    if (summary == null) {
      return AgentUiMessageCodes.upgradeIncomplete;
    }
    final normalized = summary.toLowerCase();
    if (normalized.contains('sha256')) {
      return AgentUiMessageCodes.upgradeIntegrityFailed;
    }
    if (normalized.contains('extract') || normalized.contains('archive')) {
      return AgentUiMessageCodes.upgradeExtractFailed;
    }
    if (normalized.contains('restart')) {
      return AgentUiMessageCodes.upgradeRestartFailed;
    }
    if (normalized.contains('download daemon package') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('connection') ||
        normalized.contains('http body')) {
      return AgentUiMessageCodes.upgradeLegacyDownloadFailed;
    }
    return AgentUiMessageCodes.upgradeInstallFailed;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
