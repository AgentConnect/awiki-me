import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/config/awiki_environment_config.dart';
import '../application/tenant/app_tenant.dart';
import '../data/tenant/app_tenant_store.dart';
import '../data/storage/scope_secret_repository_factory.dart';
import '../data/im_core/awiki_im_core_runtime.dart';
import '../data/im_core/awiki_im_core_secret_storage.dart';
import '../data/im_core/storage_scope_im_core_validator.dart';
import '../presentation/shared/awiki_me_design.dart';
import '../presentation/shared/responsive_layout.dart';
import 'app_locale.dart';
import 'awiki_me_app.dart';
import 'bootstrap.dart';

class TenantAwareAwikiMeApp extends StatefulWidget {
  const TenantAwareAwikiMeApp({super.key, this.appStateRoot});

  final String? appStateRoot;

  @override
  State<TenantAwareAwikiMeApp> createState() => _TenantAwareAwikiMeAppState();
}

class _TenantAwareAwikiMeAppState extends State<TenantAwareAwikiMeApp>
    implements AppTenantActions {
  late final AppTenantStore _store;
  Future<_TenantRuntime>? _runtimeFuture;
  _TenantRuntime? _runtime;
  int _runtimeGeneration = 0;
  AppBootstrapProgress _bootstrapProgress = AppBootstrapProgress.preparing;

  @override
  void initState() {
    super.initState();
    final scopeSecrets = buildScopeSecretRepository(
      appStateRoot: widget.appStateRoot,
    );
    _store = AppTenantStore(
      appStateRoot: widget.appStateRoot,
      secretRepository: scopeSecrets,
      readyValidator: StorageScopeImCoreValidator(
        repository: scopeSecrets,
      ).call,
    );
    _startInitialLoad();
  }

  @override
  void dispose() {
    unawaited(_runtime?.bootstrap.dispose());
    super.dispose();
  }

  Future<_TenantRuntime> _loadRuntime(int generation) async {
    final registry = await _store.loadRegistry();
    return _createRuntime(registry, generation: generation);
  }

  void _startInitialLoad() {
    final generation = ++_runtimeGeneration;
    _bootstrapProgress = AppBootstrapProgress.preparing;
    final future = _loadRuntime(generation);
    _runtimeFuture = future;
    unawaited(
      future.then((runtime) async {
        if (!mounted ||
            generation != _runtimeGeneration ||
            !identical(_runtimeFuture, future)) {
          await runtime.bootstrap.dispose();
          return;
        }
        setState(() {
          _runtime = runtime;
        });
      }),
    );
  }

  Future<_TenantRuntime> _createRuntime(
    AppTenantRegistry registry, {
    required int generation,
  }) async {
    final tenant = registry.activeTenant;
    final bootstrap = await AppBootstrap.create(
      appStateRoot: widget.appStateRoot,
      tenant: tenant,
      environment: AwikiEnvironmentConfig(
        baseUrl: tenant.backendBaseUrl,
        didDomain: tenant.didHost,
      ),
      onProgress: (progress) {
        if (!mounted || generation != _runtimeGeneration) return;
        setState(() => _bootstrapProgress = progress);
      },
    );
    final localeMode = await bootstrap.localePreferenceService.loadMode();
    return _TenantRuntime(
      registry: registry,
      bootstrap: bootstrap,
      localeMode: localeMode,
    );
  }

  Future<void> _replaceRuntime(
    AppTenantRegistry registry, {
    Future<void> Function()? beforeActivate,
  }) async {
    final previous = _runtime;
    final generation = ++_runtimeGeneration;
    _bootstrapProgress = AppBootstrapProgress.preparing;
    final future = openTenantRuntimeAfterDispose<_TenantRuntime>(
      previous: previous,
      disposePrevious: (runtime) => runtime.bootstrap.dispose(),
      openNext: () => _createRuntime(registry, generation: generation),
    );
    setState(() {
      _runtime = null;
      _runtimeFuture = future;
    });
    late final _TenantRuntime next;
    try {
      next = await future;
    } catch (_) {
      await _restorePreviousRuntime(previous, generation, future);
      rethrow;
    }
    if (!mounted) {
      await next.bootstrap.dispose();
      return;
    }
    if (generation != _runtimeGeneration ||
        !identical(_runtimeFuture, future)) {
      await next.bootstrap.dispose();
      return;
    }
    try {
      await beforeActivate?.call();
    } catch (_) {
      await next.bootstrap.dispose();
      await _restorePreviousRuntime(previous, generation, future);
      rethrow;
    }
    setState(() {
      _runtime = next;
    });
  }

  Future<void> _restorePreviousRuntime(
    _TenantRuntime? previous,
    int generation,
    Future<_TenantRuntime> failedFuture,
  ) async {
    if (previous == null ||
        !mounted ||
        generation != _runtimeGeneration ||
        !identical(_runtimeFuture, failedFuture)) {
      return;
    }
    final restored = await _createRuntime(
      previous.registry,
      generation: generation,
    );
    if (!mounted || generation != _runtimeGeneration) {
      await restored.bootstrap.dispose();
      return;
    }
    setState(() {
      _runtime = restored;
      _runtimeFuture = Future<_TenantRuntime>.value(restored);
    });
  }

  @override
  Future<AppTenantRegistry> createTenant(AppTenantCreateInput input) async {
    final registry = await _store.createTenant(input);
    if (!mounted) {
      return registry;
    }
    setState(() {
      _runtime = _runtime?.copyWith(registry: registry);
    });
    return registry;
  }

  @override
  Future<AppTenantRegistry> useTenant(String tenantId) async {
    final registry = await _store.prepareUseTenant(tenantId);
    await _replaceRuntime(
      registry,
      beforeActivate: () => _store.saveRegistry(registry),
    );
    return registry;
  }

  @override
  Future<AppTenantRegistry> updateTenant(AppTenantUpdateInput input) async {
    final registry = await _store.prepareUpdateTenant(input);
    final current = _runtime;
    if (current != null &&
        registry.activeTenant.id == current.registry.activeTenant.id) {
      await _replaceRuntime(
        registry,
        beforeActivate: () => _store.saveRegistry(
          registry,
          expectedRevision: registry.revision - 1,
        ),
      );
      return registry;
    }
    await _store.saveRegistry(
      registry,
      expectedRevision: registry.revision - 1,
    );
    if (!mounted) {
      return registry;
    }
    setState(() {
      _runtime = _runtime?.copyWith(registry: registry);
    });
    return registry;
  }

  @override
  Future<AppTenantRegistry> deleteTenant(String tenantId) async {
    final registry = await _store.deleteTenant(tenantId);
    if (!mounted) {
      return registry;
    }
    setState(() {
      _runtime = _runtime?.copyWith(registry: registry);
    });
    return registry;
  }

  @override
  Future<bool> tenantHasData(String tenantId) => _store.tenantHasData(tenantId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TenantRuntime>(
      future: _runtimeFuture,
      builder: (context, snapshot) {
        final runtime = _runtime ?? snapshot.data;
        if (runtime == null) {
          if (snapshot.hasError) {
            return buildTenantBootstrapErrorApp(
              snapshot.error,
              onRetry: () => setState(_startInitialLoad),
            );
          }
          return _TenantBootstrapLoadingApp(progress: _bootstrapProgress);
        }
        return AwikiMeApp(
          key: ValueKey<String>(runtime.registry.activeTenant.id),
          bootstrap: runtime.bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => runtime.localeMode),
            appTenantRegistryProvider.overrideWithValue(runtime.registry),
            activeAppTenantProvider.overrideWithValue(
              runtime.registry.activeTenant,
            ),
            appTenantActionsProvider.overrideWithValue(this),
          ],
        );
      },
    );
  }
}

class _TenantBootstrapErrorApp extends StatelessWidget {
  const _TenantBootstrapErrorApp({
    required this.error,
    this.onRetry,
    this.onExit,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final diagnosticCode = tenantBootstrapDiagnosticCode(error);
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: AwikiMeTheme.cupertinoTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CupertinoPageScaffold(
        backgroundColor: AwikiMePalette.ivory,
        child: AwikiAdaptiveScaffold(
          maxWidth: 420,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'AWikiMe failed to start.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AwikiMePalette.actionInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SelectionArea(
                  child: Text(
                    'Diagnostic code: $diagnosticCode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AwikiMePalette.actionMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    CupertinoButton(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: diagnosticCode),
                      ),
                      child: const Text('Copy diagnostics'),
                    ),
                    CupertinoButton(
                      onPressed: onExit ?? SystemNavigator.pop,
                      child: const Text('Exit'),
                    ),
                    if (onRetry != null)
                      CupertinoButton.filled(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildTenantBootstrapErrorApp(
  Object? error, {
  VoidCallback? onRetry,
  VoidCallback? onExit,
}) => _TenantBootstrapErrorApp(error: error, onRetry: onRetry, onExit: onExit);

@visibleForTesting
String tenantBootstrapDiagnosticCode(Object? error) {
  final code =
      awikiImCoreDiagnosticCode(error) ??
      switch (error) {
        AwikiVaultOpenException(:final code) => code,
        FormatException() => 'bootstrap_configuration_invalid',
        _ => 'bootstrap_failed',
      };
  return RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(code)
      ? code
      : 'bootstrap_failed';
}

Future<T> openTenantRuntimeAfterDispose<T>({
  required T? previous,
  required Future<void> Function(T previous) disposePrevious,
  required Future<T> Function() openNext,
}) async {
  if (previous != null) await disposePrevious(previous);
  return openNext();
}

class _TenantRuntime {
  const _TenantRuntime({
    required this.registry,
    required this.bootstrap,
    required this.localeMode,
  });

  final AppTenantRegistry registry;
  final AppBootstrap bootstrap;
  final AppLocaleMode localeMode;

  _TenantRuntime copyWith({AppTenantRegistry? registry}) {
    return _TenantRuntime(
      registry: registry ?? this.registry,
      bootstrap: bootstrap,
      localeMode: localeMode,
    );
  }
}

class _TenantBootstrapLoadingApp extends StatelessWidget {
  const _TenantBootstrapLoadingApp({required this.progress});

  final AppBootstrapProgress progress;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: AwikiMeTheme.cupertinoTheme,
      home: CupertinoPageScaffold(
        backgroundColor: AwikiMePalette.ivory,
        child: AwikiAdaptiveScaffold(
          maxWidth: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CupertinoActivityIndicator(radius: 11),
              const SizedBox(height: 14),
              Text(
                progress == AppBootstrapProgress.upgradingLocalState
                    ? 'Upgrading local data securely…'
                    : progress == AppBootstrapProgress.migratingLocalOverlays
                    ? 'Finishing local data upgrade…'
                    : 'AWiki',
                style: const TextStyle(
                  color: AwikiMePalette.actionInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildTenantBootstrapLoadingApp(AppBootstrapProgress progress) =>
    _TenantBootstrapLoadingApp(progress: progress);
