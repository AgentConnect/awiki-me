import 'dart:async';

enum DesktopShellEventType { activate, requestExit, shutdownForUpdate }

enum DesktopShellExitIssue { cleanupTimedOut, cleanupFailed, completionFailed }

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
  DesktopShellLifecycleCoordinator({
    required DesktopShellService shell,
    Duration cleanupTimeout = const Duration(seconds: 10),
    void Function(DesktopShellExitIssue issue)? onExitIssue,
  }) : assert(cleanupTimeout > Duration.zero),
       _shell = shell,
       _cleanupTimeout = cleanupTimeout,
       _onExitIssue = onExitIssue;

  final DesktopShellService _shell;
  final Duration _cleanupTimeout;
  final void Function(DesktopShellExitIssue issue)? _onExitIssue;
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
          try {
            await disposeRuntime().timeout(_cleanupTimeout);
          } on TimeoutException {
            _reportIssue(DesktopShellExitIssue.cleanupTimedOut);
          } on Object {
            _reportIssue(DesktopShellExitIssue.cleanupFailed);
          }
          try {
            await _shell.completeExit();
          } on Object {
            _reportIssue(DesktopShellExitIssue.completionFailed);
            rethrow;
          }
        })().whenComplete(() {
          if (identical(_exitOperation, operation)) {
            _exitOperation = null;
          }
        });
    _exitOperation = operation;
    return operation;
  }

  void _reportIssue(DesktopShellExitIssue issue) {
    try {
      _onExitIssue?.call(issue);
    } on Object {
      // Diagnostics must never become another exit precondition.
    }
  }
}
