import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/l10n/app_localizations_en.dart';
import 'package:awiki_me/l10n/app_localizations_zh.dart';
import 'package:awiki_me/src/l10n/app_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps DID service errors to friendly localized copy', () {
    final message = AppMessage.fromError(
      const core.AwikiImCoreException(
        code: 'service_error',
        message:
            '{"jsonrpc":"2.0","result":null,"error":{"code":-32000,"message":"DID not found or revoked.","data":null},"id":"req-1"}',
      ),
    );

    expect(message, AppMessage.didNotFoundOrRevoked());
    expect(
      message.resolve(AppLocalizationsZh()),
      '未找到这个身份，或它已经被撤销。请检查 DID 是否正确，或切换到可用身份后重试。',
    );
    expect(
      message.resolve(AppLocalizationsEn()),
      'This DID does not exist or has been revoked. Check the DID and try again, or switch to a valid identity.',
    );
  });

  test('maps compact malformed DID service errors', () {
    final message = AppMessage.fromError(
      const core.AwikiImCoreException(
        code: 'service_error',
        message: 'DID not found orrevoked.',
      ),
    );

    expect(message, AppMessage.didNotFoundOrRevoked());
  });

  test('maps im-core transport unavailable errors to friendly network copy', () {
    final message = AppMessage.fromError(
      const core.AwikiImCoreException(
        code: 'transport_unavailable',
        message:
            'transport unavailable: error sending request for url (https://anpclaw.com/user-service/did/profile/rpc)',
      ),
    );

    expect(message, AppMessage.networkUnavailableRetry());
    expect(message.resolve(AppLocalizationsZh()), '网络连接暂时不可用，请检查网络后重试。');
    expect(
      message.resolve(AppLocalizationsEn()),
      'Network connection is temporarily unavailable. Please check your network and try again.',
    );
  });

  test('maps common socket and DNS failures to friendly network copy', () {
    final socketMessage = AppMessage.fromError(
      Exception('SocketException: Failed host lookup: anpclaw.com'),
    );
    final refusedMessage = AppMessage.fromError(
      Exception('Connection refused'),
    );
    final proxyMessage = AppMessage.fromError(
      Exception('ClientException: proxy connection failed'),
    );
    final handshakeMessage = AppMessage.fromError(
      Exception('HandshakeException: Connection terminated during handshake'),
    );

    expect(socketMessage, AppMessage.networkUnavailableRetry());
    expect(refusedMessage, AppMessage.networkUnavailableRetry());
    expect(proxyMessage, AppMessage.networkUnavailableRetry());
    expect(handshakeMessage, AppMessage.networkUnavailableRetry());
  });

  test('maps screenshot permission errors to actionable localized copy', () {
    final message = AppMessage.fromError(
      StateError('screenshot_screen_recording_permission_required'),
    );

    expect(message, AppMessage.screenshotPermissionRequired());
    expect(
      message.resolve(AppLocalizationsZh()),
      '录屏权限尚未生效。请在系统设置的“录屏与系统录音”中允许当前 AWiki Me 应用，然后完全退出并重新打开。',
    );
    expect(
      message.resolve(AppLocalizationsEn()),
      'Screen Recording permission is not active. Allow the current AWiki Me app under Screen & System Audio Recording in System Settings, then quit and reopen it.',
    );
  });
}
