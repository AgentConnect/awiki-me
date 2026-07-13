import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../application/config/awiki_environment_config.dart';
import '../application/tenant/app_tenant.dart';
import '../data/tenant/app_tenant_store.dart';
import '../data/storage/scope_secret_repository_factory.dart';
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

  Future<_TenantRuntime> _loadRuntime() async {
    final registry = await _store.loadRegistry();
    return _createRuntime(registry);
  }

  void _startInitialLoad() {
    final generation = ++_runtimeGeneration;
    final future = _loadRuntime();
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

  Future<_TenantRuntime> _createRuntime(AppTenantRegistry registry) async {
    final tenant = registry.activeTenant;
    final bootstrap = await AppBootstrap.create(
      appStateRoot: widget.appStateRoot,
      tenant: tenant,
      environment: AwikiEnvironmentConfig(
        baseUrl: tenant.backendBaseUrl,
        didDomain: tenant.didHost,
        agentImEnabled: tenant.isPrimaryTenant,
      ),
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
    final future = openTenantRuntimeAfterDispose<_TenantRuntime>(
      previous: previous,
      disposePrevious: (runtime) => runtime.bootstrap.dispose(),
      openNext: () => _createRuntime(registry),
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
    final restored = await _createRuntime(previous.registry);
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
            return buildTenantBootstrapErrorApp(snapshot.error);
          }
          return const _TenantBootstrapLoadingApp();
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
  const _TenantBootstrapErrorApp({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final message = error?.toString().trim();
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
                if (message != null && message.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  SelectionArea(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AwikiMePalette.actionMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildTenantBootstrapErrorApp(Object? error) =>
    _TenantBootstrapErrorApp(error: error);

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
  const _TenantBootstrapLoadingApp();

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: AwikiMeTheme.cupertinoTheme,
      home: const CupertinoPageScaffold(
        backgroundColor: AwikiMePalette.ivory,
        child: AwikiAdaptiveScaffold(
          maxWidth: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CupertinoActivityIndicator(radius: 11),
              SizedBox(height: 14),
              Text(
                'AWiki',
                style: TextStyle(
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
