import '../services/desktop_network_preference.dart';
// [INPUT]: Owner-scoped IM Core paths, Vault secret provider, endpoints, and optional capability gates.
// [OUTPUT]: One validated native IM Core runtime and identity-scoped clients.
// [POS]: AWiki Me's lifecycle owner for native Core; Handle Recovery is a product baseline.

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
    this.multiDeviceDeviceRevokeEnabled = true,
    this.multiDeviceDirectE2eeEnabled = true,
    this.multiDeviceGroupE2eeEnabled = true,
    String? multiDeviceAudience,
    AwikiImCoreOpen? openCore,
    AwikiImCoreInspectLocalStateUpgrade? inspectLocalStateUpgrade,
    AwikiImCoreUpgradeLocalState? upgradeLocalState,
    void Function(AwikiImCoreRuntimeProgress progress)? onProgress,
  }) : _config = config,
       _paths = paths,
       _scopeId = scopeId,
       _vaultSecretProvider = vaultSecretProvider,
       multiDeviceAudience = _validatedMultiDeviceAudience(multiDeviceAudience),
       _usesNativeCore = openCore == null,
       _openCore = openCore ?? core.AwikiImCore.open,
       _inspectLocalStateUpgrade =
           inspectLocalStateUpgrade ?? _inspectLocalStateUpgradeWithSdk,
       _upgradeLocalState = upgradeLocalState ?? _upgradeLocalStateWithSdk,
       _onProgress = onProgress;

  final AwikiImCoreEnvironmentConfig _config;
  final AwikiImCorePathLayout _paths;
  final StorageScopeId _scopeId;
  final AwikiImCoreVaultSecretProvider _vaultSecretProvider;
  final bool multiDeviceDeviceRevokeEnabled;
  final bool multiDeviceDirectE2eeEnabled;
  final bool multiDeviceGroupE2eeEnabled;
  final String multiDeviceAudience;
  final AwikiImCoreOpen _openCore;
  final bool _usesNativeCore;
  final AwikiImCoreInspectLocalStateUpgrade _inspectLocalStateUpgrade;
  final AwikiImCoreUpgradeLocalState _upgradeLocalState;
  final void Function(AwikiImCoreRuntimeProgress progress)? _onProgress;

  bool _disposed = false;
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
    _ensureNotDisposed();
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
    if (_usesNativeCore && supportsDesktopNetwork) {
      await DesktopNetworkPreference.instance.initialize();
    }
    final opened = await _openCore(
      config: _config.toCoreConfig(),
      paths: corePaths,
      openOptions: core.AwikiImCoreOpenOptions.vaultRequired(
        multiDeviceDeviceRevokeEnabled: multiDeviceDeviceRevokeEnabled,
        multiDeviceDirectE2eeEnabled: multiDeviceDirectE2eeEnabled,
        multiDeviceGroupE2eeEnabled: multiDeviceGroupE2eeEnabled,
        multiDeviceHandleRecoveryEnabled: true,
        multiDeviceAudience: multiDeviceAudience,
        identitySecretVault: core.ImCoreSecretVaultOptions(
          rootKey: vaultSecrets.rootKey,
          vaultDir: _paths.vaultDir,
          workspaceId: _paths.vaultWorkspaceId,
          deviceId: _paths.vaultContextDeviceId,
        ),
      ),
    );
    try {
      await _verifyStartupIdentityCustody(opened);
    } on Object {
      await opened.dispose();
      rethrow;
    }
    if (_disposed) {
      await opened.dispose();
      _ensureNotDisposed();
    }
    _core = opened;
  }

  Future<Map<String, dynamic>> backendCapabilities({bool force = false}) async {
    final instance = await coreInstance();
    final client = _currentClient;
    final sources = <String, dynamic>{};
    Object? authenticationError;
    Future<void> read(
      String name,
      Future<Map<String, dynamic>> Function() refresh,
      Future<Map<String, dynamic>> Function() snapshot,
    ) async {
      try {
        sources[name] = await refresh();
      } on core.AwikiImCoreException catch (error) {
        sources[name] = await snapshot();
        if (const [
          'auth_required',
          'session_expired',
          'permission_denied',
        ].contains(error.code)) {
          authenticationError = error;
        }
      }
    }

    await Future.wait([
      read(
        'public',
        () => instance.backendCapabilities(force: force),
        instance.backendCapabilitiesSnapshot,
      ),
      if (client != null)
        read(
          'message',
          () => client.backendCapabilities(force: force),
          client.backendCapabilitiesSnapshot,
        ),
    ]);
    _ensureNotDisposed();
    if (!identical(client, _currentClient)) {
      throw StateError('capability_context_changed');
    }
    if (authenticationError != null) throw authenticationError!;
    return sources;
  }

  Stream<Map<String, dynamic>> watchBackendCapabilities() {
    late StreamController<Map<String, dynamic>> controller;
    final subscriptions = <StreamSubscription<Map<String, dynamic>>>[];
    final sources = <String, dynamic>{};
    Timer? timer;
    var cancelled = false;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () async {
        try {
          final instance = await coreInstance();
          final client = _currentClient;
          bool current() =>
              !cancelled && !_disposed && identical(client, _currentClient);
          void publish() {
            if (current()) controller.add(Map.of(sources));
          }

          void observe(String name, Stream<Map<String, dynamic>> stream) {
            subscriptions.add(
              stream.listen(
                (state) {
                  if (!current()) return;
                  sources[name] = state['snapshot'];
                  sources['${name}_diagnostics'] = {
                    'refresh_error': state['refresh_error'],
                    'persistence_failed': state['persistence_failed'],
                  };
                  publish();
                },
                onError: (Object error, StackTrace stack) {
                  if (current()) controller.addError(error, stack);
                },
              ),
            );
          }

          // Native subscriptions emit their current state first, closing the gap
          // after restoration without letting an older read overwrite an update.
          if (!current()) return;
          sources['public'] = await instance.backendCapabilitiesSnapshot();
          if (client != null) {
            sources['message'] = await client.backendCapabilitiesSnapshot();
          }
          publish();
          if (!current()) return;
          observe('public', instance.watchBackendCapabilities());
          if (client != null) {
            observe('message', client.watchBackendCapabilities());
          }
          Future<void> refresh() async {
            if (!current()) return;
            // Core keeps each source's successful state and publishes auth failures.
            await Future.wait([
              instance.backendCapabilities().then<void>(
                (_) {},
                onError: (Object _) {},
              ),
              if (client != null)
                client.backendCapabilities().then<void>(
                  (_) {},
                  onError: (Object _) {},
                ),
            ]);
          }

          if (!current()) return;
          unawaited(refresh());
          timer = Timer.periodic(
            const Duration(seconds: 10),
            (_) => unawaited(refresh()),
          );
        } catch (error, stack) {
          if (!cancelled && !_disposed) controller.addError(error, stack);
        }
      },
      onCancel: () async {
        cancelled = true;
        timer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
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
    _ensureNotDisposed();
    final existing = _core;
    if (existing != null) {
      return existing;
    }
    await open();
    _ensureNotDisposed();
    return _core!;
  }

  Future<core.AwikiImClient> clientFor(core.IdentitySelector selector) async {
    return (await coreInstance()).client(selector);
  }

  @override
  Future<void> ensureIdentityVault(String identityIdOrAlias) async {
    final coreInstance = await this.coreInstance();
    final selector = _selectorFromString(identityIdOrAlias);
    await _ensureIdentityCustodyReady(coreInstance, selector);
  }

  Future<core.AwikiImClient> currentClient() async {
    _ensureNotDisposed();
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

    _ensureNotDisposed();
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
      if (_disposed) {
        await nextClient.dispose();
        _ensureNotDisposed();
      }
      final previousClient = _currentClient;
      _currentClient = nextClient;
      await previousClient?.dispose();
    } finally {
      _endClientTransition(transition);
    }
  }

  @override
  Future<void> clearIdentity() async {
    final transition = await _beginClientTransition();
    try {
      await _waitForClientOperations();
      final client = _currentClient;
      _currentClient = null;
      await client?.dispose();
    } finally {
      _endClientTransition(transition);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    // Opening owns any partially-created native instance and closes it when
    // it observes disposal. A stale adapter must never reopen this runtime.
    try {
      await _openInFlight;
    } catch (_) {
      // Preserve disposal even when the in-flight open failed.
    }
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

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('im_core_runtime_disposed');
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

Future<void> _verifyStartupIdentityCustody(core.AwikiImCore instance) async {
  final List<core.IdentitySummary> identities;
  try {
    identities = await instance.listIdentities();
  } on core.AwikiImCoreException catch (error) {
    if (error.code == 'service_error' &&
        error.serviceCode == 'identity.local_registry_conflict') {
      // Keep the already-open, vault-validated Core available for its scoped
      // Recovery inspect/resume APIs. Ordinary identity reads and activation
      // still fail closed in Core until it resolves the conflicting registry.
      // Do not make a recoverable old-client index block the onboarding route.
      return;
    }
    rethrow;
  }
  for (final identity in identities) {
    // Custody failures remain fatal, including errors with the same service
    // code. Only registry enumeration above may defer this startup check.
    await _ensureIdentityCustodyReady(
      instance,
      core.IdentitySelector.id(identity.id),
    );
  }
}

Future<void> _ensureIdentityCustodyReady(
  core.AwikiImCore instance,
  core.IdentitySelector selector,
) async {
  final status = await instance.identityCustodyStatus(selector);
  if (status.backend != core.IdentityCustodyBackend.anpIdentity ||
      status.state != core.IdentityCustodyState.active ||
      !status.ready) {
    throw const core.AwikiImCoreException(
      code: 'identity_custody_unavailable',
      message: 'ANP Identity custody is not ready.',
    );
  }
  final device = await instance.identityDeviceSummary(selector);
  if (device.readiness != core.IdentityDeviceReadiness.memberReady &&
      device.readiness != core.IdentityDeviceReadiness.adminAwaitingRoot &&
      device.readiness != core.IdentityDeviceReadiness.adminReady) {
    throw const core.AwikiImCoreException(
      code: 'identity_custody_unavailable',
      message: 'ANP Identity device custody is not ready.',
    );
  }
}

String _validatedMultiDeviceAudience(String? value) {
  if (value == null || value.isEmpty) {
    throw ArgumentError.value(
      value,
      'multiDeviceAudience',
      'must be configured for baseline Handle Recovery',
    );
  }
  if (value.trim() != value || value.runes.length > 255) {
    throw ArgumentError.value(
      value,
      'multiDeviceAudience',
      'must have no surrounding whitespace and be at most 255 characters',
    );
  }
  return value;
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
