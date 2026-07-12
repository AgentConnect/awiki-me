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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

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
    try {
      if (!Platform.isMacOS || !kReleaseMode || _resultPath.trim().isEmpty) {
        throw StateError('production_scope_restart_precondition_failed');
      }
      final scope = StorageScopeId.parse(_scopeValue);
      final repository = PlatformScopeSecretRepository.forCurrentBuild();
      final account = PlatformScopeSecretRepository.accountFor(scope);
      switch (_phase) {
        case 'provision':
          await repository.delete(scope);
          try {
            await const MacOsScopeSecretPlatformStore().read(
              service: 'ai.awiki.awikime.dev.scope-secrets',
              account: account,
            );
            throw StateError('development_service_was_accepted');
          } on PlatformException catch (error) {
            if (error.code != 'scope_secret_bad_request') rethrow;
          }
          await repository.createExclusive(
            ScopeSecretRecord(
              envelope: ScopeSecretEnvelope.create(scopeId: scope),
            ),
          );
          final created = await repository.readExisting(scope);
          if (created.status != ScopeSecretReadStatus.present ||
              created.record?.envelope.revision != 1) {
            throw StateError('production_scope_provision_mismatch');
          }
          break;
        case 'reopen':
          final reopened = await repository.readExisting(scope);
          if (reopened.status != ScopeSecretReadStatus.present ||
              reopened.record?.envelope.revision != 1) {
            throw StateError('production_scope_restart_read_mismatch');
          }
          try {
            await repository.createExclusive(
              ScopeSecretRecord(
                envelope: ScopeSecretEnvelope.create(scopeId: scope),
              ),
            );
            throw StateError('production_scope_was_replaced');
          } on ScopeSecretException catch (error) {
            if (error.failure != ScopeSecretFailure.alreadyExists) rethrow;
          }
          break;
        case 'cleanup':
          await repository.delete(scope);
          if ((await repository.readExisting(scope)).status !=
              ScopeSecretReadStatus.missing) {
            throw StateError('production_scope_cleanup_failed');
          }
          break;
        default:
          throw StateError('production_scope_restart_phase_invalid');
      }
      status = 'passed';
      code = 'ok';
    } on Object catch (error) {
      code = _safeErrorCode(error);
    }
    await File(_resultPath).writeAsString(
      jsonEncode(<String, String>{
        'case_id': _caseId,
        'phase': _phase,
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
  if (error is ScopeSecretException) return error.failure.name;
  if (error is StateError) {
    final message = error.message;
    if (RegExp(r'^[a-z0-9_]+$').hasMatch(message)) {
      return message;
    }
  }
  return 'production_scope_restart_failed';
}
