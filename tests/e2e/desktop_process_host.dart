import 'dart:io';

enum DesktopHostPlatform { macos, linux }

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
    throw UnsupportedError('desktop_e2e_host_unsupported');
  }

  final DesktopHostPlatform platform;

  String get pseudoTerminalExecutable => '/usr/bin/script';

  bool get isAvailable => File(pseudoTerminalExecutable).existsSync();

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
    };
  }

  Future<Process> startForeground(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (!isAvailable) {
      throw StateError('desktop_e2e_pseudo_terminal_unavailable');
    }
    return Process.start(
      pseudoTerminalExecutable,
      foregroundArguments(executable, arguments),
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
  }
}

String _quotePosix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
