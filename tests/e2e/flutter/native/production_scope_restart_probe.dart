import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String _caseId = 'NATIVE-E2E-002';
const String _phase = String.fromEnvironment('AWIKI_SCOPE_RESTART_PHASE');
const String _scopeValue = String.fromEnvironment('AWIKI_SCOPE_RESTART_ID');
const String _resultPath = String.fromEnvironment(
  'AWIKI_SCOPE_RESTART_RESULT_PATH',
);
const String _productionService = 'ai.awiki.awikime.scope-secrets';
const String _developmentService = 'ai.awiki.awikime.dev.scope-secrets';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_ProbeApp(arguments: List<String>.unmodifiable(arguments)));
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp({required this.arguments});

  final List<String> arguments;

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    var status = 'failed';
    var code = 'production_scope_restart_failed';
    final configuration = _ProbeConfiguration.fromEnvironment(widget.arguments);
    try {
      if (!(Platform.isMacOS || Platform.isWindows) ||
          !kReleaseMode ||
          configuration.resultPath.trim().isEmpty) {
        throw StateError('production_scope_restart_precondition_failed');
      }
      final scope = StorageScopeId.parse(configuration.scopeValue);
      final repository = PlatformScopeSecretRepository.forCurrentBuild();
      final account = PlatformScopeSecretRepository.accountFor(scope);
      switch (configuration.phase) {
        case 'provision':
          await repository.delete(scope);
          _expectReadStatus(
            await repository.readExisting(scope),
            ScopeSecretReadStatus.missing,
            'production_scope_initial_state_not_missing',
          );
          await _expectPlatformFailure(
            () => const MethodChannelScopeSecretPlatformStore().read(
              service: _developmentService,
              account: account,
            ),
            'scope_secret_bad_request',
          );
          final first = ScopeSecretRecord(
            envelope: ScopeSecretEnvelope.create(scopeId: scope),
          );
          await repository.createExclusive(first);
          final created = await repository.readExisting(scope);
          _expectRecord(
            created,
            expectedRevision: 1,
            expectedEncoding: first.envelope.encode(),
            code: 'production_scope_provision_mismatch',
          );
          final newInstance = PlatformScopeSecretRepository.forCurrentBuild();
          _expectRecord(
            await newInstance.readExisting(scope),
            expectedRevision: 1,
            expectedEncoding: first.envelope.encode(),
            code: 'production_scope_new_instance_read_mismatch',
          );
          break;
        case 'reopen':
          final reopened = await repository.readExisting(scope);
          _expectRecord(
            reopened,
            expectedRevision: 1,
            code: 'production_scope_restart_read_mismatch',
          );
          await _expectRepositoryFailure(
            () => repository.createExclusive(
              ScopeSecretRecord(
                envelope: ScopeSecretEnvelope.create(scopeId: scope),
              ),
            ),
            ScopeSecretFailure.alreadyExists,
          );
          final unchanged = await repository.readExisting(scope);
          _expectRecord(
            unchanged,
            expectedRevision: 1,
            expectedEncoding: reopened.record!.envelope.encode(),
            code: 'production_scope_create_conflict_replaced_value',
          );

          final replacement = ScopeSecretRecord(
            envelope: reopened.record!.envelope.nextRevision(),
          );
          await repository.compareAndReplace(
            record: replacement,
            expectedRevision: 1,
          );
          _expectRecord(
            await repository.readExisting(scope),
            expectedRevision: 2,
            expectedEncoding: replacement.envelope.encode(),
            code: 'production_scope_cas_mismatch',
          );
          await _expectRepositoryFailure(
            () => repository.compareAndReplace(
              record: replacement,
              expectedRevision: 1,
            ),
            ScopeSecretFailure.revisionConflict,
          );
          _expectRecord(
            await PlatformScopeSecretRepository.forCurrentBuild().readExisting(
              scope,
            ),
            expectedRevision: 2,
            expectedEncoding: replacement.envelope.encode(),
            code: 'production_scope_stale_cas_changed_value',
          );
          break;
        case 'corrupt':
          _expectReadStatus(
            await repository.readExisting(scope),
            ScopeSecretReadStatus.corrupt,
            'production_scope_corrupt_not_detected',
          );
          if (await const MethodChannelScopeSecretPlatformStore().read(
                service: _productionService,
                account: account,
              ) ==
              null) {
            throw StateError('production_scope_corrupt_was_auto_deleted');
          }
          break;
        case 'scope_mismatch':
          _expectReadStatus(
            await repository.readExisting(scope),
            ScopeSecretReadStatus.scopeMismatch,
            'production_scope_mismatch_not_detected',
          );
          if (await const MethodChannelScopeSecretPlatformStore().read(
                service: _productionService,
                account: account,
              ) ==
              null) {
            throw StateError('production_scope_mismatch_was_auto_deleted');
          }
          break;
        case 'cleanup':
          await repository.delete(scope);
          _expectReadStatus(
            await repository.readExisting(scope),
            ScopeSecretReadStatus.missing,
            'production_scope_cleanup_failed',
          );
          final missingReplacement = ScopeSecretRecord(
            envelope: ScopeSecretEnvelope.create(scopeId: scope).nextRevision(),
          );
          await _expectRepositoryFailure(
            () => repository.compareAndReplace(
              record: missingReplacement,
              expectedRevision: 1,
            ),
            ScopeSecretFailure.revisionConflict,
          );
          break;
        default:
          throw StateError('production_scope_restart_phase_invalid');
      }
      status = 'passed';
      code = 'ok';
    } on Object catch (error) {
      code = _safeErrorCode(error);
    }
    final resultFile = File(configuration.resultPath);
    await resultFile.parent.create(recursive: true);
    await resultFile.writeAsString(
      jsonEncode(<String, String>{
        'case_id': _caseId,
        'phase': configuration.phase,
        'status': status,
        'code': code,
      }),
      flush: true,
    );
    exit(status == 'passed' ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String _safeErrorCode(Object error) {
  if (error is PlatformException) return error.code;
  if (error is ScopeSecretException) return error.code;
  if (error is StateError) {
    final message = error.message;
    if (RegExp(r'^[a-z0-9_]+$').hasMatch(message)) {
      return message;
    }
  }
  return 'production_scope_restart_failed';
}

final class _ProbeConfiguration {
  const _ProbeConfiguration({
    required this.phase,
    required this.scopeValue,
    required this.resultPath,
  });

  factory _ProbeConfiguration.fromEnvironment(List<String> arguments) =>
      _ProbeConfiguration(
        phase: _runtimeOption(arguments, 'awiki-scope-probe-phase', _phase),
        scopeValue: _runtimeOption(
          arguments,
          'awiki-scope-probe-id',
          _scopeValue,
        ),
        resultPath: _runtimeOption(
          arguments,
          'awiki-scope-probe-result',
          _resultPath,
        ),
      );

  final String phase;
  final String scopeValue;
  final String resultPath;
}

String _runtimeOption(List<String> arguments, String name, String fallback) {
  final prefix = '--$name=';
  final values = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .toList(growable: false);
  if (values.length > 1) {
    throw StateError('production_scope_restart_duplicate_argument');
  }
  return values.isEmpty ? fallback : values.single;
}

void _expectReadStatus(
  ScopeSecretReadResult result,
  ScopeSecretReadStatus expected,
  String code,
) {
  if (result.status != expected || result.record != null) {
    throw StateError(code);
  }
}

void _expectRecord(
  ScopeSecretReadResult result, {
  required int expectedRevision,
  String? expectedEncoding,
  required String code,
}) {
  final record = result.record;
  if (result.status != ScopeSecretReadStatus.present ||
      record == null ||
      record.envelope.revision != expectedRevision ||
      (expectedEncoding != null &&
          record.envelope.encode() != expectedEncoding)) {
    throw StateError(code);
  }
}

Future<void> _expectPlatformFailure(
  Future<Object?> Function() operation,
  String expectedCode,
) async {
  try {
    await operation();
  } on PlatformException catch (error) {
    if (error.code == expectedCode) return;
    rethrow;
  }
  throw StateError('production_scope_platform_failure_missing');
}

Future<void> _expectRepositoryFailure(
  Future<void> Function() operation,
  ScopeSecretFailure expected,
) async {
  try {
    await operation();
  } on ScopeSecretException catch (error) {
    if (error.failure == expected) return;
    rethrow;
  }
  throw StateError('production_scope_repository_failure_missing');
}
