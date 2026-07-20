import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/remote_multi_device_join_contract.dart';

void main() {
  group('remote multi-device OTP resolver argv', () {
    test('accepts the reviewed fixed SSH argv for staged OTP mode', () {
      final command = parseRemoteMultiDeviceOtpCommand(
        jsonEncode(reviewedStagedOtpResolverCommand),
        requireReviewedStagedResolver: true,
      );

      expect(command, reviewedStagedOtpResolverCommand);
    });

    test('rejects local shells and nested ssh shell execution', () {
      for (final command in <List<String>>[
        <String>['/bin/sh', '-c', 'resolver'],
        <String>['bash', '-c', 'resolver'],
        <String>['ssh', 'ali', 'sh', '-c', 'resolver'],
        <String>['ssh', 'ali', '/bin/bash', '-c', 'resolver'],
      ]) {
        expect(
          () => parseRemoteMultiDeviceOtpCommand(
            jsonEncode(command),
            requireReviewedStagedResolver: false,
          ),
          throwsFormatException,
          reason: command.join(' '),
        );
      }
    });

    test('rejects shell metacharacters newlines and multi-command argv', () {
      for (final unsafe in <String>[
        'cd /tmp && resolver',
        'resolver;next',
        'resolver|next',
        r'$(resolver)',
        'resolver\nnext',
        'resolver\rnext',
        'resolver next',
      ]) {
        expect(
          () => parseRemoteMultiDeviceOtpCommand(
            jsonEncode(<String>['ssh', 'ali', unsafe]),
            requireReviewedStagedResolver: false,
          ),
          throwsFormatException,
          reason: jsonEncode(unsafe),
        );
      }
    });

    test('staged mode rejects safe but unreviewed resolver argv', () {
      expect(
        () => parseRemoteMultiDeviceOtpCommand(
          jsonEncode(<String>['ssh', 'ali', '/safe/resolver', '--apply']),
          requireReviewedStagedResolver: true,
        ),
        throwsFormatException,
      );
    });
  });

  group('remote multi-device staged OTP flag', () {
    test('accepts only absent zero or one', () {
      expect(parseRemoteMultiDeviceStagedOtpFlag(const {}), isFalse);
      expect(
        parseRemoteMultiDeviceStagedOtpFlag(const {
          remoteMultiDeviceStagedOtpFlag: '0',
        }),
        isFalse,
      );
      expect(
        parseRemoteMultiDeviceStagedOtpFlag(const {
          remoteMultiDeviceStagedOtpFlag: '1',
        }),
        isTrue,
      );
      expect(
        () => parseRemoteMultiDeviceStagedOtpFlag(const {
          remoteMultiDeviceStagedOtpFlag: 'true',
        }),
        throwsFormatException,
      );
    });
  });

  group('remote multi-device SMS response', () {
    test('accepts 200 without staged mode', () {
      expect(
        evaluateRemoteMultiDeviceSmsResponse(
          statusCode: 200,
          contentType: 'application/json',
          body: '{"message":"sent"}',
          allowStagedOtpOnSmsError: false,
        ),
        RemoteMultiDeviceSmsDecision.delivered,
      );
    });

    test('accepts only the deployed Globe provider failure in staged mode', () {
      expect(
        evaluateRemoteMultiDeviceSmsResponse(
          statusCode: 503,
          contentType: 'application/problem+json',
          body: _validSmsProblemBody(),
          allowStagedOtpOnSmsError: true,
        ),
        RemoteMultiDeviceSmsDecision.stagedAfterSmsError,
      );
      expect(
        () => evaluateRemoteMultiDeviceSmsResponse(
          statusCode: 503,
          contentType: 'application/problem+json',
          body: _validSmsProblemBody(),
          allowStagedOtpOnSmsError: false,
        ),
        throwsFormatException,
      );
    });

    test('rejects any RFC7807 field or shape drift without exposing body', () {
      final valid = jsonDecode(_validSmsProblemBody()) as Map<String, dynamic>;
      final invalidBodies = <Object?>[
        <String, Object?>{...valid, 'extra': true},
        <String, Object?>{...valid}..remove('instance'),
        <String, Object?>{...valid, 'type': 'https://example.test/problem'},
        <String, Object?>{...valid, 'title': 'Unavailable'},
        <String, Object?>{...valid, 'status': '503'},
        <String, Object?>{...valid, 'status': 502},
        <String, Object?>{...valid, 'detail': 'SMS_ERROR'},
        <String, Object?>{
          ...valid,
          'detail':
              '[SMS_ERROR] SMS send failed: [MOBILE_NUMBER_ILLEGAL] '
              'The mobile number is illegal.',
        },
        <String, Object?>{
          ...valid,
          'detail':
              '[SMS_ERROR] Globe SMS send failed: [OTHER_PROVIDER_ERROR] '
              'The mobile number is illegal.',
        },
        <String, Object?>{
          ...valid,
          'detail':
              '[SMS_ERROR] Globe SMS send failed: [MOBILE_NUMBER_ILLEGAL] '
              '[OTHER_PROVIDER_ERROR] provider detail.',
        },
        <String, Object?>{
          ...valid,
          'detail':
              '[SMS_ERROR] Globe SMS send failed: [MOBILE_NUMBER_ILLEGAL] '
              '[MOBILE_NUMBER_ILLEGAL] provider detail.',
        },
        <String, Object?>{...valid, 'detail': '${valid['detail']}\n'},
        <String, Object?>{...valid, 'detail': '${valid['detail']} '},
        <String, Object?>{...valid, 'instance': '/wrong'},
      ];
      for (final body in invalidBodies) {
        var resolverCalls = 0;
        expect(
          () => continueRemoteMultiDeviceOtpAfterSmsResponse(
            statusCode: 503,
            contentType: 'application/problem+json',
            body: jsonEncode(body),
            allowStagedOtpOnSmsError: true,
            resolveOtp: () {
              resolverCalls += 1;
              return 'not-used';
            },
          ),
          throwsFormatException,
        );
        expect(resolverCalls, 0, reason: jsonEncode(body));
      }
      for (final contentType in <String?>[
        null,
        'application/json',
        'application/problem+json; charset=utf-8',
        'text/plain',
      ]) {
        var resolverCalls = 0;
        expect(
          () => continueRemoteMultiDeviceOtpAfterSmsResponse(
            statusCode: 503,
            contentType: contentType,
            body: _validSmsProblemBody(),
            allowStagedOtpOnSmsError: true,
            resolveOtp: () {
              resolverCalls += 1;
              return 'not-used';
            },
          ),
          throwsFormatException,
        );
        expect(resolverCalls, 0, reason: contentType);
      }
    });

    test('rejects secret-like provider detail before invoking resolver', () {
      for (final providerMessage in <String>[
        'otp=654321',
        'token=must-not-leak',
        'reference 654321',
        'authorization unavailable',
      ]) {
        var resolverCalls = 0;
        expect(
          () => continueRemoteMultiDeviceOtpAfterSmsResponse(
            statusCode: 503,
            contentType: 'application/problem+json',
            body: _validSmsProblemBody(providerMessage: providerMessage),
            allowStagedOtpOnSmsError: true,
            resolveOtp: () {
              resolverCalls += 1;
              return 'not-used';
            },
          ),
          throwsFormatException,
        );
        expect(resolverCalls, 0, reason: providerMessage);
      }
    });

    test('invokes resolver once after 200 or the exact staged response', () {
      for (final response
          in <({int statusCode, String contentType, String body})>[
            (
              statusCode: 200,
              contentType: 'application/json',
              body: '{"message":"sent"}',
            ),
            (
              statusCode: 503,
              contentType: 'application/problem+json',
              body: _validSmsProblemBody(),
            ),
          ]) {
        var resolverCalls = 0;
        final result = continueRemoteMultiDeviceOtpAfterSmsResponse(
          statusCode: response.statusCode,
          contentType: response.contentType,
          body: response.body,
          allowStagedOtpOnSmsError: response.statusCode == 503,
          resolveOtp: () {
            resolverCalls += 1;
            return 'resolved';
          },
        );
        expect(result, 'resolved');
        expect(resolverCalls, 1);
      }
    });

    test('requires exactly six ASCII digits from the resolver', () {
      expect(isSixDigitAsciiOtp('482917'), isTrue);
      expect(isSixDigitAsciiOtp('48291'), isFalse);
      expect(isSixDigitAsciiOtp('4829170'), isFalse);
      expect(isSixDigitAsciiOtp('１２３４５６'), isFalse);
      expect(isSixDigitAsciiOtp('48291a'), isFalse);
    });
  });
}

String _validSmsProblemBody({
  String providerMessage = 'The mobile number is illegal.',
}) => jsonEncode(<String, Object?>{
  'type': 'about:blank',
  'title': 'SMS Service Error',
  'status': 503,
  'detail':
      '[SMS_ERROR] Globe SMS send failed: [MOBILE_NUMBER_ILLEGAL] '
      '$providerMessage',
  'instance': '/user-service/auth/sms-codes',
});
