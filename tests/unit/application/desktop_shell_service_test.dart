import 'dart:async';

import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event parser accepts only the strict shell event shape', () {
    expect(
      DesktopShellEvent.tryParse(const <String, Object?>{
        'type': 'activate',
      })?.type,
      DesktopShellEventType.activate,
    );
    expect(
      DesktopShellEvent.tryParse(const <String, Object?>{
        'type': 'requestExit',
      })?.type,
      DesktopShellEventType.requestExit,
    );
    expect(
      DesktopShellEvent.tryParse(const <String, Object?>{
        'type': 'shutdownForUpdate',
      })?.type,
      DesktopShellEventType.shutdownForUpdate,
    );
    expect(DesktopShellEvent.tryParse(null), isNull);
    expect(DesktopShellEvent.tryParse(const <String, Object?>{}), isNull);
    expect(
      DesktopShellEvent.tryParse(const <String, Object?>{'type': 'unknown'}),
      isNull,
    );
    expect(
      DesktopShellEvent.tryParse(const <String, Object?>{
        'type': 'activate',
        'extra': true,
      }),
      isNull,
    );
  });

  test('activation only restores the window', () async {
    final shell = _FakeDesktopShellService();
    final coordinator = DesktopShellLifecycleCoordinator(shell: shell);
    var disposeCalls = 0;

    await coordinator.handle(
      const DesktopShellEvent(DesktopShellEventType.activate),
      disposeRuntime: () async {
        disposeCalls += 1;
      },
    );

    expect(shell.actions, <String>['show']);
    expect(disposeCalls, 0);
  });

  test(
    'concurrent exit requests dispose once before completing exit',
    () async {
      final shell = _FakeDesktopShellService();
      final coordinator = DesktopShellLifecycleCoordinator(shell: shell);
      final releaseDispose = Completer<void>();
      var disposeCalls = 0;
      Future<void> disposeRuntime() async {
        disposeCalls += 1;
        shell.actions.add('dispose-start');
        await releaseDispose.future;
        shell.actions.add('dispose-end');
      }

      final first = coordinator.handle(
        const DesktopShellEvent(DesktopShellEventType.requestExit),
        disposeRuntime: disposeRuntime,
      );
      final second = coordinator.handle(
        const DesktopShellEvent(DesktopShellEventType.shutdownForUpdate),
        disposeRuntime: disposeRuntime,
      );
      await Future<void>.delayed(Duration.zero);

      expect(disposeCalls, 1);
      expect(shell.actions, <String>['dispose-start']);
      releaseDispose.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(shell.actions, <String>[
        'dispose-start',
        'dispose-end',
        'complete',
      ]);
    },
  );

  test('failed runtime disposal does not confirm a safe exit', () async {
    final shell = _FakeDesktopShellService();
    final coordinator = DesktopShellLifecycleCoordinator(shell: shell);

    await expectLater(
      coordinator.handle(
        const DesktopShellEvent(DesktopShellEventType.requestExit),
        disposeRuntime: () async => throw StateError('dispose failed'),
      ),
      throwsStateError,
    );

    expect(shell.actions, isEmpty);
  });
}

final class _FakeDesktopShellService implements DesktopShellService {
  final List<String> actions = <String>[];

  @override
  Stream<DesktopShellEvent> get events =>
      const Stream<DesktopShellEvent>.empty();

  @override
  Future<void> completeExit() async => actions.add('complete');

  @override
  Future<void> dispose() async {}

  @override
  Future<DesktopStorageRoots> getStorageRoots() async =>
      const DesktopStorageRoots(
        support: 'support',
        cache: 'cache',
        temp: 'temp',
      );

  @override
  Future<void> hideWindow() async => actions.add('hide');

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setUnreadCount(int count) async {}

  @override
  Future<void> showWindow() async => actions.add('show');
}
