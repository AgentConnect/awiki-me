import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/l10n/app_localizations_en.dart';
import 'package:awiki_me/l10n/app_localizations_zh.dart';
import 'package:awiki_me/src/core/app_error_classifier.dart';
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

  test(
    'maps structured registration verification errors without parsing messages',
    () {
      final unavailable = AppMessage.fromError(
        const AppStructuredError(
          code: 'identity.registration_verification_unavailable',
          cause: core.AwikiImCoreException(
            code: 'service_error',
            message: 'diagnostic text may change',
            statusCode: 409,
            serviceCode: '-32003',
          ),
        ),
      );
      final invalid = AppMessage.fromError(
        const AppStructuredError(
          code: 'identity.registration_verification_invalid',
          cause: core.AwikiImCoreException(
            code: 'service_error',
            message: 'another diagnostic',
            statusCode: 400,
          ),
        ),
      );

      expect(unavailable, AppMessage.registrationVerificationUnavailable());
      expect(
        unavailable.resolve(AppLocalizationsZh()),
        '这个验证码已过期或已被使用，请重新发送验证码后再试。',
      );
      expect(
        unavailable.resolve(AppLocalizationsEn()),
        'This verification code has expired or has already been used. Send a new code and try again.',
      );
      expect(invalid, AppMessage.registrationVerificationInvalid());
      expect(invalid.resolve(AppLocalizationsZh()), '验证码不正确，请核对后重试。');
    },
  );

  test('maps invalid registration recovery state to support guidance', () {
    final message = AppMessage.fromError(
      const AppStructuredError(
        code: 'identity.registration_recovery_state_invalid',
        cause: core.AwikiImCoreException(
          code: 'service_error',
          message: 'diagnostic text may change',
          statusCode: 409,
        ),
      ),
    );

    expect(message, AppMessage.registrationRecoveryStateInvalid());
    expect(
      message.resolve(AppLocalizationsZh()),
      '当前 Handle 的身份状态需要服务器处理，请联系支持后重试。',
    );
    expect(
      message.resolve(AppLocalizationsEn()),
      "This Handle's identity state needs server-side attention. Contact support before trying again.",
    );
  });

  test(
    'maps every stable identity deletion guard to dedicated localized copy',
    () {
      const expected = <String, String>{
        'handle_recovery.transition_must_complete':
            'identityDeletionCompleteTransitionFirst',
        'handle_recovery.join_must_complete':
            'identityDeletionCompleteJoinFirst',
        'identity.local_data_deletion_pending':
            'identityDeletionPendingWillResume',
        'identity.local_deletion_conflict': 'identityDeletionConflict',
      };
      for (final entry in expected.entries) {
        final message = AppMessage.fromError(
          AppStructuredError(
            code: entry.key,
            cause: const core.AwikiImCoreException(
              code: 'service_error',
              message: 'redacted diagnostic',
            ),
          ),
        );
        expect(message.id, entry.value);
        expect(message.resolve(AppLocalizationsZh()), isNotEmpty);
        expect(message.resolve(AppLocalizationsEn()), isNotEmpty);
      }
    },
  );

  test('maps im-core transport unavailable errors to friendly network copy', () {
    final message = AppMessage.fromError(
      const core.AwikiImCoreException(
        code: 'transport_unavailable',
        message:
            'transport unavailable: error sending request for url (https://anpclaw.com/user-service/v1/did/profile/rpc)',
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

  test('normalizes Dart ArgumentError before mapping handle validation', () {
    final message = AppMessage.fromError(
      ArgumentError('handle_invalid_pattern'),
    );

    expect(message, AppMessage.handleInvalidPattern());
    expect(
      message.resolve(AppLocalizationsZh()),
      'handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线',
    );
  });

  test('maps screenshot permission errors to actionable localized copy', () {
    final message = AppMessage.fromError(
      StateError('screenshot_screen_recording_permission_required'),
    );

    expect(message, AppMessage.screenshotPermissionRequired());
    expect(
      message.resolve(AppLocalizationsZh()),
      'macOS 要求开启“屏幕录制”权限才能截图。请在系统设置中允许 AWiki Me，完成后退出并重新打开应用。',
    );
    expect(
      message.resolve(AppLocalizationsEn()),
      'macOS requires Screen Recording permission to take screenshots. Allow AWiki Me in System Settings, then quit and reopen the app.',
    );
  });
}
