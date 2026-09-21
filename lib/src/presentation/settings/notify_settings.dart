import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/auth/auth_session_coordinator.dart';
import '../../application/models/app_session.dart';
import '../../application/ports/notify_preference_port.dart';
import '../../application/remote_push_message_reference.dart';
import '../../data/push/user_service_notify_preference_adapter.dart';
import '../../data/services/authenticated_user_service_rpc_client.dart';
import '../../data/services/awiki_onboarding_utility_client.dart';
import '../app_shell/providers/session_provider.dart';

final notifyPreferencePortProvider = Provider<NotifyPreferencePort>((ref) {
  final environment = ref.watch(awikiEnvironmentConfigProvider);
  return UserServiceNotifyPreferenceAdapter(
    AuthenticatedUserServiceRpcClient(
      client: AwikiOnboardingUtilityHttpClient(
        baseUrl: environment.userServiceUrl,
      ),
      sessions: AuthSessionCoordinator(
        sessions: ref.watch(appSessionServiceProvider),
        onSessionUpdated: (session) => ref
            .read(sessionProvider.notifier)
            .setSession(session.toLegacySessionIdentity()),
      ),
    ),
  );
});

class NotifySettingsPage extends StatelessWidget {
  const NotifySettingsPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('任务通知')),
    child: SafeArea(child: ListView(children: const [NotifySettings()])),
  );
}

class NotifySettings extends ConsumerStatefulWidget {
  const NotifySettings({super.key});
  @override
  ConsumerState<NotifySettings> createState() => _NotifySettingsState();
}

class _NotifySettingsState extends ConsumerState<NotifySettings> {
  NotifyPreference? value;
  bool busy = true;
  String? error;
  int request = 0;
  static const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<NotifyPreference> syncNative(
    NotifyPreference v,
    String owner, {
    bool localDisable = false,
    bool explicitSave = false,
  }) async {
    try {
      final applied = await channel.invokeMethod<bool>('configureTextNotify', {
        ...v.json,
        'local_disable': localDisable,
        'explicit_save': explicitSave,
        'target': remotePushOpaqueTargetReference(owner),
        'muted_identities': v.mutedPeerDids
            .map(remotePushOpaqueIdentityReference)
            .toList(),
      });
      if (applied != true) {
        throw StateError('notify_native_preference_not_applied');
      }
      final effective = await channel.invokeMapMethod<String, Object?>(
        'getTextNotifyPreferenceState',
        remotePushOpaqueTargetReference(owner),
      );
      if (effective == null) {
        throw StateError('notify_native_preference_unavailable');
      }
      return NotifyPreference.fromJson({
        ...effective,
        'muted_peer_dids': v.mutedPeerDids,
      });
    } on MissingPluginException {
      return v; // non-Android test host
    }
  }

  Future<void> load() async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    final id = ++request;
    if (epoch == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await ref.read(notifyPreferencePortProvider).load();
      if (!mounted ||
          id != request ||
          ref.read(sessionProvider).activeEpoch != epoch) {
        return;
      }
      final effective = await syncNative(next, epoch.ownerDid);
      if (mounted && id == request) {
        setState(() {
          value = effective;
          busy = false;
        });
      }
    } on Object {
      if (mounted && id == request) {
        setState(() {
          busy = false;
          error = '暂时无法读取通知设置，请重试。';
        });
      }
    }
  }

  Future<void> save({required bool enabled, required bool urgent}) async {
    final previous = value;
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (previous == null || epoch == null || busy) return;
    final id = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    var locallyDisabled = false;
    try {
      // Disable sound locally immediately; a server outage must not keep this phone ringing.
      if (!enabled || !urgent) {
        final local = await syncNative(
          NotifyPreference(
            enabled: enabled,
            urgentEnabled: urgent,
            version: previous.version,
            mutedPeerDids: previous.mutedPeerDids,
          ),
          epoch.ownerDid,
          localDisable: true,
        );
        locallyDisabled = true;
        if (mounted && id == request) {
          setState(() {
            value = local;
          });
        }
      }
      final next = await ref
          .read(notifyPreferencePortProvider)
          .save(previous, enabled: enabled, urgentEnabled: urgent);
      if (!mounted ||
          id != request ||
          ref.read(sessionProvider).activeEpoch != epoch) {
        return;
      }
      await syncNative(next, epoch.ownerDid, explicitSave: true);
      if (mounted && id == request) {
        setState(() {
          value = next;
          busy = false;
        });
      }
    } on Object {
      if (mounted && id == request) {
        setState(() {
          busy = false;
          error = locallyDisabled
              ? '设置未同步，本机已停止提醒。请重新加载后重试。'
              : '设置未同步，请重新加载后重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.activeEpoch != next.activeEpoch) {
        request++;
        value = null;
        Future.microtask(load);
      }
    });
    return CupertinoListSection.insetGrouped(
      header: const Text('任务通知'),
      children: [
        CupertinoListTile(
          title: const Text('允许任务通知'),
          subtitle: const Text('接收我的 Skill Agent 发来的任务结果'),
          trailing: CupertinoSwitch(
            value: value?.enabled ?? false,
            onChanged: busy || value == null
                ? null
                : (v) => save(enabled: v, urgent: value!.urgentEnabled),
          ),
        ),
        CupertinoListTile(
          title: const Text('紧急提醒'),
          subtitle: const Text('自动弹出，持续响铃和振动，最长 60 秒'),
          trailing: CupertinoSwitch(
            value: value?.urgentEnabled ?? false,
            onChanged: busy || value?.enabled != true
                ? null
                : (v) => save(enabled: true, urgent: v),
          ),
        ),
        CupertinoListTile(
          title: const Text('自动弹出权限'),
          subtitle: const Text('锁屏全屏提醒由系统控制；未允许时显示通知横幅'),
          onTap: () async {
            await channel.invokeMethod<void>('openNotifyFullScreenSettings');
          },
        ),
        if (busy)
          const CupertinoListTile(
            title: Text('正在同步通知设置…'),
            trailing: CupertinoActivityIndicator(),
          ),
        if (error != null)
          CupertinoListTile(
            title: Text(error!, maxLines: 3),
            trailing: CupertinoButton(onPressed: load, child: const Text('重试')),
          ),
      ],
    );
  }
}

Future<void> syncNotifyConversationMute(
  WidgetRef ref,
  String peer,
  bool muted,
) async {
  final epoch = ref.read(sessionProvider).activeEpoch;
  if (epoch == null || peer.isEmpty) return;
  const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
  final args = {
    'target': remotePushOpaqueTargetReference(epoch.ownerDid),
    'identity': remotePushOpaqueIdentityReference(peer),
    'muted': muted,
  };
  // Local mute is immediate. Unmute waits for server confirmation.
  if (muted) {
    await channel.invokeMethod<bool>('muteTextNotifyConversation', args);
  }
  final port = ref.read(notifyPreferencePortProvider);
  final previous = await port.load();
  if (ref.read(sessionProvider).activeEpoch != epoch) return;
  final peers = previous.mutedPeerDids.toSet();
  if (muted) {
    peers.add(peer);
  } else {
    peers.remove(peer);
  }
  final next = await port.save(
    previous,
    enabled: previous.enabled,
    urgentEnabled: previous.urgentEnabled,
    mutedPeerDids: peers.toList(),
  );
  if (ref.read(sessionProvider).activeEpoch != epoch) return;
  await channel.invokeMethod<bool>('configureTextNotify', {
    ...next.json,
    'target': args['target'],
    'muted_identities': next.mutedPeerDids
        .map(remotePushOpaqueIdentityReference)
        .toList(),
  });
  await channel.invokeMethod<bool>('muteTextNotifyConversation', args);
}
