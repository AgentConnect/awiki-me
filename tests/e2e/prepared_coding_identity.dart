import 'dart:convert';
import 'dart:io';

/// Reuse only an explicitly selected, owned ACP run. Reports and runtime Agents
/// still belong to the new run; the human App/CLI identities stay in place.
class PreparedCodingIdentity {
  PreparedCodingIdentity._(this.runId, this.directory);

  final String runId;
  final Directory directory;

  Directory get app => Directory('${directory.path}/app');
  Directory get cli => Directory('${directory.path}/cli-peer');
  Directory get cliHome => Directory('${directory.path}/cli-home');

  static PreparedCodingIdentity? resolve({
    required Directory root,
    required String suite,
    required String currentRunId,
    required String? preparedRunId,
  }) {
    if (preparedRunId == null) return null;
    if (suite != 'acp-agent' ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{7,79}$').hasMatch(preparedRunId) ||
        preparedRunId == currentRunId) {
      throw StateError('Invalid prepared ACP identity run selection.');
    }
    final base = Directory('${root.path}/.e2e/acp-agent');
    final directory = Directory('${base.path}/$preparedRunId');
    final ledger = File('${directory.path}/reports/resource_ledger.json');
    if (!ledger.existsSync()) {
      throw StateError('Prepared ACP identity run has no ownership ledger.');
    }
    final owner = jsonDecode(ledger.readAsStringSync());
    if (owner is! Map ||
        owner['runId'] != preparedRunId ||
        owner['suite'] != 'acp-agent' ||
        owner['scenario'] != 'acp-agent-full-ui') {
      throw StateError('Prepared ACP identity ownership does not match.');
    }
    final expected = '${base.resolveSymbolicLinksSync()}/$preparedRunId';
    if (directory.resolveSymbolicLinksSync() != expected) {
      throw StateError('Prepared ACP identity run must not redirect state.');
    }
    for (final name in ['app', 'cli-peer', 'cli-home']) {
      final child = Directory('${directory.path}/$name');
      if (!child.existsSync() ||
          child.resolveSymbolicLinksSync() != '$expected/$name') {
        throw StateError(
          'Prepared ACP identity state is missing or redirected.',
        );
      }
    }
    return PreparedCodingIdentity._(preparedRunId, directory);
  }

  RandomAccessFile acquireLease() {
    final file = File(
      '${directory.path}/.prepared-identity.lock',
    ).openSync(mode: FileMode.append);
    try {
      file.lockSync(FileLock.exclusive);
      return file;
    } on Object {
      file.closeSync();
      throw StateError('Prepared ACP identity is already in use.');
    }
  }
}
