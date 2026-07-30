import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dotless local alias falls back after identity id lookup', () {
    final selectors = identitySelectorCandidates('cgw-038');

    expect(selectors, hasLength(2));
    expect(selectors[0], isA<core.IdIdentitySelector>());
    expect((selectors[0] as core.IdIdentitySelector).id, 'cgw-038');
    expect(selectors[1], isA<core.LocalAliasIdentitySelector>());
    expect((selectors[1] as core.LocalAliasIdentitySelector).alias, 'cgw-038');
  });

  test('unambiguous selectors do not add a local alias fallback', () {
    expect(
      identitySelectorCandidates('default').single,
      isA<core.DefaultIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('did:wba:awiki.info:user:alice:e1_a').single,
      isA<core.DidIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('alice.awiki.info').single,
      isA<core.HandleIdentitySelector>(),
    );
  });
}
