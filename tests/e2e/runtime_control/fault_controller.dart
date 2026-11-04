import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:awiki_me/src/app/e2e_fault_hooks.dart';
import '../protected_files.dart';
import 'invocation.dart';

/// Instantiated only by a test entrypoint, never the normal application.
final class E2eFaultController {
  E2eFaultController({
    required this.phase,
    this.invocation,
    this.pauseForTermination = false,
  });
  final String phase;
  final E2eInvocation? invocation;
  final bool pauseForTermination;
  bool _fired = false;

  Future<E2eFaultAction> hit(E2eFaultCheckpoint checkpoint) async {
    final matching =
        (phase == 'crash_a' &&
            checkpoint == E2eFaultCheckpoint.recoveryBeforeProductReset) ||
        (phase == 'identity_deletion_a' &&
            checkpoint == E2eFaultCheckpoint.identityAfterProductDelete);
    if (!matching) return E2eFaultAction.continueExecution;
    if (_fired) throw StateError('E2E fault checkpoint fired twice.');
    _fired = true;
    if (pauseForTermination) {
      final plan = invocation;
      if (plan == null) {
        throw StateError('External termination requires a bound invocation.');
      }
      if (plan.interruption != checkpoint.name) {
        throw StateError('Checkpoint differs from the interruption plan.');
      }
      final path = Platform.environment[invocationPathEnvironment];
      if (path == null) throw StateError('Checkpoint path is not bound.');
      final file = File('$path.checkpoint');
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Checkpoint already exists.');
      }
      final temporary = File('${file.path}.tmp');
      if (FileSystemEntity.typeSync(temporary.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Checkpoint temporary already exists.');
      }
      temporary.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'invocationId': plan.invocationId,
          'planDigest': plan.digest,
          'checkpoint': checkpoint.name,
          'pid': pid,
          'occurrence': 1,
        }),
        flush: true,
      );
      protectE2ePathSync(temporary.path);
      temporary.renameSync(file.path);
      // The owning process runner enforces the original execution deadline.
      // An OS kill deliberately does not execute Dart finally blocks.
      final remaining =
          plan.deadlineUnixMs - DateTime.now().toUtc().millisecondsSinceEpoch;
      if (remaining <= 0) {
        throw StateError('Interruption controller deadline expired.');
      }
      return Completer<E2eFaultAction>().future.timeout(
        Duration(milliseconds: remaining),
        onTimeout: () => throw StateError(
          'Interruption controller did not terminate its child.',
        ),
      );
    }
    return checkpoint == E2eFaultCheckpoint.recoveryBeforeProductReset
        ? E2eFaultAction.stopBeforeReset
        : E2eFaultAction.throwError;
  }
}
