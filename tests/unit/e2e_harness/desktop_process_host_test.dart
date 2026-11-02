import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/desktop_process_host.dart';

void main() {
  test('Windows foreground CLI keeps argv separate from the ConPTY bridge', () {
    const host = DesktopProcessHost(DesktopHostPlatform.windows);
    final args = host.foregroundArguments(r'C:\AWiki cli\awiki-cli.exe', [
      'a b',
      'x&y',
    ]);
    expect(args.first, endsWith('pty_bridge.cjs'));
    expect(args.skip(1), [r'C:\AWiki cli\awiki-cli.exe', 'a b', 'x&y']);
  });

  test(
    'Windows foreground child has a terminal and bounded tree cleanup',
    () async {
      final host = DesktopProcessHost.current();
      expect(host.isAvailable, isTrue);
      final node = (await Process.run('node', [
        '-p',
        'process.execPath',
      ])).stdout.toString().trim();
      expect(File(node).existsSync(), isTrue);
      final isolatedHome = await Directory.systemTemp.createTemp('awiki-pty-');
      addTearDown(() => isolatedHome.delete(recursive: true));
      final process = await host.startForeground(
        node,
        [
          '-e',
          "console.log('AWIKI_TTY:' + !!process.stdin.isTTY); setInterval(() => {}, 1000);",
        ],
        environment: {...Platform.environment, 'HOME': isolatedHome.path},
      );
      final ready = Completer<void>();
      final transcript = StringBuffer();
      final output = process.stdout.transform(utf8.decoder).listen((text) {
        transcript.write(text);
        final clean = transcript.toString().replaceAll(
          RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'),
          '',
        );
        if (clean.contains('AWIKI_TTY:true') && !ready.isCompleted) {
          ready.complete();
        }
      });
      final errors = process.stderr.drain<void>();
      try {
        await ready.future.timeout(const Duration(seconds: 10));
        expect(process.kill(ProcessSignal.sigkill), isTrue);
        await process.exitCode.timeout(const Duration(seconds: 5));
      } finally {
        process.kill(ProcessSignal.sigkill);
        await output.cancel();
        await errors;
      }
    },
    skip: !Platform.isWindows,
  );

  test('macOS foreground CLI keeps argv structured', () {
    const host = DesktopProcessHost(DesktopHostPlatform.macos);

    expect(
      host.foregroundArguments('/opt/awiki cli', <String>['a b', "c'd"]),
      <String>['-q', '/dev/null', '/opt/awiki cli', 'a b', "c'd"],
    );
  });

  test('Linux foreground CLI quotes every shell word for script command', () {
    const host = DesktopProcessHost(DesktopHostPlatform.linux);

    expect(
      host.foregroundArguments('/opt/awiki cli', <String>['a b', "c'd"]),
      <String>[
        '-q',
        '-e',
        '-c',
        "'/opt/awiki cli' 'a b' 'c'\"'\"'d'",
        '/dev/null',
      ],
    );
  });

  test('foreground CLI rejects an ambiguous executable', () {
    const host = DesktopProcessHost(DesktopHostPlatform.linux);

    expect(
      () => host.foregroundArguments(' /opt/awiki', const <String>[]),
      throwsArgumentError,
    );
  });
}
