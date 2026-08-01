import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/message_sync_diagnostics.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AwikiImCoreErrorMapper();

  test('maps unsupported capability with stable code', () {
    final mapped = mapper.map(mapper.unsupported('markThreadRead'));

    expect(mapped.code, 'unsupported_capability');
    expect(mapped.isUnsupported, isTrue);
    expect(mapped.message, contains('markThreadRead'));
  });

  test('sanitizes sensitive native error details', () {
    final mapped = mapper.map(
      const core.AwikiImCoreException(
        code: 'auth_failed',
        message:
            'Authorization: Bearer abc.def token=secret signature=very-secret private_key=raw',
      ),
    );

    expect(mapped.message, isNot(contains('abc.def')));
    expect(mapped.message, isNot(contains('very-secret')));
    expect(mapped.message, isNot(contains('raw')));
    expect(mapped.message, contains('<redacted>'));
  });

  test('preserves service error code and data from SDK errors', () {
    final mapped = mapper.map(
      const core.AwikiImCoreException(
        code: 'service_error',
        message: 'target did is inactive',
        statusCode: 409,
        serviceCode: '1007',
        serviceDataJson: '{"did":"did:example:old","handle":"alice"}',
      ),
    );

    expect(mapped.code, 'service_error');
    expect(mapped.statusCode, 409);
    expect(mapped.serviceCode, '1007');
    expect(
      mapped.serviceDataJson,
      '{"did":"did:example:old","handle":"alice"}',
    );
  });

  test('classifies Direct sync binding absence by stable service code', () {
    final mapped = mapper.map(
      const core.AwikiImCoreException(
        code: 'service_error',
        message: 'localized or changed diagnostic text',
        serviceCode: 'SYNC_THREAD_BINDING_REQUIRED',
      ),
    );

    expect(mapped.isDirectSyncBindingUnavailable, isTrue);
  });

  test('projects HTTP auth rejection without native error text', () {
    final failure = mapper.messageSyncFailure(
      const core.AwikiImCoreException(
        code: 'service_error',
        message: 'sensitive native error text',
        statusCode: 401,
        serviceCode: '1401',
      ),
    );

    expect(failure.category, AppMessageSyncFailureCategory.auth);
    expect(failure.code, '1401');
    expect(failure.httpStatus, 401);
    expect(failure.toString(), isNot(contains('sensitive')));
  });

  test('keeps transport failure retryable at the App boundary', () {
    final failure = mapper.messageSyncFailure(
      const core.AwikiImCoreException(
        code: 'transport_unavailable',
        message: 'offline',
      ),
    );

    expect(failure.category, AppMessageSyncFailureCategory.transport);
    expect(failure.code, 'transport_unavailable');
    expect(failure.httpStatus, isNull);
  });

  test('sync failure projection rejects unsafe service codes', () {
    final failure = mapper.messageSyncFailure(
      const core.AwikiImCoreException(
        code: 'service_error',
        message: 'private response',
        statusCode: 503,
        serviceCode: 'secret payload value',
      ),
    );

    expect(failure.category, AppMessageSyncFailureCategory.service);
    expect(failure.code, 'message_sync_failure');
    expect(failure.toString(), isNot(contains('secret')));
  });
}
