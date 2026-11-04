// Runtime-only selection. Never imported by the normal product entrypoint.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../protected_files.dart';
import 'shared_host_contract.dart';

const invocationPathEnvironment = 'AWIKI_E2E_INVOCATION_PATH';
const invocationDigestEnvironment = 'AWIKI_E2E_INVOCATION_DIGEST';

typedef ArtifactRuntimeMode = ({String family, String phase, String role});

ArtifactRuntimeMode artifactRuntimeMode(String name) {
  sharedHostEntry(name);
  const recovery = {
    'recovery-main': 'main',
    'recovery-crash-a': 'crash_a',
    'recovery-crash-b': 'crash_b',
    'recovery-fresh-restart': 'fresh_restart',
    'recovery-registration-resume-a': 'registration_resume_a',
    'recovery-registration-resume-b': 'registration_resume_b',
    'identity-deletion-a': 'identity_deletion_a',
    'identity-deletion-b': 'identity_deletion_b',
  };
  if (recovery.containsKey(name)) {
    return (family: 'recovery', phase: recovery[name]!, role: 'primary');
  }
  if (const ['restart-a', 'restart-b', 'restart-c'].contains(name)) {
    return (family: 'restart', phase: name, role: 'primary');
  }
  if (const ['admin', 'joiner'].contains(name)) {
    return (family: 'app-pair', phase: 'main', role: name);
  }
  return (family: 'single', phase: 'main', role: 'primary');
}

/// Schema changes invalidate execution plans, independently of compile keys.
final class E2eInvocation {
  E2eInvocation({
    required this.artifact,
    required this.runId,
    required this.scenario,
    required this.invocationId,
    required this.platform,
    required List<String> caseIds,
    required this.artifactSha256,
    this.attempt = 1,
    this.interruption = '',
    int? deadlineUnixMs,
  }) : caseIds = List.unmodifiable(caseIds),
       deadlineUnixMs =
           deadlineUnixMs ??
           DateTime.now().toUtc().millisecondsSinceEpoch + 60000 {
    if (![artifact, runId, scenario, invocationId].every(
          (v) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$').hasMatch(v),
        ) ||
        !const ['windows', 'linux', 'macos'].contains(platform) ||
        attempt < 1 ||
        caseIds.isEmpty ||
        caseIds.toSet().length != caseIds.length ||
        caseIds.any((v) => !RegExp(r'^[A-Z0-9-]+$').hasMatch(v)) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      throw const FormatException('Invalid E2E invocation identity.');
    }
    if (interruption.isNotEmpty &&
        interruption !=
            switch (mode.phase) {
              'crash_a' => 'recoveryBeforeProductReset',
              'identity_deletion_a' => 'identityAfterProductDelete',
              _ => null,
            }) {
      throw const FormatException(
        'Interruption is not supported by this phase.',
      );
    }
  }

  final String artifact,
      runId,
      scenario,
      invocationId,
      platform,
      artifactSha256;
  final List<String> caseIds;
  final int attempt;
  final String interruption;
  final int deadlineUnixMs;
  ArtifactRuntimeMode get mode => artifactRuntimeMode(artifact);
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'artifact': artifact,
    'runId': runId,
    'scenario': scenario,
    'invocationId': invocationId,
    'platform': platform,
    'attempt': attempt,
    'caseIds': caseIds,
    'artifactSha256': artifactSha256,
    'phase': mode.phase,
    'role': mode.role,
    'interruption': interruption,
    'deadlineUnixMs': deadlineUnixMs,
  };

  factory E2eInvocation.fromJson(Object? value) {
    const keys = {
      'schemaVersion',
      'artifact',
      'runId',
      'scenario',
      'invocationId',
      'platform',
      'attempt',
      'caseIds',
      'artifactSha256',
      'phase',
      'role',
      'interruption',
      'deadlineUnixMs',
    };
    if (value is! Map ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value.length != keys.length ||
        value['schemaVersion'] != 1 ||
        value['caseIds'] is! List ||
        (value['caseIds'] as List).any((v) => v is! String) ||
        value['attempt'] is! int ||
        value['deadlineUnixMs'] is! int ||
        const [
          'artifact',
          'runId',
          'scenario',
          'invocationId',
          'platform',
          'artifactSha256',
          'phase',
          'role',
          'interruption',
        ].any((k) => value[k] is! String)) {
      throw const FormatException('Invalid E2E invocation schema.');
    }
    final result = E2eInvocation(
      artifact: value['artifact'] as String,
      runId: value['runId'] as String,
      scenario: value['scenario'] as String,
      invocationId: value['invocationId'] as String,
      platform: value['platform'] as String,
      attempt: value['attempt'] as int,
      caseIds: List.unmodifiable((value['caseIds'] as List).cast<String>()),
      artifactSha256: value['artifactSha256'] as String,
      interruption: value['interruption'] as String,
      deadlineUnixMs: value['deadlineUnixMs'] as int,
    );
    if (value['phase'] != result.mode.phase ||
        value['role'] != result.mode.role) {
      throw const FormatException(
        'E2E invocation mode does not match artifact.',
      );
    }
    return result;
  }

  void validateEnvironment(Map<String, String> env) {
    if (runId != env['AWIKI_E2E_RUN_ID'] ||
        scenario != env['AWIKI_E2E_SCENARIO'] ||
        caseIds.join(',') != env['AWIKI_E2E_CASE_IDS'] ||
        platform != Platform.operatingSystem) {
      throw const FormatException(
        'E2E invocation differs from execution identity.',
      );
    }
  }

  static E2eInvocation? load(Map<String, String> env, {String? family}) {
    final path = env[invocationPathEnvironment];
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.isAbsolute ||
        !isPrivateE2eFile(file) ||
        file.lengthSync() > 16384) {
      throw const FormatException(
        'E2E invocation must be a bounded private file.',
      );
    }
    final result = E2eInvocation.fromJson(jsonDecode(file.readAsStringSync()));
    if (env[invocationDigestEnvironment] != result.digest) {
      throw const FormatException('E2E invocation digest is stale.');
    }
    result.validateEnvironment(env);
    final remaining =
        result.deadlineUnixMs - DateTime.now().toUtc().millisecondsSinceEpoch;
    if (remaining <= 0 || remaining > const Duration(days: 1).inMilliseconds) {
      throw const FormatException(
        'E2E invocation deadline is expired or invalid.',
      );
    }
    if (family != null && result.mode.family != family) {
      throw const FormatException(
        'E2E invocation has the wrong test entrypoint.',
      );
    }
    return result;
  }

  void write(File destination) {
    destination.parent.createSync(recursive: true);
    protectE2ePathSync(destination.parent.path, directory: true);
    final temporary = File('${destination.path}.tmp');
    if (FileSystemEntity.typeSync(temporary.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FormatException(
        'E2E invocation cannot overwrite an existing path.',
      );
    }
    temporary.writeAsStringSync(jsonEncode(toJson()), flush: true);
    protectE2ePathSync(temporary.path);
    temporary.renameSync(destination.path);
  }
}
