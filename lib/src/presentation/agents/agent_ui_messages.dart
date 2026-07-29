final class AgentUiMessageCodes {
  const AgentUiMessageCodes._();

  static const loginRequired = 'agent.login_required';
  static const handleUnavailable = 'agent.handle_unavailable';
  static const personalAgentDisabled = 'agent.personal_agent_disabled';
  static const tenantUnsupported = 'agent.tenant_unsupported';
  static const selectDaemon = 'agent.select_daemon';
  static const daemonBootstrapMissing = 'agent.daemon_bootstrap_missing';
  static const daemonUnreachableDelete = 'agent.daemon_unreachable_delete';
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
  static const upgradeNotCancellable = 'agent.upgrade_not_cancellable';
  static const upgradeCancelFailed = 'agent.upgrade_cancel_failed';

  static const upgradeDownloadFailedPrefix = 'agent.upgrade_download_failed:';

  static String upgradeDownloadFailed(String summary) {
    return '$upgradeDownloadFailedPrefix$summary';
  }
}
