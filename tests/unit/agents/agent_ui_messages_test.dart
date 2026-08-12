import 'package:awiki_me/src/presentation/agents/agent_ui_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daemon upgrade failure codes map to stable user messages', () {
    const expectations = <String, String>{
      'upgrade_download_failed': AgentUiMessageCodes.upgradeDownloadFailed,
      'upgrade_integrity_failed': AgentUiMessageCodes.upgradeIntegrityFailed,
      'upgrade_extract_failed': AgentUiMessageCodes.upgradeExtractFailed,
      'upgrade_restart_failed': AgentUiMessageCodes.upgradeRestartFailed,
      'upgrade_install_failed': AgentUiMessageCodes.upgradeInstallFailed,
    };

    for (final entry in expectations.entries) {
      final failure = DaemonUpgradeFailureView.fromResult(<String, Object?>{
        'error_code': entry.key,
        'retryable': true,
        'diagnostic_summary': 'private diagnostic',
      });
      expect(failure.messageCode, entry.value, reason: entry.key);
      expect(failure.diagnosticSummary, 'private diagnostic');
    }
  });

  test('non-retryable install failure directs the user to reinstall', () {
    final failure = DaemonUpgradeFailureView.fromResult(<String, Object?>{
      'error_code': 'upgrade_install_failed',
      'retryable': false,
    });

    expect(failure.messageCode, AgentUiMessageCodes.upgradeRequiresReinstall);
    expect(failure.retryable, isFalse);
  });

  test('legacy daemon download failure does not claim resume support', () {
    final failure = DaemonUpgradeFailureView.fromResult(<String, Object?>{
      'error_code': 'upgrade_failed',
      'last_error_summary':
          'download daemon package https://example.invalid: request timed out',
    });

    expect(
      failure.messageCode,
      AgentUiMessageCodes.upgradeLegacyDownloadFailed,
    );
  });
}
