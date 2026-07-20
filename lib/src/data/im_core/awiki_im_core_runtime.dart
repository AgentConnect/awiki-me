// [INPUT]: Owner-scoped IM Core paths, Vault secret provider, endpoints, and default-off capability gates.
// [OUTPUT]: One validated native IM Core runtime and identity-scoped clients.
// [POS]: AWiki Me's lifecycle owner for native Core; it never exposes Vault/root-key material.

import 'dart:async';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/im_core_runtime_port.dart';
import '../../application/tenant/app_tenant.dart';
import 'awiki_im_core_config.dart';
import 'awiki_im_core_paths.dart';
import 'awiki_im_core_secret_storage.dart';

typedef AwikiImCoreOpen =
    Future<core.AwikiImCore> Function({
      required core.AwikiImCoreConfig config,
      required core.AwikiImCorePaths paths,
      core.AwikiImCoreOpenOptions? openOptions,
    });

typedef AwikiImCoreInspectLocalStateUpgrade =
    Future<core.LocalStateUpgradeInspection> Function(
      core.AwikiImCorePaths paths,
    );

typedef AwikiImCoreUpgradeLocalState =
    Future<core.LocalStateUpgradeResult> Function(core.AwikiImCorePaths paths);

enum AwikiImCoreRuntimeProgress { upgradingLocalState }

String? awikiImCoreDiagnosticCode(Object? error) => switch (error) {
  core.AwikiImCoreException(:final code) => code,
  _ => null,
};

class AwikiImCoreRuntime implements ImCoreRuntimePort {
  AwikiImCoreRuntime({
    required AwikiImCoreEnvironmentConfig config,
    required AwikiImCorePathLayout paths,
    required StorageScopeId scopeId,
    required AwikiImCoreVaultSecretProvider vaultSecretProvider,
    this.multiDeviceJoinEnabled = false,
    this.multiDeviceRootTransferEnabled = false,
    this.multiDeviceDeviceRevokeEnabled = false,
    this.multiDeviceHandleRecoveryEnabled = false,
    this.multiDeviceGroupE2eeEnabled = false,
    AwikiImCoreOpen? openCore,
    AwikiImCoreInspectLocalStateUpgrade? inspectLocalStateUpgrade,
    AwikiImCoreUpgradeLocalState? upgradeLocalState,
    void Function(AwikiImCoreRuntimeProgress progress)? onProgress,
  }) : _config = config,
       _paths = paths,
       _scopeId = scopeId,
       _vaultSecretProvider = vaultSecretProvider,
       _openCore = openCore ?? core.AwikiImCore.open,
       _inspectLocalStateUpgrade =
           inspectLocalStateUpgrade ?? _inspectLocalStateUpgradeWithSdk,
       _upgradeLocalState = upgradeLocalState ?? _upgradeLocalStateWithSdk,
       _onProgress = onProgress;

  final AwikiImCoreEnvironmentConfig _config;
  final AwikiImCorePathLayout _paths;
  final StorageScopeId _scopeId;
  final AwikiImCoreVaultSecretProvider _vaultSecretProvider;
  final bool multiDeviceJoinEnabled;
  final bool multiDeviceRootTransferEnabled;
  final bool multiDeviceDeviceRevokeEnabled;
  final bool multiDeviceHandleRecoveryEnabled;
  final bool multiDeviceGroupE2eeEnabled;
  final AwikiImCoreOpen _openCore;
  final AwikiImCoreInspectLocalStateUpgrade _inspectLocalStateUpgrade;
  final AwikiImCoreUpgradeLocalState _upgradeLocalState;
  final void Function(AwikiImCoreRuntimeProgress progress)? _onProgress;

  core.AwikiImCore? _core;
  core.LocalStateUpgradeResult? _localStateUpgradeResult;
  Future<void>? _openInFlight;
  core.AwikiImClient? _currentClient;
  int _activeClientOperations = 0;
  Completer<void>? _clientOperationsIdle;
  Completer<void>? _clientTransition;

  AwikiImCoreEnvironmentConfig get config => _config;

  AwikiImCorePathLayout get paths => _paths;

  core.LocalStateUpgradeResult? get localStateUpgradeResult =>
      _localStateUpgradeResult;

  bool get hasCanonicalOverlayMigrationWork {
    final result = _localStateUpgradeResult;
    return result?.status == core.LocalStateUpgradeStatus.completed ||
        result?.aliasMappings.isNotEmpty == true;
  }

  @override
  bool get isOpen => _core != null;

  @override
  Future<void> open() async {
    if (_core != null) {
      return;
    }
    final inFlight = _openInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final opening = _open();
    _openInFlight = opening;
    return opening.whenComplete(() {
      if (identical(_openInFlight, opening)) {
        _openInFlight = null;
      }
    });
  }

  Future<void> _open() async {
    if (_paths.scopeId != _scopeId) {
      throw const AwikiVaultOpenException('vault_context_mismatch');
    }
    await _paths.scopeLayout.assertSafeExistingScope();
    final vaultSecrets = await _vaultSecretProvider.openExisting(_scopeId);
    await _paths.ensureDirectories();
    await _paths.archiveIncompatibleLocalStateIfNeeded();
    final corePaths = _paths.toCorePaths();
    final inspection = await _inspectLocalStateUpgrade(corePaths);
    if (inspection.eligibility == core.LocalStateUpgradeEligibility.required) {
      _onProgress?.call(AwikiImCoreRuntimeProgress.upgradingLocalState);
    }
    // Run the idempotent entry point even after cutover. Besides performing a
    // required upgrade, it returns the stable alias mapping that lets the App
    // resume its independent overlay migration after a process crash.
    _localStateUpgradeResult = await _upgradeLocalState(corePaths);
    final opened = await _openCore(
      config: _config.toCoreConfig(),
      paths: corePaths,
      openOptions: core.AwikiImCoreOpenOptions.vaultRequired(
        multiDeviceJoinEnabled: multiDeviceJoinEnabled,
        multiDeviceRootTransferEnabled: multiDeviceRootTransferEnabled,
        multiDeviceDeviceRevokeEnabled: multiDeviceDeviceRevokeEnabled,
        multiDeviceHandleRecoveryEnabled: multiDeviceHandleRecoveryEnabled,
        multiDeviceGroupE2eeEnabled: multiDeviceGroupE2eeEnabled,
        identitySecretVault: core.ImCoreSecretVaultOptions(
          rootKey: vaultSecrets.rootKey,
          vaultDir: _paths.vaultDir,
          workspaceId: _paths.vaultWorkspaceId,
          deviceId: _paths.vaultContextDeviceId,
        ),
      ),
    );
    try {
      for (final identity in await opened.listIdentities()) {
        await opened.verifyIdentityVault(core.IdentitySelector.id(identity.id));
      }
    } on Object {
      await opened.dispose();
      rethrow;
    }
    _core = opened;
  }

  Future<void> openAndValidate() async {
    await open();
    await validate();
  }

  @override
  Future<List<String>> validate() async {
    return (await coreInstance()).validatePaths();
  }

  Future<core.AwikiImCore> coreInstance() async {
    final existing = _core;
    if (existing != null) {
      return existing;
    }
    await open();
    return _core!;
  }

  Future<core.AwikiImClient> clientFor(core.IdentitySelector selector) async {
    return (await coreInstance()).client(selector);
  }

  @override
  Future<void> ensureIdentityVault(String identityIdOrAlias) async {
    final coreInstance = await this.coreInstance();
    final selector = _selectorFromString(identityIdOrAlias);
    await coreInstance.verifyIdentityVault(selector);
  }

  Future<core.AwikiImClient> currentClient() async {
    final client = _currentClient;
    if (client == null) {
      throw StateError('IM Core identity is not selected.');
    }
    return client;
  }

  Future<T> withCurrentClient<T>(
    Future<T> Function(core.AwikiImClient client) action,
  ) async {
    while (true) {
      final transition = _clientTransition;
      if (transition == null) {
        break;
      }
      await transition.future;
    }

    final client = _currentClient;
    if (client == null) {
      throw StateError('IM Core identity is not selected.');
    }

    _activeClientOperations += 1;
    try {
      return await action(client);
    } finally {
      _activeClientOperations -= 1;
      if (_activeClientOperations == 0) {
        _clientOperationsIdle?.complete();
        _clientOperationsIdle = null;
      }
    }
  }

  @override
  Future<void> switchIdentity(String identityIdOrAlias) {
    return selectIdentity(_selectorFromString(identityIdOrAlias));
  }

  Future<void> selectIdentity(core.IdentitySelector selector) async {
    final transition = await _beginClientTransition();
    try {
      final nextClient = await clientFor(selector);
      await _waitForClientOperations();
      final previousClient = _currentClient;
      _currentClient = nextClient;
      await previousClient?.dispose();
    } finally {
      _endClientTransition(transition);
    }
  }

  @override
  Future<void> dispose() async {
    final transition = await _beginClientTransition();
    try {
      await _waitForClientOperations();
      final client = _currentClient;
      _currentClient = null;
      final core = _core;
      _core = null;
      _localStateUpgradeResult = null;
      try {
        await client?.dispose();
      } finally {
        await core?.dispose();
      }
    } finally {
      _endClientTransition(transition);
    }
  }

  Future<Completer<void>> _beginClientTransition() async {
    while (true) {
      final currentTransition = _clientTransition;
      if (currentTransition == null) {
        break;
      }
      await currentTransition.future;
    }
    final transition = Completer<void>();
    _clientTransition = transition;
    return transition;
  }

  void _endClientTransition(Completer<void> transition) {
    if (identical(_clientTransition, transition)) {
      _clientTransition = null;
    }
    if (!transition.isCompleted) {
      transition.complete();
    }
  }

  Future<void> _waitForClientOperations() async {
    if (_activeClientOperations == 0) {
      return;
    }
    final idle = _clientOperationsIdle ??= Completer<void>();
    await idle.future;
  }
}

Future<core.LocalStateUpgradeInspection> _inspectLocalStateUpgradeWithSdk(
  core.AwikiImCorePaths paths,
) => core.AwikiImCore.inspectLocalStateUpgrade(paths: paths);

Future<core.LocalStateUpgradeResult> _upgradeLocalStateWithSdk(
  core.AwikiImCorePaths paths,
) => core.AwikiImCore.upgradeLocalState(paths: paths);

core.IdentitySelector _selectorFromString(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'identityIdOrAlias', 'must not be empty');
  }
  if (trimmed == 'default') {
    return const core.IdentitySelector.defaultIdentity();
  }
  if (trimmed.startsWith('did:')) {
    return core.IdentitySelector.did(trimmed);
  }
  if (trimmed.contains('.')) {
    return core.IdentitySelector.handle(trimmed);
  }
  return core.IdentitySelector.id(trimmed);
}
