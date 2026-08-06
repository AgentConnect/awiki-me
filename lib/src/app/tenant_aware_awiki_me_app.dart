import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/config/awiki_environment_config.dart';
import '../application/desktop_shell_service.dart';
import '../application/desktop_startup_presentation_service.dart';
import '../application/tenant/app_tenant.dart';
import '../data/tenant/app_tenant_store.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/method_channel_desktop_shell_service.dart';
import '../data/services/method_channel_desktop_startup_presentation_service.dart';
import '../data/storage/scope_secret_repository_factory.dart';
import '../data/im_core/awiki_im_core_runtime.dart';
import '../data/im_core/awiki_im_core_secret_storage.dart';
import '../data/im_core/storage_scope_im_core_validator.dart';
import '../data/push/remote_push_client_factory.dart';
import '../domain/services/remote_push_client.dart';
import '../presentation/shared/awiki_me_design.dart';
import '../presentation/shared/desktop_startup_ready_boundary.dart';
import '../presentation/shared/responsive_layout.dart';
import '../presentation/shared/startup_splash.dart';
import 'app_locale.dart';
import 'app_services.dart';
import 'awiki_me_app.dart';
import 'bootstrap.dart';

class TenantAwareAwikiMeApp extends StatefulWidget {
  const TenantAwareAwikiMeApp({
    super.key,
    this.appStateRoot,
    this.desktopShellService,
    this.desktopStartupPresentationService,
    this.remotePushClient,
  });

  final String? appStateRoot;
  final DesktopShellService? desktopShellService;
  final DesktopStartupPresentationService? desktopStartupPresentationService;
  final RemotePushClient? remotePushClient;

  @override
  State<TenantAwareAwikiMeApp> createState() => _TenantAwareAwikiMeAppState();
}

class _TenantAwareAwikiMeAppState extends State<TenantAwareAwikiMeApp>
    with WidgetsBindingObserver
    implements AppTenantActions {
  late final AppTenantStore _store;
  late final DesktopShellService _desktopShell;
  late final DesktopStartupPresentationService _desktopStartupPresentation;
  late final DesktopShellLifecycleCoordinator _shellLifecycle;
  late final StreamSubscription<DesktopShellEvent> _shellSubscription;
  late final Future<void> _shellReady;
  late final Future<AppNotificationFacade> _notificationFacadeReady;
  late final RemotePushClient _remotePushClient;
  Future<void>? _remotePushInitialization;
  Future<_TenantRuntime>? _runtimeFuture;
  Future<void>? _runtimeDisposeOperation;
  _TenantRuntime? _runtime;
  int _runtimeGeneration = 0;
  AppBootstrapProgress _bootstrapProgress = AppBootstrapProgress.preparing;
  bool _shutdownRequested = false;

  @override
  void initState() {
    super.initState();
    _desktopShell =
        widget.desktopShellService ??
        (Platform.isWindows
            ? MethodChannelDesktopShellService()
            : const NoopDesktopShellService());
    _desktopStartupPresentation =
        widget.desktopStartupPresentationService ??
        buildDesktopStartupPresentationService();
    _shellLifecycle = DesktopShellLifecycleCoordinator(
      shell: _desktopShell,
      onExitIssue: (issue) {
        debugPrint('[awiki_me][desktop-exit] issue=${issue.name}');
      },
    );
    _shellSubscription = _desktopShell.events.listen(_handleShellEvent);
    _shellReady = _desktopShell.initialize();
    _notificationFacadeReady = AppNotificationFacade.create(
      desktopShell: _desktopShell,
    );
    WidgetsBinding.instance.addObserver(this);
    _remotePushClient = widget.remotePushClient ?? buildRemotePushClient();
    _startRemotePushInitialization();
    final scopeSecrets = buildScopeSecretRepository(
      appStateRoot: widget.appStateRoot,
    );
    _store = AppTenantStore(
      appStateRoot: widget.appStateRoot,
      secretRepository: scopeSecrets,
      readyValidator: StorageScopeImCoreValidator(
        repository: scopeSecrets,
      ).call,
      platformStorageRoots: _desktopShell.getStorageRoots,
    );
    _startInitialLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _disposeAfterWidgetRemoval().catchError((Object _, StackTrace __) {}),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _remotePushClient.registration == null) {
      _startRemotePushInitialization();
    }
  }

  void _startRemotePushInitialization() {
    if (_remotePushClient.registration != null ||
        _remotePushInitialization != null) {
      return;
    }
    final initialization = _initializeRemotePush();
    _remotePushInitialization = initialization;
    unawaited(
      initialization.whenComplete(() {
        if (identical(_remotePushInitialization, initialization)) {
          _remotePushInitialization = null;
        }
      }),
    );
  }

  Future<void> _initializeRemotePush() async {
    if (!mounted) return;
    try {
      final registration = await _remotePushClient.initialize();
      if (registration != null && kDebugMode) {
        final deviceId = registration.providerDeviceId;
        final suffix = deviceId.length <= 6
            ? deviceId
            : deviceId.substring(deviceId.length - 6);
        debugPrint(
          '[awiki_me][remote-push] provider=${registration.provider} '
          'device_id_suffix=$suffix',
        );
      }
    } catch (error) {
      debugPrint('[awiki_me][remote-push][error] $error');
    }
  }

  Future<_TenantRuntime> _loadRuntime(int generation) async {
    await _shellReady;
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
          if (!_shutdownRequested) {
            await runtime.bootstrap.dispose();
          }
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
    final notificationFacade = await _notificationFacadeReady;
    final bootstrap = await AppBootstrap.create(
      appStateRoot: widget.appStateRoot,
      desktopShellService: _desktopShell,
      notificationFacade: notificationFacade,
      remotePushClient: _remotePushClient,
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
    final displayScale = await bootstrap.displayScalePreferenceService
        .loadScale();
    return _TenantRuntime(
      registry: registry,
      bootstrap: bootstrap,
      localeMode: localeMode,
      displayScale: displayScale,
    );
  }

  void _handleShellEvent(DesktopShellEvent event) {
    unawaited(
      _shellLifecycle
          .handle(event, disposeRuntime: _disposeRuntimeForExit)
          .catchError((Object _, StackTrace __) {}),
    );
  }

  Future<void> _disposeAfterWidgetRemoval() async {
    await _shellSubscription.cancel();
    try {
      await _disposeRuntimeForExit();
    } finally {
      try {
        await _desktopShell.dispose();
      } finally {
        await _remotePushClient.dispose();
      }
    }
  }

  Future<void> _disposeRuntimeForExit() {
    return _runtimeDisposeOperation ??= _performRuntimeDisposeForExit();
  }

  Future<void> _performRuntimeDisposeForExit() async {
    if (_shutdownRequested && _runtime == null && _runtimeFuture == null) {
      return;
    }
    _shutdownRequested = true;
    _runtimeGeneration += 1;
    final current = _runtime;
    final pending = _runtimeFuture;
    if (mounted) {
      setState(() {
        _runtime = null;
        _runtimeFuture = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _runtime = null;
      _runtimeFuture = null;
    }
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> disposeStep(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (current != null) {
      await disposeStep(current.bootstrap.dispose);
    } else if (pending != null) {
      await disposeStep(() async {
        final runtime = await pending;
        await runtime.bootstrap.dispose();
      });
    }
    await disposeStep(() async {
      final notificationFacade = await _notificationFacadeReady;
      await notificationFacade.dispose();
    });

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
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
              startupPresentationService: _desktopStartupPresentation,
            );
          }
          return _TenantBootstrapLoadingApp(progress: _bootstrapProgress);
        }
        return AwikiMeApp(
          key: ValueKey<String>(runtime.registry.activeTenant.id),
          bootstrap: runtime.bootstrap,
          initialDisplayScale: runtime.displayScale,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => runtime.localeMode),
            appTenantRegistryProvider.overrideWithValue(runtime.registry),
            activeAppTenantProvider.overrideWithValue(
              runtime.registry.activeTenant,
            ),
            appTenantActionsProvider.overrideWithValue(this),
            desktopStartupPresentationServiceProvider.overrideWithValue(
              _desktopStartupPresentation,
            ),
          ],
        );
      },
    );
  }
}

class _TenantBootstrapErrorApp extends StatelessWidget {
  const _TenantBootstrapErrorApp({
    required this.error,
    required this.startupPresentationService,
    this.onRetry,
    this.onExit,
  });

  final Object? error;
  final DesktopStartupPresentationService startupPresentationService;
  final VoidCallback? onRetry;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final diagnosticCode = tenantBootstrapDiagnosticCode(error);
    final appTheme = AwikiMeTheme.current;
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme.cupertinoTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DesktopStartupReadyBoundary(
        presentationService: startupPresentationService,
        child: CupertinoPageScaffold(
          backgroundColor: AwikiMePalette.canvas,
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
      ),
    );
  }
}

@visibleForTesting
Widget buildTenantBootstrapErrorApp(
  Object? error, {
  VoidCallback? onRetry,
  VoidCallback? onExit,
  DesktopStartupPresentationService startupPresentationService =
      const NoopDesktopStartupPresentationService(),
}) => _TenantBootstrapErrorApp(
  error: error,
  startupPresentationService: startupPresentationService,
  onRetry: onRetry,
  onExit: onExit,
);

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
    required this.displayScale,
  });

  final AppTenantRegistry registry;
  final AppBootstrap bootstrap;
  final AppLocaleMode localeMode;
  final double displayScale;

  _TenantRuntime copyWith({AppTenantRegistry? registry}) {
    return _TenantRuntime(
      registry: registry ?? this.registry,
      bootstrap: bootstrap,
      localeMode: localeMode,
      displayScale: displayScale,
    );
  }
}

class _TenantBootstrapLoadingApp extends StatelessWidget {
  const _TenantBootstrapLoadingApp({required this.progress});

  final AppBootstrapProgress progress;

  @override
  Widget build(BuildContext context) {
    final appTheme = AwikiMeTheme.current;
    final statusLabel = switch (progress) {
      AppBootstrapProgress.preparing ||
      AppBootstrapProgress.startingApplication => null,
      AppBootstrapProgress.upgradingLocalState =>
        'Upgrading local data securely…',
      AppBootstrapProgress.migratingLocalOverlays =>
        'Finishing local data upgrade…',
    };
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme.cupertinoTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AwikiMeStartupPlaceholder(statusLabel: statusLabel),
    );
  }
}

@visibleForTesting
Widget buildTenantBootstrapLoadingApp(AppBootstrapProgress progress) =>
    _TenantBootstrapLoadingApp(progress: progress);
