import 'package:awiki_im_core/awiki_im_core.dart' as core;
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
}
