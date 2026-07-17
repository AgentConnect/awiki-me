import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' as material;

import '../application/agent/agent_control_service.dart';
import '../application/auth/auth_session_coordinator.dart';
import '../application/conversation_service.dart';
import '../application/models/app_session.dart';
import '../data/agent/user_service_agent_inventory_adapter.dart';
import '../data/agent/user_service_personal_agent_binding_adapter.dart';
import '../data/services/authenticated_user_service_rpc_client.dart';
import '../presentation/app_shell/app_shell.dart';
import '../presentation/app_shell/providers/app_lifecycle_provider.dart';
import '../presentation/app_shell/providers/session_provider.dart';
import '../presentation/agents/agents_provider.dart';
import '../presentation/chat/chat_provider.dart';
import '../presentation/shared/awiki_me_design.dart';
import '../presentation/shared/display_scale.dart';
import 'app_orientation.dart';
import 'app_locale.dart';
import 'app_services.dart';
import 'bootstrap.dart';

class AwikiMeApp extends StatelessWidget {
  const AwikiMeApp({
    super.key,
    required this.bootstrap,
    this.providerOverrides = const <Override>[],
  });

  final AppBootstrap bootstrap;
  final List<Override> providerOverrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: <Override>[
        awikiEnvironmentConfigProvider.overrideWithValue(bootstrap.environment),
        awikiAccountGatewayProvider.overrideWithValue(bootstrap.accountGateway),
        awikiGatewayProvider.overrideWithValue(bootstrap.gateway),
        realtimeGatewayProvider.overrideWithValue(bootstrap.realtimeGateway),
        notificationFacadeProvider.overrideWithValue(
          bootstrap.notificationFacade,
        ),
        e2eeFacadeProvider.overrideWithValue(bootstrap.e2eeFacade),
        localePreferenceServiceProvider.overrideWithValue(
          bootstrap.localePreferenceService,
        ),
        updateServiceProvider.overrideWithValue(bootstrap.updateService),
        if (bootstrap.attachmentCacheService != null)
          attachmentCacheServiceProvider.overrideWithValue(
            bootstrap.attachmentCacheService!,
          ),
        if (bootstrap.appSessionService != null)
          appSessionServiceProvider.overrideWithValue(
            bootstrap.appSessionService!,
          ),
        if (bootstrap.identityCorePort != null)
          identityCorePortProvider.overrideWithValue(
            bootstrap.identityCorePort!,
          ),
        if (bootstrap.onboardingService != null)
          onboardingServiceProvider.overrideWithValue(
            bootstrap.onboardingService!,
          ),
        if (bootstrap.onboardingSupportService != null)
          onboardingSupportServiceProvider.overrideWithValue(
            bootstrap.onboardingSupportService!,
          ),
        if (bootstrap.messagingService != null)
          messagingServiceProvider.overrideWithValue(
            bootstrap.messagingService!,
          ),
        if (bootstrap.messageSyncService != null)
          messageSyncServiceProvider.overrideWithValue(
            bootstrap.messageSyncService!,
          ),
        if (bootstrap.agentInventoryPort != null)
          agentInventoryPortProvider.overrideWith((ref) {
            final inventory = bootstrap.agentInventoryPort!;
            if (inventory is UserServiceAgentInventoryAdapter &&
                bootstrap.appSessionService != null) {
              final sessions = ref.read(appSessionServiceProvider);
              final coordinator = AuthSessionCoordinator(
                sessions: sessions,
                onSessionUpdated: (session) {
                  ref
                      .read(sessionProvider.notifier)
                      .setSession(session.toLegacySessionIdentity());
                },
              );
              return inventory.withAuthenticatedClient(
                AuthenticatedUserServiceRpcClient(
                  client: inventory.httpClient,
                  sessions: coordinator,
                ),
              );
            }
            return inventory;
          }),
        if (bootstrap.personalAgentBindingPort != null)
          personalAgentBindingPortProvider.overrideWith((ref) {
            final bindings = bootstrap.personalAgentBindingPort!;
            if (bindings is UserServicePersonalAgentBindingAdapter &&
                bootstrap.appSessionService != null) {
              final sessions = ref.read(appSessionServiceProvider);
              final coordinator = AuthSessionCoordinator(
                sessions: sessions,
                onSessionUpdated: (session) {
                  ref
                      .read(sessionProvider.notifier)
                      .setSession(session.toLegacySessionIdentity());
                },
              );
              return bindings.withAuthenticatedClient(
                AuthenticatedUserServiceRpcClient(
                  client: bindings.httpClient,
                  sessions: coordinator,
                ),
              );
            }
            return bindings;
          }),
        if (bootstrap.conversationService != null)
          conversationServiceProvider.overrideWith((ref) {
            final conversations = bootstrap.conversationService!;
            if (conversations is ImCoreConversationService) {
              return conversations.withAgentInventory(
                ref.watch(agentInventoryPortProvider),
              );
            }
            return conversations;
          }),
        if (bootstrap.agentControlService != null)
          agentControlServiceProvider.overrideWith((ref) {
            final control = bootstrap.agentControlService!;
            if (control is DefaultAgentControlService &&
                bootstrap.messagingService != null) {
              final personalAgentBindings =
                  bootstrap.personalAgentBindingPort == null
                  ? null
                  : ref.watch(personalAgentBindingPortProvider);
              return DefaultAgentControlService(
                inventory: ref.watch(agentInventoryPortProvider),
                messages: bootstrap.messagingService!,
                personalAgentBindings: personalAgentBindings,
                identities: bootstrap.identityCorePort == null
                    ? null
                    : ref.watch(identityCorePortProvider),
                environment: bootstrap.environment,
                downloadBaseUrl: control.downloadBaseUrl,
                agentImEnabled: ref.watch(agentImEnabledProvider),
                preferredLanguageProvider: () {
                  final mode = ref.read(appLocaleModeProvider);
                  final platformLocale =
                      WidgetsBinding.instance.platformDispatcher.locale;
                  return resolveEffectiveAppLanguage(
                    mode,
                    platformLocale,
                  ).wireValue;
                },
              );
            }
            return control;
          }),
        if (bootstrap.agentControlStatusStore != null)
          agentControlStatusStoreProvider.overrideWithValue(
            bootstrap.agentControlStatusStore!,
          ),
        if (bootstrap.groupApplicationService != null)
          groupApplicationServiceProvider.overrideWithValue(
            bootstrap.groupApplicationService!,
          ),
        if (bootstrap.profileApplicationService != null)
          profileApplicationServiceProvider.overrideWithValue(
            bootstrap.profileApplicationService!,
          ),
        if (bootstrap.peerIdentityService != null)
          peerIdentityServiceProvider.overrideWithValue(
            bootstrap.peerIdentityService!,
          ),
        if (bootstrap.directoryApplicationService != null)
          directoryApplicationServiceProvider.overrideWithValue(
            bootstrap.directoryApplicationService!,
          ),
        if (bootstrap.relationshipApplicationService != null)
          relationshipApplicationServiceProvider.overrideWithValue(
            bootstrap.relationshipApplicationService!,
          ),
        if (bootstrap.realtimeApplicationService != null)
          realtimeApplicationServiceProvider.overrideWithValue(
            bootstrap.realtimeApplicationService!,
          ),
        if (bootstrap.productLocalStore != null)
          productLocalStoreProvider.overrideWithValue(
            bootstrap.productLocalStore!,
          ),
        ...providerOverrides,
      ],
      child: const _AwikiMeRoot(),
    );
  }
}

class _AwikiMeRoot extends ConsumerStatefulWidget {
  const _AwikiMeRoot();

  @override
  ConsumerState<_AwikiMeRoot> createState() => _AwikiMeRootState();
}

class _AwikiMeRootState extends ConsumerState<_AwikiMeRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLifecycleProvider.notifier).setLifecycle(state);
  }

  @override
  void didHaveMemoryPressure() {
    ref.read(chatThreadsProvider.notifier).trimForMemoryPressure();
  }

  @override
  Widget build(BuildContext context) {
    final localeMode = ref.watch(appLocaleModeProvider);
    final displayScale = ref.watch(displayScaleProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AwikiMePalette.ivory,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AwikiMePalette.ivory,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AwikiMePalette.ivory,
      ),
      child: CupertinoApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: localeMode.locale,
        localeResolutionCallback: (locale, supportedLocales) {
          if (locale == null) {
            return const Locale('zh');
          }
          for (final supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == locale.languageCode) {
              return supportedLocale;
            }
          }
          return const Locale('zh');
        },
        theme: AwikiMeTheme.cupertinoTheme,
        builder: (context, child) {
          return AwikiDisplayScaleScope(
            scale: displayScale,
            child: _DisplayScaleShortcuts(
              onDecrease: () =>
                  ref.read(displayScaleProvider.notifier).decrease(),
              onIncrease: () =>
                  ref.read(displayScaleProvider.notifier).increase(),
              onReset: () => ref.read(displayScaleProvider.notifier).reset(),
              child: _KeyboardDismissScope(
                child: material.Theme(
                  data: AwikiMeTheme.materialTheme,
                  child: AppOrientationScope(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

class _DisplayScaleShortcuts extends StatefulWidget {
  const _DisplayScaleShortcuts({
    required this.child,
    required this.onDecrease,
    required this.onIncrease,
    required this.onReset,
  });

  final Widget child;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onReset;

  @override
  State<_DisplayScaleShortcuts> createState() => _DisplayScaleShortcutsState();
}

class _DisplayScaleShortcutsState extends State<_DisplayScaleShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasModifier =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (!hasModifier) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      widget.onDecrease();
      return true;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      widget.onIncrease();
      return true;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      widget.onReset();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _KeyboardDismissScope extends StatelessWidget {
  const _KeyboardDismissScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_isPointerInsideEditable(context, event.position)) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: child,
    );
  }

  bool _isPointerInsideEditable(BuildContext context, Offset globalPosition) {
    var found = false;

    void visit(Element element) {
      if (found) {
        return;
      }
      if (element.widget is EditableText) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.attached) {
          final localPosition = renderObject.globalToLocal(globalPosition);
          if (renderObject.size.contains(localPosition)) {
            found = true;
            return;
          }
        }
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }
}
