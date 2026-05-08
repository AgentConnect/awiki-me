import 'package:awiki_me/src/presentation/shared/formatters/display_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compactDid only recognizes e1 DID user segment', () {
    expect(
      DidDisplayFormatter.compactDid('did:wba:awiki.ai:user:alice:e1_key'),
      'alice',
    );
    expect(
      DidDisplayFormatter.compactDid('did:wba:awiki.ai:user:alice:k1_legacy'),
      'k1_legacy',
    );
  });
}
