import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/config/awiki_environment_config.dart';
import '../application/tenant/app_tenant.dart';
import '../data/tenant/app_tenant_store.dart';
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
    _store = AppTenantStore(appStateRoot: widget.appStateRoot);
    _startInitialLoad();
  }

  @override
  void dispose() {
    unawaited(_runtime?.bootstrap.dispose());
    super.dispose();
  }

  Future<_TenantRuntime> _loadRuntime() async {
    final registry = await _store.loadRegistry();
    try {
      return await _createRuntime(registry);
    } catch (_) {
      if (registry.activeTenant.id == defaultTenantId) {
        rethrow;
      }
      final fallback = registry.copyWith(activeTenantId: defaultTenantId);
      await _store.saveRegistry(fallback);
      return _createRuntime(fallback);
    }
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
        stateNamespace: tenant.stateNamespace,
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
    final future = _createRuntime(registry);
    setState(() {
      _runtimeFuture = future;
    });
    late final _TenantRuntime next;
    try {
      next = await future;
    } catch (_) {
      if (mounted &&
          generation == _runtimeGeneration &&
          identical(_runtimeFuture, future) &&
          previous != null) {
        setState(() {
          _runtimeFuture = Future<_TenantRuntime>.value(previous);
        });
      }
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
      if (mounted &&
          generation == _runtimeGeneration &&
          identical(_runtimeFuture, future) &&
          previous != null) {
        setState(() {
          _runtimeFuture = Future<_TenantRuntime>.value(previous);
        });
      }
      rethrow;
    }
    setState(() {
      _runtime = next;
    });
    await previous?.bootstrap.dispose();
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
    final registry = await _store.updateTenant(input);
    final current = _runtime;
    if (current != null &&
        registry.activeTenant.id == current.registry.activeTenant.id) {
      await _replaceRuntime(registry);
      return registry;
    }
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
            return _TenantBootstrapErrorApp(error: snapshot.error);
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
                  'AWiki failed to start.',
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
