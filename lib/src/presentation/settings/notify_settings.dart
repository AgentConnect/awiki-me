import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/remote_push_message_reference.dart';
import '../app_shell/providers/session_provider.dart';
import '../app_shell/providers/remote_push_coordinator_provider.dart';

// Device-local, account-scoped settings. No User Service RPC or installation schema changes.
class NotifyPreference {
  const NotifyPreference({
    required this.enabled,
    required this.urgentEnabled,
    this.mutesReady = false,
  });
  final bool enabled;
  final bool urgentEnabled;
  final bool mutesReady;
  factory NotifyPreference.fromJson(Map<String, Object?> value) {
    if (value['enabled'] is! bool || value['urgent_enabled'] is! bool) {
      throw const FormatException('Invalid local Notify preference');
    }
    return NotifyPreference(
      enabled: value['enabled'] as bool,
      urgentEnabled: value['urgent_enabled'] as bool,
      mutesReady: value['mutes_ready'] == true,
    );
  }
}

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
  final List<Timer> _timeouts = <Timer>[];
  static const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    request++;
    for (final timer in _timeouts) {
      timer.cancel();
    }
    _timeouts.clear();
    super.dispose();
  }

  Future<T> _withinTimeout<T>(Future<T> future) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 3), () {
      _timeouts.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('notify_settings_timeout'));
      }
    });
    _timeouts.add(timer);
    future.then(
      (value) {
        if (timer.isActive) {
          timer.cancel();
          _timeouts.remove(timer);
        }
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (timer.isActive) {
          timer.cancel();
          _timeouts.remove(timer);
        }
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );
    return completer.future;
  }

  Future<void> load() async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    final id = ++request;
    if (epoch == null) {
      if (mounted) {
        setState(() {
          busy = false;
          value = null;
        });
      }
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = await _withinTimeout(
        channel.invokeMapMethod<String, Object?>(
          'getTextNotifyPreferenceState',
          remotePushOpaqueTargetReference(epoch.ownerDid),
        ),
      );
      if (!mounted ||
          id != request ||
          ref.read(sessionProvider).activeEpoch != epoch) {
        return;
      }
      if (values == null) throw StateError('notify_local_scope_unavailable');
      final next = NotifyPreference.fromJson(values);
      setState(() {
        value = next;
        busy = false;
      });
    } on Object {
      if (mounted && id == request) {
        setState(() {
          busy = false;
          error = '无法读取本机通知设置，请重试。';
        });
      }
    }
  }

  Future<void> save({required bool enabled, required bool urgent}) async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (value == null || epoch == null || busy) return;
    final id = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final applied = await channel.invokeMethod<bool>('configureTextNotify', {
        'target': remotePushOpaqueTargetReference(epoch.ownerDid),
        'enabled': enabled,
        'urgent_enabled': urgent,
      });
      if (!mounted ||
          id != request ||
          ref.read(sessionProvider).activeEpoch != epoch) {
        return;
      }
      if (applied != true) throw StateError('notify_local_write_failed');
      setState(() {
        value = NotifyPreference(
          enabled: enabled,
          urgentEnabled: urgent,
          mutesReady: value!.mutesReady,
        );
        busy = false;
      });
    } on Object {
      if (mounted && id == request) {
        setState(() {
          busy = false;
          error = '本机通知设置未保存，请重试。';
        });
      }
    }
  }

  Future<void> retryMuteSync() async {
    final context = ref.read(currentTextNotifySessionContextProvider);
    if (context == null || busy) return;
    final id = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(textNotifyMuteCoordinatorProvider).ensureReady(context);
      if (!mounted || id != request) return;
      await load();
    } on Object {
      if (!mounted || id != request) return;
      setState(() {
        busy = false;
        error = '会话免打扰同步失败，任务提醒仍已暂停。请重试。';
      });
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
          subtitle: const Text('仅控制当前账号在这台手机上的任务提醒'),
          trailing: CupertinoSwitch(
            value: value?.enabled ?? false,
            onChanged: busy || value == null
                ? null
                : (v) => save(enabled: v, urgent: value!.urgentEnabled),
          ),
        ),
        CupertinoListTile(
          title: const Text('紧急提醒'),
          subtitle: const Text('允许收到的紧急任务消息持续提醒，最长 60 秒'),
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
        if (!busy && value?.mutesReady == false)
          CupertinoListTile(
            title: const Text('会话免打扰尚未同步，任务提醒已暂停。', maxLines: 3),
            trailing: CupertinoButton(
              onPressed: retryMuteSync,
              child: const Text('同步设置'),
            ),
          ),
        if (busy)
          const CupertinoListTile(
            title: Text('正在读取本机设置…'),
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
