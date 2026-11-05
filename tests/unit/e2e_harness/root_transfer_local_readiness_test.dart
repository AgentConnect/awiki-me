import 'package:flutter_test/flutter_test.dart';
import '../../e2e/root_transfer_registry_observer.dart';

void main() {
  test(
    'pending local authority is observed without an authenticated Registry read',
    () async {
      var ready = false;
      var reads = 0;
      final events = <String>[];
      Future<int?> observe() => readRegistryWhenLocalManagementReady<int>(
        localManagementReady: () async {
          events.add('local');
          return ready;
        },
        readRegistry: () async {
          events.add('registry');
          reads++;
          return 7;
        },
      );
      expect(await observe(), isNull);
      expect(reads, 0);
      ready = true;
      expect(await observe(), 7);
      expect(reads, 1);
      ready = false;
      expect(await observe(), isNull);
      expect(reads, 1);
      expect(events, ['local', 'local', 'registry', 'local']);
    },
  );
  test(
    'a local binding error is terminal and cannot trigger a remote read',
    () async {
      final error = StateError('device_registry_binding_mismatch');
      var reads = 0;
      await expectLater(
        readRegistryWhenLocalManagementReady<int>(
          localManagementReady: () async => throw error,
          readRegistry: () async {
            reads++;
            return 7;
          },
        ),
        throwsA(same(error)),
      );
      expect(reads, 0);
    },
  );
  test('permission denial after local readiness remains terminal', () async {
    final error = StateError('permission_denied');
    var reads = 0;
    await expectLater(
      readRegistryWhenLocalManagementReady<int>(
        localManagementReady: () async => true,
        readRegistry: () async {
          reads++;
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(reads, 1);
  });
}
