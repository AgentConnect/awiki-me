import 'dart:io';

import 'awiki_storage_roots.dart';
import 'file_scope_secret_repository.dart';
import 'platform_scope_secret_repository.dart';
import 'scope_secret_repository.dart';

ScopeSecretRepository buildScopeSecretRepository({String? appStateRoot}) {
  if (!awikiE2eEnabledForBuild()) {
    return PlatformScopeSecretRepository.forCurrentBuild();
  }
  final explicitRoot = explicitAwikiAppStateRoot(appStateRoot);
  if (explicitRoot == null) {
    throw StateError('e2e_scope_secret_root_missing');
  }
  return E2eFileScopeSecretRepository(
    root: Directory(
      joinAwikiPath(explicitRoot, const <String>[
        'support',
        'awiki-me',
        'e2e-scope-secrets',
      ]),
    ),
  );
}
