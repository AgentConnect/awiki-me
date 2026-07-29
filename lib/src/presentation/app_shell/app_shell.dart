import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/e2e_semantics.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/device_management.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/services/realtime_gateway.dart';
import '../../l10n/l10n.dart';
import '../conversation_list/conversation_workspace_page.dart';
import '../conversation_list/conversation_provider.dart';
import '../devices/device_join_approval_sheet.dart';
import '../devices/devices_provider.dart';
import '../agents/agents_page.dart';
import '../agents/agents_provider.dart';
import '../friends/friends_navigation_provider.dart';
import '../friends/friends_workspace_page.dart';
import '../onboarding/onboarding_page.dart';
import '../profile/profile_workspace_page.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'providers/app_update_provider.dart';
import 'providers/app_runtime_provider.dart';
import 'providers/message_sync_coordinator_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/selected_conversation_provider.dart';
import 'providers/session_provider.dart';

const _desktopRailActiveColor = AwikiMePalette.brandAccent;
const _desktopRailInactiveColor = AwikiMePalette.mutedNeutral;
const _desktopRailActiveBackground = AwikiMePalette.brandAccentSoft;
const double _desktopRailWidth = 64;
const double _desktopRailMinWidth = 56;
const MethodChannel _macWindowChromeChannel = MethodChannel(
  'ai.awiki.awikime/window_chrome',
);

bool shouldInitializeAppUpdates(TargetPlatform platform) =>
    platform != TargetPlatform.windows;

String? _formatUnreadBadge(int count) {
  if (count <= 0) {
    return null;
  }
  return count > 99 ? '99+' : '$count';
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int? _lastFeedbackId;
  final Set<ShellDestination> _retainedDestinations = <ShellDestination>{};
  String? _retainedSessionDid;
  bool? _previousExpandedLayout;
  bool _desktopIdentityDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appRuntimeProvider.notifier).initialize());
      if (shouldInitializeAppUpdates(defaultTargetPlatform)) {
        unawaited(ref.read(appUpdateProvider.notifier).initialize());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UiFeedbackEvent?>(uiFeedbackProvider, (previous, next) {
      if (next == null || next.id == _lastFeedbackId || !mounted) {
        return;
      }
      _lastFeedbackId = next.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final implicitDetail = next.detail ?? next.message.detail;
        final message =
            next.message.id == 'raw' &&
                implicitDetail != null &&
                implicitDetail.trim().isNotEmpty
            ? context.l10n.operationFailedRetry
            : next.message.resolve(context.l10n);
        AwikiMeToast.show(
          context,
          message,
          danger: next.danger,
          detail: implicitDetail,
        );
      });
    });

    final runtime = ref.watch(appRuntimeProvider);
    final session = ref.watch(sessionProvider);
    final messageSync = ref.watch(messageSyncCoordinatorProvider);
    final realtimeStatus = ref
        .watch(realtimeConnectionStatusProvider)
        .maybeWhen(
          data: (status) => status,
          orElse: () => RealtimeConnectionStatus.idle,
        );
    final responsive = context.awikiResponsive;
    final selectedDestination = ref.watch(shellDestinationProvider);
    final navigationController = ref.read(shellDestinationProvider.notifier);
    final unreadCount = ref.watch(
      conversationListProvider.select((state) => state.unreadCount),
    );
    final pendingJoinRequest = ref.watch(
      devicesProvider.select((state) {
        if (!state.currentDeviceCanManage) {
          return null;
        }
        final requests = state.visibleJoinRequests;
        return requests.isEmpty ? null : requests.first;
      }),
    );

    if (!session.isLoggedIn) {
      return Stack(
        children: <Widget>[
          const OnboardingPage(),
          if (runtime.isBusy) const AwikiMeLoadingMask(),
          if (messageSync.status == MessageSyncCoordinatorStatus.authRevoked)
            AwikiMePersistentToast(
              message: context.l10n.messageSyncStatusAuthRevoked,
              danger: true,
              bottom: 32,
            ),
        ],
      );
    }

    final expanded = responsive.usesDesktopLayout;
    final enteredDesktopFromCompactProfile =
        _previousExpandedLayout == false &&
        expanded &&
        selectedDestination == ShellDestination.profile;
    _previousExpandedLayout = expanded;
    final destination = navigationController.resolvedFor(expanded);
    if (destination != selectedDestination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(shellDestinationProvider.notifier).reconcileFor(expanded);
      });
    }
    if (enteredDesktopFromCompactProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showDesktopIdentityDialog();
        }
      });
    }

    final sessionDid = session.session?.did.trim();
    if (_retainedSessionDid != sessionDid) {
      _retainedSessionDid = sessionDid;
      _retainedDestinations.clear();
    }
    _retainedDestinations.add(destination);

    final bottomNav = _BottomNavBar(
      currentDestination: destination,
      unreadCount: unreadCount,
      onTap: (next) {
        ref.read(shellDestinationProvider.notifier).selectCompact(next);
      },
    );

    final retainedPage = _RetainedDestinationHost(
      activeDestination: destination,
      retainedDestinations: _retainedDestinations,
      pageBuilder: _buildDestinationPage,
    );
    final page = !expanded && _isCompactSecondaryDestination(destination)
        ? PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                ref.read(shellDestinationProvider.notifier).backFromSecondary();
              }
            },
            child: retainedPage,
          )
        : retainedPage;
    final compactDetailVisible =
        !expanded &&
        switch (destination) {
          ShellDestination.messages =>
            ref.watch(selectedConversationProvider) != null,
          ShellDestination.agents => ref.watch(
            agentsProvider.select((state) => state.selectedAgentDid != null),
          ),
          ShellDestination.contacts => ref.watch(
            friendsWorkspaceNavigationProvider.select(
              (state) => state.showsCompactDetail,
            ),
          ),
          ShellDestination.settings => true,
          ShellDestination.profile => false,
          _ => false,
        };
    final content = expanded
        ? _DesktopShell(
            currentDestination: destination,
            unreadCount: unreadCount,
            session: session.session,
            onTap: (next) {
              ref.read(shellDestinationProvider.notifier).selectExpanded(next);
            },
            onProfileTap: _showDesktopIdentityDialog,
            child: page,
          )
        : Column(
            children: <Widget>[
              Expanded(child: page),
              if (!compactDetailVisible) bottomNav,
            ],
          );

    return AwikiShellNavigationScope(
      child: Stack(
        children: <Widget>[
          e2eSemantics(
            identifier: 'e2e-authenticated',
            child: AwikiMeWidgets.pageBackground(
              key: const Key('app-shell-page-background'),
              color: expanded ? null : context.awikiTheme.surface,
              child: SafeArea(
                bottom: false,
                child: AwikiSystemNavigationClearance(child: content),
              ),
            ),
          ),
          if (pendingJoinRequest != null)
            _DeviceJoinRequestBanner(
              deviceId: pendingJoinRequest.protocolDeviceId,
              onReview: () => _openDeviceJoinRequest(pendingJoinRequest),
            ),
          if (runtime.isBusy)
            AwikiMeLoadingMask(label: context.l10n.commonPleaseWait),
          if (_shouldShowRealtimeToast(realtimeStatus))
            AwikiMePersistentToast(
              message: _realtimeToastMessage(context, realtimeStatus),
              danger:
                  realtimeStatus == RealtimeConnectionStatus.disconnected ||
                  realtimeStatus == RealtimeConnectionStatus.failed,
              showSpinner:
                  realtimeStatus == RealtimeConnectionStatus.connecting ||
                  realtimeStatus == RealtimeConnectionStatus.reconnecting,
              bottom: responsive.isPhone ? 96 : 32,
            ),
          if (_shouldShowMessageSyncBanner(messageSync))
            AwikiMePersistentToast(
              message: _messageSyncBannerMessage(context, messageSync),
              danger:
                  messageSync.status ==
                      MessageSyncCoordinatorStatus.retryableFailure ||
                  messageSync.status ==
                      MessageSyncCoordinatorStatus.authRevoked,
              showSpinner:
                  messageSync.status ==
                      MessageSyncCoordinatorStatus.recoveryRequired ||
                  messageSync.status ==
                      MessageSyncCoordinatorStatus.recovering,
              bottom: _shouldShowRealtimeToast(realtimeStatus)
                  ? (responsive.isPhone ? 154 : 90)
                  : (responsive.isPhone ? 96 : 32),
            ),
        ],
      ),
    );
  }

  Future<void> _showDesktopIdentityDialog() async {
    if (!mounted || _desktopIdentityDialogOpen) {
      return;
    }
    _desktopIdentityDialogOpen = true;
    try {
      await showCurrentIdentityDialog(context);
    } finally {
      _desktopIdentityDialogOpen = false;
    }
  }

  Future<void> _openDeviceJoinRequest(DeviceJoinRequestNotice request) async {
    await AppNavigator.push<void>(
      context,
      (_) => DeviceJoinApprovalSheet(request: request),
    );
    if (mounted) {
      await ref.read(devicesProvider.notifier).refreshJoinInbox();
    }
  }

  bool _shouldShowRealtimeToast(RealtimeConnectionStatus status) {
    return status == RealtimeConnectionStatus.connecting ||
        status == RealtimeConnectionStatus.reconnecting;
  }

  bool _shouldShowMessageSyncBanner(MessageSyncCoordinatorState state) {
    return state.status == MessageSyncCoordinatorStatus.recoveryRequired ||
        state.status == MessageSyncCoordinatorStatus.recovering ||
        state.status == MessageSyncCoordinatorStatus.retryableFailure ||
        state.status == MessageSyncCoordinatorStatus.authRevoked;
  }

  String _messageSyncBannerMessage(
    BuildContext context,
    MessageSyncCoordinatorState state,
  ) {
    return switch (state.status) {
      MessageSyncCoordinatorStatus.recoveryRequired =>
        context.l10n.messageSyncStatusRecoveryRequired,
      MessageSyncCoordinatorStatus.recovering =>
        context.l10n.messageSyncStatusRecovering,
      MessageSyncCoordinatorStatus.retryableFailure =>
        context.l10n.messageSyncStatusRetryableFailure,
      MessageSyncCoordinatorStatus.authRevoked =>
        context.l10n.messageSyncStatusAuthRevoked,
      MessageSyncCoordinatorStatus.idle => context.l10n.messageSyncStatusIdle,
      MessageSyncCoordinatorStatus.syncing =>
        context.l10n.messageSyncStatusSyncing,
    };
  }

  String _realtimeToastMessage(
    BuildContext context,
    RealtimeConnectionStatus status,
  ) {
    switch (status) {
      case RealtimeConnectionStatus.connecting:
        return context.l10n.realtimeStatusConnecting;
      case RealtimeConnectionStatus.reconnecting:
        return context.l10n.realtimeStatusReconnecting;
      case RealtimeConnectionStatus.disconnected:
      case RealtimeConnectionStatus.failed:
        return context.l10n.realtimeStatusDisconnected;
      case RealtimeConnectionStatus.idle:
      case RealtimeConnectionStatus.connected:
        return '';
    }
  }

  Widget _buildDestinationPage(ShellDestination destination) {
    final expanded = context.awikiResponsive.usesDesktopLayout;
    final navigationController = ref.read(shellDestinationProvider.notifier);
    return switch (destination) {
      ShellDestination.messages => const ConversationWorkspacePage(),
      ShellDestination.agents => const AgentsWorkspacePage(),
      ShellDestination.contacts => const FriendsWorkspacePage(),
      ShellDestination.profile => const ProfileWorkspacePage(),
      ShellDestination.tasks => _DesktopPlaceholderPage(
        title: context.l10n.shellTasksPlaceholderTitle,
        subtitle: context.l10n.shellTasksPlaceholderSubtitle,
        icon: CupertinoIcons.checkmark_square,
      ),
      ShellDestination.workbench => _DesktopPlaceholderPage(
        title: context.l10n.shellWorkspacePlaceholderTitle,
        subtitle: context.l10n.shellWorkspacePlaceholderSubtitle,
        icon: CupertinoIcons.square_grid_2x2,
      ),
      ShellDestination.settings =>
        expanded
            ? const _DesktopEmbeddedSettingsPage()
            : SettingsPage(
                onBack: navigationController.backFromSecondary,
                onProfileTap: () => navigationController.selectCompact(
                  ShellDestination.profile,
                ),
              ),
    };
  }
}

bool _isCompactSecondaryDestination(ShellDestination destination) {
  return destination == ShellDestination.settings;
}

typedef _ShellPageBuilder = Widget Function(ShellDestination destination);

class _RetainedDestinationHost extends StatelessWidget {
  const _RetainedDestinationHost({
    required this.activeDestination,
    required this.retainedDestinations,
    required this.pageBuilder,
  });

  final ShellDestination activeDestination;
  final Set<ShellDestination> retainedDestinations;
  final _ShellPageBuilder pageBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final destination in retainedDestinations)
          _RetainedDestinationPage(
            key: ValueKey<ShellDestination>(destination),
            active: destination == activeDestination,
            child: pageBuilder(destination),
          ),
      ],
    );
  }
}

class _RetainedDestinationPage extends StatelessWidget {
  const _RetainedDestinationPage({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: ExcludeSemantics(
          excluding: !active,
          child: IgnorePointer(ignoring: !active, child: child),
        ),
      ),
    );
  }
}

class _DeviceJoinRequestBanner extends StatelessWidget {
  const _DeviceJoinRequestBanner({
    required this.deviceId,
    required this.onReview,
  });

  final String deviceId;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Positioned(
      left: 20,
      right: 20,
      top: 12,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Semantics(
            identifier: 'device-join-request-entry',
            button: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onReview,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(AwikiMeRadii.lg),
                  border: Border.all(
                    color: AwikiMeColors.primary.withValues(alpha: 0.2),
                  ),
                  boxShadow: theme.overlayShadow,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.device_phone_portrait,
                      color: AwikiMeColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            context.l10n.deviceJoinApprovalTitle,
                            style: TextStyle(
                              color: theme.title,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            deviceId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.l10n.deviceReviewAction,
                      style: const TextStyle(
                        color: AwikiMeColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.currentDestination,
    required this.unreadCount,
    required this.session,
    required this.onTap,
    required this.onProfileTap,
    required this.child,
  });

  final ShellDestination currentDestination;
  final int unreadCount;
  final SessionIdentity? session;
  final ValueChanged<ShellDestination> onTap;
  final VoidCallback onProfileTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final railWidth = responsive
        .displayScaled(_desktopRailWidth)
        .clamp(_desktopRailMinWidth, double.infinity)
        .toDouble();
    final content = Row(
      children: <Widget>[
        SizedBox(
          key: const Key('mac-desktop-rail-slot'),
          width: railWidth,
          child: _DesktopRail(
            currentDestination: currentDestination,
            unreadCount: unreadCount,
            session: session,
            onTap: onTap,
            onProfileTap: onProfileTap,
          ),
        ),
        Container(width: 1, color: context.awikiTheme.border),
        Expanded(child: child),
      ],
    );
    if (!responsive.isMacDesktop) {
      return content;
    }
    return _MacWindowChromeSync(railWidth: railWidth, child: content);
  }
}

class _MacWindowChromeSync extends StatefulWidget {
  const _MacWindowChromeSync({required this.railWidth, required this.child});

  final double railWidth;
  final Widget child;

  @override
  State<_MacWindowChromeSync> createState() => _MacWindowChromeSyncState();
}

class _MacWindowChromeSyncState extends State<_MacWindowChromeSync> {
  double? _lastSyncedRailWidth;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(_MacWindowChromeSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.railWidth - widget.railWidth).abs() >= 0.5) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _macWindowChromeChannel
        .invokeMethod<void>('resetTrafficLightRailWidth')
        .catchError((Object _) {});
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final railWidth = widget.railWidth;
      if (_lastSyncedRailWidth != null &&
          (_lastSyncedRailWidth! - railWidth).abs() < 0.5) {
        return;
      }
      _lastSyncedRailWidth = railWidth;
      _macWindowChromeChannel
          .invokeMethod<void>('setTrafficLightRailWidth', <String, Object?>{
            'width': railWidth,
          })
          .catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.currentDestination,
    required this.unreadCount,
    required this.session,
    required this.onTap,
    required this.onProfileTap,
  });

  final ShellDestination currentDestination;
  final int unreadCount;
  final SessionIdentity? session;
  final ValueChanged<ShellDestination> onTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AwikiMePalette.navigationSurface),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 760;
          final gap = responsive.displayScaled(compact ? 7.0 : 10.0);
          final avatar = _avatarSeedForSession(session);
          return Column(
            children: <Widget>[
              SizedBox(height: responsive.displayScaled(compact ? 40 : 50)),
              _DesktopRailAvatar(
                key: const Key('mac-me-rail-avatar'),
                seed: avatar.seed,
                labelOverride: avatar.labelOverride,
                onTap: onProfileTap,
              ),
              SizedBox(height: responsive.displayScaled(compact ? 10 : 12)),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _DesktopRailItem(
                        key: const Key('desktop-rail-messages'),
                        role: AwikiMeIconRole.messages,
                        label: context.l10n.shellNavMessages,
                        semanticsIdentifier: 'e2e-messages-tab',
                        selected:
                            currentDestination == ShellDestination.messages,
                        badge: _formatUnreadBadge(unreadCount),
                        compact: compact,
                        onTap: () => onTap(ShellDestination.messages),
                      ),
                      SizedBox(height: gap),
                      _DesktopRailItem(
                        key: const Key('desktop-rail-agents'),
                        role: AwikiMeIconRole.agents,
                        label: context.l10n.shellNavAgents,
                        selected: currentDestination == ShellDestination.agents,
                        compact: compact,
                        semanticsIdentifier: 'e2e-agents-tab',
                        onTap: () => onTap(ShellDestination.agents),
                      ),
                      SizedBox(height: gap),
                      _DesktopRailItem(
                        key: const Key('desktop-rail-contacts'),
                        role: AwikiMeIconRole.contacts,
                        label: context.l10n.shellNavContacts,
                        semanticsIdentifier: 'e2e-contacts-tab',
                        selected:
                            currentDestination == ShellDestination.contacts,
                        compact: compact,
                        onTap: () => onTap(ShellDestination.contacts),
                      ),
                      SizedBox(height: gap),
                      _DesktopRailItem(
                        key: const Key('desktop-rail-tasks'),
                        role: AwikiMeIconRole.tasks,
                        label: context.l10n.shellNavTasks,
                        selected: currentDestination == ShellDestination.tasks,
                        compact: compact,
                        onTap: () => onTap(ShellDestination.tasks),
                      ),
                      SizedBox(height: gap),
                      _DesktopRailItem(
                        key: const Key('desktop-rail-workbench'),
                        role: AwikiMeIconRole.workbench,
                        label: context.l10n.shellNavWorkspace,
                        selected:
                            currentDestination == ShellDestination.workbench,
                        compact: compact,
                        onTap: () => onTap(ShellDestination.workbench),
                      ),
                    ],
                  ),
                ),
              ),
              _DesktopRailItem(
                key: const Key('desktop-rail-settings'),
                role: AwikiMeIconRole.settings,
                label: context.l10n.shellNavSettings,
                semanticsIdentifier: 'e2e-settings-tab',
                selected: currentDestination == ShellDestination.settings,
                compact: compact,
                onTap: () => onTap(ShellDestination.settings),
              ),
              SizedBox(height: responsive.displayScaled(compact ? 10 : 14)),
            ],
          );
        },
      ),
    );
  }

  ({String seed, String? labelOverride}) _avatarSeedForSession(
    SessionIdentity? session,
  ) {
    final handle = session?.handle?.trim();
    if (handle != null && handle.isNotEmpty) {
      return (seed: handle, labelOverride: null);
    }
    final displayName = session?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return (seed: displayName, labelOverride: null);
    }
    final did = session?.did.trim();
    if (did != null && did.isNotEmpty) {
      return (seed: did, labelOverride: null);
    }
    return (seed: 'Me', labelOverride: 'Me');
  }
}

class _DesktopEmbeddedSettingsPage extends StatelessWidget {
  const _DesktopEmbeddedSettingsPage();

  @override
  Widget build(BuildContext context) {
    return AwikiSidebarWorkspace(
      sidebar: const SizedBox.expand(
        key: Key('mac-settings-list-pane'),
        child: SettingsPage(embedded: true),
      ),
      detailPane: DecoratedBox(
        decoration: BoxDecoration(color: context.awikiTheme.surface),
        child: const AwikiWorkspaceEmptyDetail(),
      ),
    );
  }
}

class _DesktopRailItem extends StatelessWidget {
  const _DesktopRailItem({
    super.key,
    required this.role,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
    this.semanticsIdentifier,
  });

  final AwikiMeIconRole role;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String? badge;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final foreground = selected
        ? _desktopRailActiveColor
        : _desktopRailInactiveColor;
    final height = responsive.displayScaled(compact ? 50.0 : 56.0);
    final width = responsive.displayScaled(54);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      selected: selected,
      borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
      pressedScale: 0.98,
      scaleOnPress: true,
      builder: (context, state, child) {
        final overlay = state.pressed
            ? _desktopRailActiveColor.withValues(alpha: 0.10)
            : state.hovered || state.focused
            ? _desktopRailActiveColor.withValues(alpha: 0.06)
            : CupertinoColors.transparent;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: overlay,
            borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
          ),
          child: child,
        );
      },
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: width,
                height: height,
                padding: EdgeInsets.symmetric(
                  vertical: responsive.displayScaled(compact ? 6 : 8),
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? _desktopRailActiveBackground
                      : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(
                    responsive.displayScaled(10),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: responsive.displayScaled(30),
                      height: responsive.displayScaled(24),
                      child: Center(
                        child: AwikiMeSemanticIcon(
                          role: role,
                          selected: selected,
                          color: foreground,
                          size: responsive.displayScaled(18),
                        ),
                      ),
                    ),
                    SizedBox(height: responsive.displayScaled(compact ? 2 : 4)),
                    SizedBox(
                      width: width - responsive.displayScaled(6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground,
                            fontSize: responsive.displayScaled(10.5),
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  right: responsive.displayScaled(5),
                  top: responsive.displayScaled(4),
                  child: Container(
                    key: const Key('mac-messages-unread-badge'),
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.displayScaled(5),
                      vertical: responsive.displayScaled(2),
                    ),
                    decoration: BoxDecoration(
                      color: AwikiMePalette.unreadRed,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: AwikiMePalette.navigationSurface,
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: responsive.displayScaled(9),
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopRailAvatar extends StatelessWidget {
  const _DesktopRailAvatar({
    super.key,
    required this.seed,
    this.labelOverride,
    required this.onTap,
  });

  final String seed;
  final String? labelOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: context.l10n.shellNavMe,
      semanticsIdentifier: 'e2e-profile-dialog-button',
      scaleOnPress: true,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(responsive.displayScaled(19)),
      child: ExcludeSemantics(
        child: Container(
          width: responsive.displayScaled(38),
          height: responsive.displayScaled(38),
          decoration: BoxDecoration(
            color: AwikiMePalette.content,
            borderRadius: BorderRadius.circular(responsive.displayScaled(19)),
            border: Border.all(color: AwikiMePalette.hairline),
          ),
          child: Center(
            child: AvatarBadge(
              seed: seed,
              size: responsive.displayScaled(34),
              labelOverride: labelOverride,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPlaceholderPage extends StatelessWidget {
  const _DesktopPlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.surface),
      child: Center(
        child: ConstrainedBox(
          key: const Key('mac-desktop-placeholder-card'),
          constraints: BoxConstraints(maxWidth: responsive.displayScaled(360)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: theme.secondaryText,
                size: responsive.displayScaled(36),
              ),
              SizedBox(height: responsive.displayScaled(14)),
              Text(
                title,
                style: TextStyle(
                  color: theme.title,
                  fontSize: responsive.displayScaled(18),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: responsive.displayScaled(8)),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: responsive.displayScaled(13),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentDestination,
    required this.unreadCount,
    required this.onTap,
  });

  final ShellDestination currentDestination;
  final int unreadCount;
  final ValueChanged<ShellDestination> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return DecoratedBox(
      key: const Key('compact-bottom-navigation'),
      decoration: BoxDecoration(
        color: AwikiMePalette.navigationSurface,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _BottomNavItem(
                  key: const Key('compact-nav-messages'),
                  label: context.l10n.shellNavMessages,
                  semanticsIdentifier: 'e2e-messages-tab',
                  role: AwikiMeIconRole.messages,
                  active: currentDestination == ShellDestination.messages,
                  badge: _formatUnreadBadge(unreadCount),
                  onTap: () => onTap(ShellDestination.messages),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  key: const Key('compact-nav-agents'),
                  label: context.l10n.shellNavAgents,
                  semanticsIdentifier: 'e2e-agents-tab',
                  role: AwikiMeIconRole.agents,
                  active: currentDestination == ShellDestination.agents,
                  onTap: () => onTap(ShellDestination.agents),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  key: const Key('compact-nav-contacts'),
                  label: context.l10n.shellNavContacts,
                  semanticsIdentifier: 'e2e-contacts-tab',
                  role: AwikiMeIconRole.contacts,
                  active: currentDestination == ShellDestination.contacts,
                  onTap: () => onTap(ShellDestination.contacts),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  key: const Key('compact-nav-profile'),
                  label: context.l10n.shellNavMe,
                  semanticsIdentifier: 'e2e-profile-tab',
                  role: AwikiMeIconRole.profile,
                  active: currentDestination == ShellDestination.profile,
                  onTap: () => onTap(ShellDestination.profile),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    super.key,
    required this.label,
    required this.semanticsIdentifier,
    required this.role,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String semanticsIdentifier;
  final AwikiMeIconRole role;
  final bool active;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final iconSize = responsive.scaled(23);
    final labelFontSize = responsive.scaled(10.5);
    final iconSlotSize = responsive.scaled(32);
    final foreground = active
        ? AwikiMePalette.brandAccent
        : AwikiMePalette.mutedNeutral;
    Widget buildNavIcon() {
      final icon = AwikiMeSemanticIcon(
        role: role,
        selected: active,
        color: foreground,
        size: iconSize,
      );
      final badgeLabel = badge;
      return SizedBox(
        width: iconSlotSize,
        height: iconSlotSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            icon,
            if (badgeLabel != null)
              Positioned(
                top: 0,
                right: responsive.scaled(-4),
                child: _NavUnreadBadge(label: badgeLabel),
              ),
          ],
        ),
      );
    }

    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      selected: active,
      scaleOnPress: true,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(
            responsive.spacing(4),
            0,
            responsive.spacing(4),
            responsive.spacing(2),
          ),
          color: CupertinoColors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              buildNavIcon(),
              SizedBox(height: responsive.scaled(1)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: foreground,
                    fontSize: labelFontSize,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavUnreadBadge extends StatelessWidget {
  const _NavUnreadBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      key: const Key('mobile-messages-unread-badge'),
      constraints: BoxConstraints(
        minWidth: responsive.scaled(17),
        minHeight: responsive.scaled(16),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.scaled(label.length > 1 ? 5 : 4),
        vertical: responsive.scaled(1.5),
      ),
      decoration: BoxDecoration(
        color: AwikiMePalette.unreadRed,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: responsive.scaled(9.5),
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
