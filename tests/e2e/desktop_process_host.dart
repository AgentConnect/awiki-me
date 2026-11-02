import 'dart:async';
import 'dart:io';
import 'desktop_subprocess_environment.dart';

enum DesktopHostPlatform { macos, linux, windows }

/// The narrow host boundary used by desktop product E2E processes.
///
/// Business scenarios provide an executable and argv. This adapter owns the
/// host-specific pseudo-terminal invocation needed by interactive CLI flows.
final class DesktopProcessHost {
  const DesktopProcessHost(this.platform);

  factory DesktopProcessHost.current() {
    if (Platform.isMacOS) {
      return const DesktopProcessHost(DesktopHostPlatform.macos);
    }
    if (Platform.isLinux) {
      return const DesktopProcessHost(DesktopHostPlatform.linux);
    }
    if (Platform.isWindows) {
      return const DesktopProcessHost(DesktopHostPlatform.windows);
    }
    throw UnsupportedError('desktop_e2e_host_unsupported');
  }

  final DesktopHostPlatform platform;

  String get pseudoTerminalExecutable => platform == DesktopHostPlatform.windows
      ? (Platform.environment['AWIKI_E2E_NODE_BIN'] ?? 'node')
      : '/usr/bin/script';

  String get windowsBridge =>
      Platform.environment['AWIKI_E2E_WINDOWS_PTY_BRIDGE'] ??
      File('tests/e2e/windows/pty_bridge.cjs').absolute.path;

  bool get isAvailable {
    if (platform != DesktopHostPlatform.windows) {
      return File(pseudoTerminalExecutable).existsSync();
    }
    if (!Platform.isWindows || !File(windowsBridge).existsSync()) return false;
    try {
      return Process.runSync(pseudoTerminalExecutable, [
            windowsBridge,
            '--check',
          ]).exitCode ==
          0;
    } on ProcessException {
      return false;
    }
  }

  List<String> foregroundArguments(String executable, List<String> arguments) {
    if (executable.trim().isEmpty || executable != executable.trim()) {
      throw ArgumentError.value(executable, 'executable');
    }
    return switch (platform) {
      DesktopHostPlatform.macos => <String>[
        '-q',
        '/dev/null',
        executable,
        ...arguments,
      ],
      DesktopHostPlatform.linux => <String>[
        '-q',
        '-e',
        '-c',
        <String>[executable, ...arguments].map(_quotePosix).join(' '),
        '/dev/null',
      ],
      DesktopHostPlatform.windows => <String>[
        windowsBridge,
        executable,
        ...arguments,
      ],
    };
  }

  Future<Process> startForeground(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
  }) async {
    if (!isAvailable) {
      throw StateError('desktop_e2e_pseudo_terminal_unavailable');
    }
    final process = await Process.start(
      pseudoTerminalExecutable,
      foregroundArguments(executable, arguments),
      environment: desktopSubprocessEnvironment(environment),
      includeParentEnvironment: false,
      runInShell: false,
    );
    return platform == DesktopHostPlatform.windows
        ? _WindowsPtyProcess(process)
        : process;
  }
}

/// ConPTY has a native child behind the Node transport. Kill only this owned
/// process tree so a timed-out SAS approval cannot leave an orphan CLI alive.
final class _WindowsPtyProcess implements Process {
  _WindowsPtyProcess(this.delegate) {
    unawaited(delegate.exitCode.then<void>((_) => _exited = true));
  }

  final Process delegate;
  bool _exited = false;
  @override
  int get pid => delegate.pid;
  @override
  Future<int> get exitCode => delegate.exitCode;
  @override
  IOSink get stdin => delegate.stdin;
  @override
  Stream<List<int>> get stdout => delegate.stdout;
  @override
  Stream<List<int>> get stderr => delegate.stderr;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_exited) return false;
    try {
      return Process.runSync('taskkill.exe', [
            '/PID',
            '$pid',
            '/T',
            '/F',
          ]).exitCode ==
          0;
    } on ProcessException {
      return false;
    }
  }
}

String _quotePosix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
