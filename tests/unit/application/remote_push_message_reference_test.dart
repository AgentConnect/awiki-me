import 'package:awiki_me/src/application/remote_push_message_reference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remotePushOpaqueMessageReference', () {
    test('matches the release Message Service fixed vectors', () {
      const vectors = <String, String>{
        'message-sensitive-id': 'message_xoHiCNuDN3nIPLC3HI_ay7zP',
        'skill-greeting-9280d474542be461e0ec5fd2dedc2937':
            'message_2Tk1yCrJgbyEnIDR2mIcvFQ8',
      };

      for (final entry in vectors.entries) {
        final opaque = remotePushOpaqueMessageReference(entry.key);

        expect(opaque, entry.value);
        expect(opaque, isNot(contains(entry.key)));
      }
    });

    test('rejects unsafe message identifiers', () {
      final invalid = <String>[
        '',
        ' leading',
        'trailing ',
        'line\nbreak',
        'delete\u007fcontrol',
        List<String>.filled(257, 'a').join(),
      ];

      for (final messageId in invalid) {
        expect(
          () => remotePushOpaqueMessageReference(messageId),
          throwsArgumentError,
          reason: 'invalid message ID ${messageId.length}',
        );
      }
    });
  });

  group('remotePushOpaqueTargetReference', () {
    test('matches the release Message Service target vector', () {
      expect(
        remotePushOpaqueTargetReference('did:wba:example.test:alice'),
        'target__O36e96xvUp2bpAWguuIrcdZ',
      );
    });

    test('rejects unsafe owner DIDs', () {
      for (final ownerDid in <String>['', ' did:test:alice', 'did:test:a\n']) {
        expect(
          () => remotePushOpaqueTargetReference(ownerDid),
          throwsArgumentError,
        );
      }
    });
  });
}
