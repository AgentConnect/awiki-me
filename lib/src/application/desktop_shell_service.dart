import 'dart:async';

enum DesktopShellEventType { activate, requestExit, shutdownForUpdate }

final class DesktopShellEvent {
  const DesktopShellEvent(this.type);

  final DesktopShellEventType type;

  static DesktopShellEvent? tryParse(Object? arguments) {
    if (arguments is! Map || arguments.length != 1) {
      return null;
    }
    final type = arguments['type'];
    if (type is! String) {
      return null;
    }
    return switch (type) {
      'activate' => const DesktopShellEvent(DesktopShellEventType.activate),
      'requestExit' => const DesktopShellEvent(
        DesktopShellEventType.requestExit,
      ),
      'shutdownForUpdate' => const DesktopShellEvent(
        DesktopShellEventType.shutdownForUpdate,
      ),
      _ => null,
    };
  }
}

final class DesktopStorageRoots {
  const DesktopStorageRoots({
    required this.support,
    required this.cache,
    required this.temp,
  });

  final String support;
  final String cache;
  final String temp;
}

abstract interface class DesktopShellService {
  Stream<DesktopShellEvent> get events;

  Future<void> initialize();

  Future<DesktopStorageRoots> getStorageRoots();

  Future<void> showWindow();

  Future<void> hideWindow();

  Future<void> setUnreadCount(int count);

  Future<void> completeExit();

  Future<void> dispose();
}

final class NoopDesktopShellService implements DesktopShellService {
  const NoopDesktopShellService();

  @override
  Stream<DesktopShellEvent> get events =>
      const Stream<DesktopShellEvent>.empty();

  @override
  Future<void> completeExit() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<DesktopStorageRoots> getStorageRoots() {
    throw UnsupportedError('desktop_storage_roots_unavailable');
  }

  @override
  Future<void> hideWindow() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setUnreadCount(int count) async {}

  @override
  Future<void> showWindow() async {}
}

final class DesktopShellLifecycleCoordinator {
  DesktopShellLifecycleCoordinator({required DesktopShellService shell})
    : _shell = shell;

  final DesktopShellService _shell;
  Future<void>? _exitOperation;

  Future<void> handle(
    DesktopShellEvent event, {
    required Future<void> Function() disposeRuntime,
  }) async {
    if (event.type == DesktopShellEventType.activate) {
      await _shell.showWindow();
      return;
    }
    final active = _exitOperation;
    if (active != null) {
      return active;
    }
    late final Future<void> operation;
    operation =
        (() async {
          await disposeRuntime();
          await _shell.completeExit();
        })().whenComplete(() {
          if (identical(_exitOperation, operation)) {
            _exitOperation = null;
          }
        });
    _exitOperation = operation;
    return operation;
  }
}
