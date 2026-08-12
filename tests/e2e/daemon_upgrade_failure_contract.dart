import 'package:awiki_me/src/presentation/agents/agent_ui_messages.dart';

void verifyDaemonUpgradeFailureContract() {
  final failure = DaemonUpgradeFailureView.fromResult(<String, Object?>{
    'error_code': 'upgrade_download_failed',
    'failed_stage': 'downloading',
    'retryable': true,
    'last_error_summary':
        'daemon package download was interrupted after retries',
    'diagnostic_summary':
        'download daemon package <url>: response body interrupted',
  });

  if (failure.messageCode != AgentUiMessageCodes.upgradeDownloadFailed ||
      failure.failedStage != 'downloading' ||
      failure.retryable != true ||
      failure.diagnosticSummary == null) {
    throw StateError('daemon upgrade failure contract is not preserved');
  }
}
