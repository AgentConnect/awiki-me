import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _mobileScenario = 'mobile-two-device';
const _mobileCaseIds = <String>['MOBILE-E2E-001'];
const _mobileDryRunSkippedReason =
    'dry-run: device preparation, installation, and Maestro flows skipped';

Future<void> main(List<String> args) async {
  try {
    final options = RunnerOptions.parse(args);
    if (options.help) {
      RunnerOptions.printUsage();
      return;
    }

    final root = Directory.current;
    final config = E2eConfig.load(File(options.configPath));
    final runner = E2eRunner(root: root, config: config, options: options);
    await runner.run();
  } on E2eFailure catch (error) {
    stderr.writeln('\nE2E failed: ${error.message}');
    exitCode = 1;
  }
}

class E2eRunner {
  E2eRunner({required this.root, required this.config, required this.options})
    : commands = CommandRunner(root: root, dryRun: options.dryRun);

  final Directory root;
  final E2eConfig config;
  final RunnerOptions options;
  final CommandRunner commands;

  late final Directory reportDir;
  final List<E2eTimingEntry> _timings = <E2eTimingEntry>[];
  late final String _runId;
  late final Map<String, Object?> _messagePlan;
  DevicePair? _preparedDevices;

  Future<void> run() async {
    final totalStopwatch = Stopwatch()..start();
    var succeeded = false;
    _runId = _newRunId();
    reportDir = Directory('${root.path}/.e2e/reports/$_runId')
      ..createSync(recursive: true);
    _messagePlan = _buildMessagePlan(_runId);

    try {
      _section('AWiki Me E2E $_runId');
      _line('platform: ${config.platform.name}');
      _line('reports: ${reportDir.path}');

      await _timed('Checking tooling', _checkTooling);
      if (!options.skipBuild) {
        await _timed('Building app', _buildApp);
      }
      if (options.dryRun) {
        _section('Dry run completed');
        _line(_mobileDryRunSkippedReason);
        succeeded = true;
        return;
      }

      final devices = await _timed('Preparing devices', _prepareDevices);
      _preparedDevices = devices;
      await _timed('Installing app', () => _installApp(devices));

      await _timed('Logging in ${devices.a.label}', () {
        return _login(devices.a, config.accounts.a);
      });
      await _timed('Logging in ${devices.b.label}', () {
        return _login(devices.b, config.accounts.b);
      });

      final messageAB =
          (_messagePlan['aToB'] as Map<String, Object?>)['text']! as String;
      final messageBA =
          (_messagePlan['bToA'] as Map<String, Object?>)['text']! as String;

      await _timed('Messaging A_TO_B', () {
        return _assertMessageDirection(
          sender: devices.a,
          receiver: devices.b,
          senderPeerHandle: config.accounts.b.handle,
          receiverPeerHandle: config.accounts.a.handle,
          message: messageAB,
          label: 'A_TO_B',
        );
      });
      await _timed('Messaging B_TO_A', () {
        return _assertMessageDirection(
          sender: devices.b,
          receiver: devices.a,
          senderPeerHandle: config.accounts.a.handle,
          receiverPeerHandle: config.accounts.b.handle,
          message: messageBA,
          label: 'B_TO_A',
        );
      });

      _section('E2E completed');
      _line('runId: $_runId');
      _line('A -> B: $messageAB');
      _line('B -> A: $messageBA');
      succeeded = true;
    } finally {
      totalStopwatch.stop();
      _printTimingSummary(
        succeeded: succeeded,
        totalElapsed: totalStopwatch.elapsed,
      );
    }
  }

  Future<T> _timed<T>(String name, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      stopwatch.stop();
      final entry = E2eTimingEntry(
        name: name,
        elapsed: stopwatch.elapsed,
        succeeded: succeeded,
      );
      _timings.add(entry);
      _line(
        'duration: ${_formatDuration(entry.elapsed)}'
        '${entry.succeeded ? '' : ' (failed)'}',
      );
    }
  }

  void _printTimingSummary({
    required bool succeeded,
    required Duration totalElapsed,
  }) {
    Object? reportError;
    try {
      _writeTimingReport(succeeded: succeeded, totalElapsed: totalElapsed);
    } catch (error) {
      reportError = error;
    }
    _section('Timing summary');
    _line('status: ${succeeded ? 'success' : 'failed'}');
    _line('total: ${_formatDuration(totalElapsed)}');
    for (final entry in _timings) {
      final status = entry.succeeded ? '' : ' (failed)';
      _line('${entry.name}: ${_formatDuration(entry.elapsed)}$status');
    }
    if (reportError == null) {
      _line('timings: ${reportDir.path}/timings.json');
    } else {
      _line('timings: unavailable ($reportError)');
    }
  }

  void _writeTimingReport({
    required bool succeeded,
    required Duration totalElapsed,
  }) {
    final file = File('${reportDir.path}/timings.json');
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(
      encoder.convert(<String, Object?>{
        'scenario': _mobileScenario,
        'caseIds': _mobileCaseIds,
        'runId': _runId,
        'status': succeeded ? 'success' : 'failed',
        'caseStatus': options.dryRun
            ? 'skipped'
            : succeeded
            ? 'pass'
            : 'fail',
        'skippedReason': options.dryRun ? _mobileDryRunSkippedReason : null,
        'dryRun': options.dryRun,
        'skipBuild': options.skipBuild,
        'platform': config.platform.name,
        'appId': config.appId,
        'configPath': _redactPath(options.configPath),
        'reportDir': _redactPath(reportDir.path),
        'service': _serviceReport(),
        'accounts': _accountsReport(),
        'devices': _devicesReport(),
        'messages': _messagePlan,
        'totalMs': totalElapsed.inMilliseconds,
        'total': _formatDuration(totalElapsed),
        'steps': [
          for (final entry in _timings)
            <String, Object?>{
              'name': entry.name,
              'status': entry.succeeded ? 'success' : 'failed',
              'elapsedMs': entry.elapsed.inMilliseconds,
              'elapsed': _formatDuration(entry.elapsed),
            },
        ],
      }),
    );
  }

  Map<String, Object?> _serviceReport() {
    return <String, Object?>{
      'baseUrl': _redactUrl(config.service.baseUrl),
      'userServiceUrl': _redactUrl(config.service.userServiceUrl),
      'messageServiceUrl': _redactUrl(config.service.messageServiceUrl),
      'didDomain': config.service.didDomain,
      if (config.service.anpServiceUrl != null)
        'anpServiceUrl': _redactUrl(config.service.anpServiceUrl!),
      if (config.service.anpServiceDid != null)
        'anpServiceDid': _redactIdentifier(config.service.anpServiceDid!),
    };
  }

  Map<String, Object?> _accountsReport() {
    return <String, Object?>{
      'a': <String, Object?>{'label': 'a', 'handle': config.accounts.a.handle},
      'b': <String, Object?>{'label': 'b', 'handle': config.accounts.b.handle},
    };
  }

  Map<String, Object?> _devicesReport() {
    final prepared = _preparedDevices;
    return <String, Object?>{
      'resetBeforeRun': config.device.resetBeforeRun,
      'configured': _configuredDevicesReport(),
      if (prepared != null)
        'prepared': <String, Object?>{
          'a': <String, Object?>{
            'label': prepared.a.label,
            'id': _redactIdentifier(prepared.a.id),
          },
          'b': <String, Object?>{
            'label': prepared.b.label,
            'id': _redactIdentifier(prepared.b.id),
          },
        },
    };
  }

  Map<String, Object?> _configuredDevicesReport() {
    return switch (config.platform) {
      E2ePlatform.ios => <String, Object?>{
        'type': 'ios-simulator',
        'deviceType': config.device.ios.deviceType,
        'runtime': config.device.ios.runtime,
        'a': _slotReport(
          label: 'a',
          name: config.device.ios.names.a,
          id: config.device.ios.ids.a,
        ),
        'b': _slotReport(
          label: 'b',
          name: config.device.ios.names.b,
          id: config.device.ios.ids.b,
        ),
      },
      E2ePlatform.android => <String, Object?>{
        'type': 'android-emulator-or-device',
        'a': _slotReport(
          label: 'a',
          name: config.device.android.avdNames.a,
          id: config.device.android.ids.a,
        ),
        'b': _slotReport(
          label: 'b',
          name: config.device.android.avdNames.b,
          id: config.device.android.ids.b,
        ),
      },
    };
  }

  Map<String, Object?> _slotReport({
    required String label,
    required String? name,
    required String? id,
  }) {
    return <String, Object?>{
      'label': label,
      'configuredBy': id == null ? 'name' : 'id',
      if (name != null) 'name': name,
      if (id != null) 'id': _redactIdentifier(id),
    };
  }

  Map<String, Object?> _buildMessagePlan(String runId) {
    final messageAB = 'awiki e2e $runId A_TO_B';
    final messageBA = 'awiki e2e $runId B_TO_A';
    return <String, Object?>{
      'aToB': <String, Object?>{
        'label': 'A_TO_B',
        'sender': 'a',
        'receiver': 'b',
        'text': messageAB,
        'messageId': _messageIdentifier(messageAB),
      },
      'bToA': <String, Object?>{
        'label': 'B_TO_A',
        'sender': 'b',
        'receiver': 'a',
        'text': messageBA,
        'messageId': _messageIdentifier(messageBA),
      },
    };
  }

  String _redactPath(String path) {
    final rootPath = root.path;
    if (path == rootPath) {
      return '<repo>';
    }
    if (path.startsWith('$rootPath${Platform.pathSeparator}')) {
      return '<repo>${path.substring(rootPath.length)}';
    }
    if (!path.startsWith('/') && !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return path;
    }
    return '<redacted-path>';
  }

  Future<void> _checkTooling() async {
    _section('Checking tooling');
    await commands.requireExecutable('flutter');
    await commands.requireExecutable('maestro');
    if (config.platform == E2ePlatform.ios) {
      await commands.requireExecutable('xcrun');
    } else {
      await commands.requireExecutable('adb');
    }
  }

  Future<void> _buildApp() async {
    _section('Building app');
    final defines = <String>[
      'AWIKI_E2E=true',
      'AWIKI_SERVICE_BASE_URL=${config.service.baseUrl}',
      'AWIKI_USER_SERVICE_URL=${config.service.userServiceUrl}',
      'AWIKI_MESSAGE_SERVICE_URL=${config.service.messageServiceUrl}',
      'AWIKI_DID_DOMAIN=${config.service.didDomain}',
      if (config.service.anpServiceUrl != null)
        'AWIKI_ANP_SERVICE_URL=${config.service.anpServiceUrl}',
      if (config.service.anpServiceDid != null)
        'AWIKI_ANP_SERVICE_DID=${config.service.anpServiceDid}',
    ];
    final defineArgs = [for (final define in defines) '--dart-define=$define'];
    switch (config.platform) {
      case E2ePlatform.ios:
        await commands.run('flutter', [
          'build',
          'ios',
          '--simulator',
          '--debug',
          ...defineArgs,
        ], timeout: const Duration(minutes: 20));
      case E2ePlatform.android:
        await commands.run('flutter', [
          'build',
          'apk',
          '--debug',
          ...defineArgs,
        ], timeout: const Duration(minutes: 20));
    }
  }

  Future<DevicePair> _prepareDevices() async {
    _section('Preparing devices');
    switch (config.platform) {
      case E2ePlatform.ios:
        return IosDeviceManager(commands, config).prepare();
      case E2ePlatform.android:
        return AndroidDeviceManager(commands, config, reportDir).prepare();
    }
  }

  Future<void> _installApp(DevicePair devices) async {
    _section('Installing app');
    switch (config.platform) {
      case E2ePlatform.ios:
        final appPath = '${root.path}/build/ios/iphonesimulator/Runner.app';
        if (!Directory(appPath).existsSync() && !options.dryRun) {
          throw E2eFailure('iOS build output was not found: $appPath');
        }
        for (final device in [devices.a, devices.b]) {
          if (config.device.resetBeforeRun) {
            await commands.run('xcrun', [
              'simctl',
              'uninstall',
              device.id,
              config.appId,
            ], allowFailure: true);
          }
          await commands.run('xcrun', [
            'simctl',
            'install',
            device.id,
            appPath,
          ]);
        }
      case E2ePlatform.android:
        final apkPath =
            '${root.path}/build/app/outputs/flutter-apk/app-debug.apk';
        if (!File(apkPath).existsSync() && !options.dryRun) {
          throw E2eFailure('Android build output was not found: $apkPath');
        }
        for (final device in [devices.a, devices.b]) {
          if (config.device.resetBeforeRun) {
            await commands.run('adb', [
              '-s',
              device.id,
              'uninstall',
              config.appId,
            ], allowFailure: true);
          }
          await commands.run('adb', [
            '-s',
            device.id,
            'install',
            '-r',
            apkPath,
          ]);
        }
    }
  }

  Future<void> _login(E2eDevice device, E2eAccount account) async {
    _section('Logging in ${device.label}');
    await _runMaestro(
      device,
      'tests/e2e_test/mobile/maestro/login.yaml',
      {
        'PHONE': account.phone,
        'HANDLE': account.handle,
        'OTP_SEND_TIMEOUT_MS': '120000',
        'OTP_TIMEOUT_MS': '${config.otp.timeout.inMilliseconds}',
      },
      label: 'login-${device.label}',
      timeout: config.otp.timeout + const Duration(minutes: 3),
    );
  }

  Future<void> _assertMessageDirection({
    required E2eDevice sender,
    required E2eDevice receiver,
    required String senderPeerHandle,
    required String receiverPeerHandle,
    required String message,
    required String label,
  }) async {
    _section('Messaging $label');
    final wait = await _startMaestro(
      receiver,
      'tests/e2e_test/mobile/maestro/open_chat_and_wait.yaml',
      {
        'PEER_HANDLE': receiverPeerHandle,
        'MESSAGE_TEXT': message,
        'MESSAGE_ID': _messageIdentifier(message),
        'MESSAGE_TIMEOUT_MS': '${config.message.waitTimeout.inMilliseconds}',
      },
      label: 'wait-$label-${receiver.label}',
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      await _runMaestro(
        sender,
        'tests/e2e_test/mobile/maestro/open_chat_and_send.yaml',
        {
          'PEER_HANDLE': senderPeerHandle,
          'MESSAGE_TEXT': message,
          'MESSAGE_ID': _messageIdentifier(message),
          'MESSAGE_TIMEOUT_MS': '${config.message.waitTimeout.inMilliseconds}',
        },
        label: 'send-$label-${sender.label}',
        timeout: config.message.waitTimeout + const Duration(minutes: 2),
      );
      await wait.wait(
        timeout: config.message.waitTimeout + const Duration(minutes: 3),
      );
    } catch (_) {
      wait.kill();
      rethrow;
    }
  }

  Future<void> _runMaestro(
    E2eDevice device,
    String flowPath,
    Map<String, String> env, {
    required String label,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final process = await _startMaestro(device, flowPath, env, label: label);
    await process.wait(timeout: timeout);
  }

  Future<RunningProcess> _startMaestro(
    E2eDevice device,
    String flowPath,
    Map<String, String> env, {
    required String label,
  }) {
    final mergedEnv = <String, String>{'APP_ID': config.appId, ...env};
    final args = <String>[
      '--device',
      device.id,
      'test',
      for (final entry in mergedEnv.entries) ...[
        '--env',
        '${entry.key}=${entry.value}',
      ],
      flowPath,
    ];
    return commands.start(
      'maestro',
      args,
      label: label,
      logFile: File('${reportDir.path}/$label.log'),
    );
  }
}

class IosDeviceManager {
  IosDeviceManager(this.commands, this.config);

  final CommandRunner commands;
  final E2eConfig config;

  Future<DevicePair> prepare() async {
    final ids = config.device.ios.ids;
    final a =
        ids.a ??
        await _ensureDevice(config.device.ios.names.a ?? 'awiki-e2e-ios-a');
    final b =
        ids.b ??
        await _ensureDevice(config.device.ios.names.b ?? 'awiki-e2e-ios-b');
    if (a == b) {
      throw E2eFailure('iOS E2E requires two different simulator UDIDs.');
    }
    for (final deviceId in [a, b]) {
      if (config.device.resetBeforeRun) {
        await commands.run('xcrun', [
          'simctl',
          'shutdown',
          deviceId,
        ], allowFailure: true);
        await commands.run('xcrun', ['simctl', 'erase', deviceId]);
      }
      await commands.run('xcrun', [
        'simctl',
        'boot',
        deviceId,
      ], allowFailure: true);
      await commands.run('xcrun', ['simctl', 'bootstatus', deviceId, '-b']);
    }
    return DevicePair(
      a: E2eDevice(label: 'a', id: a),
      b: E2eDevice(label: 'b', id: b),
    );
  }

  Future<String> _ensureDevice(String name) async {
    final existing = await _findDeviceByName(name);
    if (existing != null) {
      return existing;
    }
    final typeId = await _resolveDeviceType(config.device.ios.deviceType);
    final runtimeId = await _resolveRuntime(config.device.ios.runtime);
    final args = <String>['simctl', 'create', name, typeId];
    if (runtimeId != null) {
      args.add(runtimeId);
    }
    final result = await commands.capture('xcrun', args);
    final udid = result.trim();
    if (udid.isEmpty) {
      throw E2eFailure(
        'simctl did not return a UDID for created device $name.',
      );
    }
    return udid;
  }

  Future<String?> _findDeviceByName(String name) async {
    final result = await commands.capture('xcrun', [
      'simctl',
      'list',
      'devices',
      '--json',
    ]);
    final decoded = jsonDecode(result) as Map<String, dynamic>;
    final devicesByRuntime = decoded['devices'] as Map<String, dynamic>;
    for (final runtimeDevices in devicesByRuntime.values) {
      for (final item in runtimeDevices as List<dynamic>) {
        final device = item as Map<String, dynamic>;
        if (device['name'] == name && device['isAvailable'] != false) {
          return device['udid'] as String;
        }
      }
    }
    return null;
  }

  Future<String> _resolveDeviceType(String? value) async {
    final requested = value?.trim();
    if (requested != null &&
        requested.startsWith('com.apple.CoreSimulator.SimDeviceType.')) {
      return requested;
    }
    final result = await commands.capture('xcrun', [
      'simctl',
      'list',
      'devicetypes',
      '--json',
    ]);
    final decoded = jsonDecode(result) as Map<String, dynamic>;
    final deviceTypes = decoded['devicetypes'] as List<dynamic>;
    String? latestIphone;
    for (final item in deviceTypes) {
      final deviceType = item as Map<String, dynamic>;
      final name = deviceType['name'] as String;
      final identifier = deviceType['identifier'] as String;
      if (name.startsWith('iPhone ')) {
        latestIphone = identifier;
      }
      if (requested != null && (name == requested || identifier == requested)) {
        return identifier;
      }
    }
    if (requested == null || requested.isEmpty) {
      if (latestIphone != null) {
        _line('Using iOS simulator device type $latestIphone.');
        return latestIphone;
      }
      throw E2eFailure('Could not find an installed iPhone simulator type.');
    }
    throw E2eFailure('Could not find iOS simulator device type "$requested".');
  }

  Future<String?> _resolveRuntime(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    if (value.startsWith('com.apple.CoreSimulator.SimRuntime.')) {
      return value;
    }
    final result = await commands.capture('xcrun', [
      'simctl',
      'list',
      'runtimes',
      '--json',
    ]);
    final decoded = jsonDecode(result) as Map<String, dynamic>;
    final runtimes = decoded['runtimes'] as List<dynamic>;
    for (final item in runtimes) {
      final runtime = item as Map<String, dynamic>;
      if (runtime['isAvailable'] == false) {
        continue;
      }
      final name = runtime['name'] as String;
      final identifier = runtime['identifier'] as String;
      if (name == value || identifier == value || name.contains(value)) {
        return identifier;
      }
    }
    throw E2eFailure('Could not find iOS simulator runtime "$value".');
  }
}

class AndroidDeviceManager {
  AndroidDeviceManager(this.commands, this.config, this.reportDir);

  final CommandRunner commands;
  final E2eConfig config;
  final Directory reportDir;

  Future<DevicePair> prepare() async {
    final ids = config.device.android.ids;
    final a = ids.a;
    final b = ids.b;
    if ((a == null) != (b == null)) {
      throw E2eFailure(
        'Configure both android.ids.a and android.ids.b, or omit both.',
      );
    }
    if (a != null && b != null) {
      if (a == b) {
        throw E2eFailure('Android E2E requires two different device IDs.');
      }
      await _waitForBoot(a);
      await _waitForBoot(b);
      return DevicePair(
        a: E2eDevice(label: 'a', id: a),
        b: E2eDevice(label: 'b', id: b),
      );
    }

    final avds = config.device.android.avdNames;
    if ((avds.a == null) != (avds.b == null)) {
      throw E2eFailure(
        'Configure both android.avdNames.a and android.avdNames.b, or omit both.',
      );
    }
    if (avds.a != null && avds.b != null) {
      if (avds.a == avds.b) {
        throw E2eFailure(
          'Use two independent Android AVDs; one read-only multi-instance AVD '
          'is not suitable for this real-login flow.',
        );
      }
      await _startAvd(avds.a!, 'android-emulator-a');
      await _startAvd(avds.b!, 'android-emulator-b');
      final pair = await _waitForAvdPair(avds.a!, avds.b!);
      await _waitForBoot(pair.a.id);
      await _waitForBoot(pair.b.id);
      return pair;
    }

    final connected = await _listAndroidDevices();
    if (connected.length < 2) {
      throw E2eFailure(
        'No Android ids or avdNames were configured, and fewer than two '
        'connected Android devices are available.',
      );
    }
    return DevicePair(
      a: E2eDevice(label: 'a', id: connected[0]),
      b: E2eDevice(label: 'b', id: connected[1]),
    );
  }

  Future<void> _startAvd(String avdName, String label) async {
    final runningSerial = await _serialForAvd(avdName);
    if (runningSerial != null) {
      _line('$label already running as $runningSerial.');
      return;
    }
    final emulator = await _findExecutable('emulator');
    if (emulator == null) {
      throw E2eFailure(
        'Could not find Android emulator binary. Add Android SDK emulator to '
        'PATH, or set ANDROID_HOME/ANDROID_SDK_ROOT.',
      );
    }
    await commands.start(
      emulator,
      ['-avd', avdName, '-no-snapshot-save'],
      label: label,
      logFile: File('${reportDir.path}/$label.log'),
      checkExit: false,
      detached: true,
    );
  }

  Future<DevicePair> _waitForAvdPair(String avdA, String avdB) async {
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      final devices = await _listAndroidDevices();
      String? serialA;
      String? serialB;
      for (final serial in devices) {
        final name = await _avdNameFor(serial);
        if (name == avdA) {
          serialA = serial;
        } else if (name == avdB) {
          serialB = serial;
        }
      }
      if (serialA != null && serialB != null) {
        return DevicePair(
          a: E2eDevice(label: 'a', id: serialA),
          b: E2eDevice(label: 'b', id: serialB),
        );
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw E2eFailure('Timed out waiting for Android AVDs $avdA and $avdB.');
  }

  Future<String?> _serialForAvd(String avdName) async {
    final devices = await _listAndroidDevices();
    for (final serial in devices) {
      final name = await _avdNameFor(serial);
      if (name == avdName) {
        return serial;
      }
    }
    return null;
  }

  Future<List<String>> _listAndroidDevices() async {
    final output = await commands.capture('adb', ['devices']);
    final devices = <String>[];
    for (final line in const LineSplitter().convert(output).skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.contains('\tdevice')) {
        continue;
      }
      devices.add(trimmed.split(RegExp(r'\s+')).first);
    }
    return devices;
  }

  Future<String?> _avdNameFor(String serial) async {
    final result = await commands.capture('adb', [
      '-s',
      serial,
      'emu',
      'avd',
      'name',
    ], allowFailure: true);
    final lines = const LineSplitter()
        .convert(result)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line != 'OK')
        .toList();
    return lines.isEmpty ? null : lines.first;
  }

  Future<void> _waitForBoot(String serial) async {
    await commands.run('adb', ['-s', serial, 'wait-for-device']);
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      final output = await commands.capture('adb', [
        '-s',
        serial,
        'shell',
        'getprop',
        'sys.boot_completed',
      ], allowFailure: true);
      if (output.trim() == '1') {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw E2eFailure('Timed out waiting for Android device $serial to boot.');
  }
}

class CommandRunner {
  CommandRunner({
    required this.root,
    required this.dryRun,
    void Function(String line)? logLine,
  }) : _logLine = logLine ?? _line;

  final Directory root;
  final bool dryRun;
  final void Function(String line) _logLine;

  Future<void> requireExecutable(String executable) async {
    final result = await capture(Platform.isWindows ? 'where' : 'which', [
      executable,
    ], allowFailure: true);
    final path = result.trim();
    if (path.isEmpty && !dryRun) {
      throw E2eFailure('Required executable was not found: $executable');
    }
    _logLine(
      '$executable: ${path.isEmpty ? 'dry-run' : path.split('\n').first}',
    );
  }

  Future<void> run(
    String executable,
    List<String> args, {
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final process = await start(
      executable,
      args,
      label: executable,
      checkExit: !allowFailure,
    );
    final exit = await process.wait(timeout: timeout);
    if (exit != 0 && !allowFailure) {
      throw E2eFailure('$executable exited with code $exit.');
    }
  }

  Future<String> capture(
    String executable,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    _command(executable, args, logLine: _logLine);
    if (dryRun) {
      return '';
    }
    final result = await Process.run(
      executable,
      args,
      workingDirectory: root.path,
      runInShell: false,
    );
    final out = (result.stdout as String?) ?? '';
    final err = (result.stderr as String?) ?? '';
    if (result.exitCode != 0 && !allowFailure) {
      throw E2eFailure(
        '$executable ${args.join(' ')} failed with code ${result.exitCode}.\n'
        '$err',
      );
    }
    return out.isNotEmpty ? out : err;
  }

  Future<RunningProcess> start(
    String executable,
    List<String> args, {
    required String label,
    File? logFile,
    bool checkExit = true,
    bool detached = false,
  }) async {
    _command(executable, args, logLine: _logLine);
    if (dryRun) {
      return RunningProcess.fake(label);
    }
    final process = await Process.start(
      executable,
      args,
      workingDirectory: root.path,
      runInShell: false,
      mode: detached ? ProcessStartMode.detached : ProcessStartMode.normal,
    );
    if (detached) {
      _line('[$label] started detached process ${process.pid}');
      return RunningProcess.fake(label);
    }
    final sink = logFile?.openWrite(mode: FileMode.writeOnlyAppend);
    _pipe(process.stdout, label, sink);
    _pipe(process.stderr, label, sink, isError: true);
    return RunningProcess(
      label: label,
      process: process,
      sink: sink,
      checkExit: checkExit,
      logFile: logFile,
    );
  }
}

class RunningProcess {
  RunningProcess({
    required this.label,
    required this.process,
    required this.sink,
    required this.checkExit,
    this.logFile,
  });

  RunningProcess.fake(this.label)
    : process = null,
      sink = null,
      checkExit = false,
      logFile = null;

  final String label;
  final Process? process;
  final IOSink? sink;
  final bool checkExit;
  final File? logFile;

  Future<int> wait({Duration timeout = const Duration(minutes: 5)}) async {
    final current = process;
    if (current == null) {
      return 0;
    }
    final exit = await current.exitCode.timeout(
      timeout,
      onTimeout: () {
        current.kill();
        throw E2eFailure(
          '$label timed out after ${timeout.inSeconds}s.'
          '${_logHint()}',
        );
      },
    );
    await sink?.flush();
    await sink?.close();
    if (exit != 0 && checkExit) {
      throw E2eFailure('$label exited with code $exit.${_logHint()}');
    }
    return exit;
  }

  void kill() {
    process?.kill();
  }

  String _logHint() {
    final path = logFile?.path;
    if (path == null || path.isEmpty) {
      return '';
    }
    return ' See log: $path';
  }
}

class E2eTimingEntry {
  const E2eTimingEntry({
    required this.name,
    required this.elapsed,
    required this.succeeded,
  });

  final String name;
  final Duration elapsed;
  final bool succeeded;
}

class E2eConfig {
  E2eConfig({
    required this.platform,
    required this.app,
    required this.service,
    required this.device,
    required this.otp,
    required this.accounts,
    required this.message,
  });

  final E2ePlatform platform;
  final AppConfig app;
  final ServiceConfig service;
  final DeviceConfig device;
  final OtpConfig otp;
  final AccountsConfig accounts;
  final MessageConfig message;

  String get appId => switch (platform) {
    E2ePlatform.ios => app.iosId,
    E2ePlatform.android => app.androidId,
  };

  static E2eConfig load(File file) {
    if (!file.existsSync()) {
      throw E2eFailure('Config file does not exist: ${file.path}');
    }
    final yaml = loadYaml(file.readAsStringSync());
    final root = _toStringKeyMap(yaml, path: 'root');
    final platform = E2ePlatform.parse(_requiredString(root, 'platform'));
    return E2eConfig(
      platform: platform,
      app: AppConfig.fromMap(_mapAt(root, 'app')),
      service: ServiceConfig.fromMap(_mapAt(root, 'service')),
      device: DeviceConfig.fromMap(_mapAt(root, 'device')),
      otp: OtpConfig.fromMap(_mapAt(root, 'otp')),
      accounts: AccountsConfig.fromMap(_mapAt(root, 'accounts')),
      message: MessageConfig.fromMap(_mapAt(root, 'message')),
    );
  }
}

enum E2ePlatform {
  ios,
  android;

  static E2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'ios' => E2ePlatform.ios,
      'android' => E2ePlatform.android,
      'macos' => throw E2eFailure(
        'macOS is not supported in the first E2E version.',
      ),
      _ => throw E2eFailure(
        'Unsupported platform "$value". Use ios or android.',
      ),
    };
  }
}

class AppConfig {
  AppConfig({required this.androidId, required this.iosId});

  final String androidId;
  final String iosId;

  factory AppConfig.fromMap(Map<String, Object?> map) {
    return AppConfig(
      androidId: _stringAt(map, 'androidId', 'ai.awiki.awikime'),
      iosId: _stringAt(map, 'iosId', 'ai.awiki.awikime123'),
    );
  }
}

class ServiceConfig {
  ServiceConfig({
    required this.baseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.didDomain,
    this.anpServiceUrl,
    this.anpServiceDid,
  });

  final String baseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String didDomain;
  final String? anpServiceUrl;
  final String? anpServiceDid;

  factory ServiceConfig.fromMap(Map<String, Object?> map) {
    return ServiceConfig(
      baseUrl: _stringAt(map, 'baseUrl', 'https://awiki.info'),
      userServiceUrl: _stringAt(map, 'userServiceUrl', 'https://awiki.info'),
      messageServiceUrl: _stringAt(
        map,
        'messageServiceUrl',
        'https://awiki.info',
      ),
      didDomain: _stringAt(map, 'didDomain', 'awiki.info'),
      anpServiceUrl: _optionalStringAt(map, 'anpServiceUrl'),
      anpServiceDid: _optionalStringAt(map, 'anpServiceDid'),
    );
  }
}

class DeviceConfig {
  DeviceConfig({
    required this.resetBeforeRun,
    required this.ios,
    required this.android,
  });

  final bool resetBeforeRun;
  final IosConfig ios;
  final AndroidConfig android;

  factory DeviceConfig.fromMap(Map<String, Object?> map) {
    return DeviceConfig(
      resetBeforeRun: _boolAt(map, 'resetBeforeRun', true),
      ios: IosConfig.fromMap(_mapAt(map, 'ios', optional: true)),
      android: AndroidConfig.fromMap(_mapAt(map, 'android', optional: true)),
    );
  }
}

class IosConfig {
  IosConfig({
    required this.deviceType,
    required this.runtime,
    required this.names,
    required this.ids,
  });

  final String? deviceType;
  final String? runtime;
  final SlotStrings names;
  final SlotStrings ids;

  factory IosConfig.fromMap(Map<String, Object?> map) {
    return IosConfig(
      deviceType: _optionalStringAt(map, 'deviceType'),
      runtime: _optionalStringAt(map, 'runtime'),
      names: SlotStrings.fromMap(
        _mapAt(map, 'names', optional: true),
        defaultA: 'awiki-e2e-ios-a',
        defaultB: 'awiki-e2e-ios-b',
      ),
      ids: SlotStrings.fromMap(_mapAt(map, 'ids', optional: true)),
    );
  }
}

class AndroidConfig {
  AndroidConfig({required this.avdNames, required this.ids});

  final SlotStrings avdNames;
  final SlotStrings ids;

  factory AndroidConfig.fromMap(Map<String, Object?> map) {
    return AndroidConfig(
      avdNames: SlotStrings.fromMap(_mapAt(map, 'avdNames', optional: true)),
      ids: SlotStrings.fromMap(_mapAt(map, 'ids', optional: true)),
    );
  }
}

class SlotStrings {
  SlotStrings({this.a, this.b});

  final String? a;
  final String? b;

  factory SlotStrings.fromMap(
    Map<String, Object?> map, {
    String? defaultA,
    String? defaultB,
  }) {
    return SlotStrings(
      a: _optionalStringAt(map, 'a') ?? defaultA,
      b: _optionalStringAt(map, 'b') ?? defaultB,
    );
  }
}

class OtpConfig {
  OtpConfig({required this.digits, required this.timeout});

  final int digits;
  final Duration timeout;

  factory OtpConfig.fromMap(Map<String, Object?> map) {
    final digits = _intAt(map, 'digits', 6);
    if (digits != 6) {
      throw E2eFailure('This E2E flow currently supports 6-digit OTP only.');
    }
    final timeoutSeconds = _intAt(map, 'timeoutSeconds', 180);
    if (timeoutSeconds <= 0) {
      throw E2eFailure('otp.timeoutSeconds must be greater than 0.');
    }
    return OtpConfig(
      digits: digits,
      timeout: Duration(seconds: timeoutSeconds),
    );
  }
}

class AccountsConfig {
  AccountsConfig({required this.a, required this.b});

  final E2eAccount a;
  final E2eAccount b;

  factory AccountsConfig.fromMap(Map<String, Object?> map) {
    final a = E2eAccount.fromMap(_mapAt(map, 'a'));
    final b = E2eAccount.fromMap(_mapAt(map, 'b'));
    if (a.handle.toLowerCase() == b.handle.toLowerCase()) {
      throw E2eFailure('accounts.a.handle and accounts.b.handle must differ.');
    }
    return AccountsConfig(a: a, b: b);
  }
}

class E2eAccount {
  E2eAccount({required this.phone, required this.handle});

  final String phone;
  final String handle;

  factory E2eAccount.fromMap(Map<String, Object?> map) {
    return E2eAccount(
      phone: _requiredString(map, 'phone'),
      handle: _requiredString(map, 'handle'),
    );
  }
}

class MessageConfig {
  MessageConfig({required this.waitTimeout});

  final Duration waitTimeout;

  factory MessageConfig.fromMap(Map<String, Object?> map) {
    final timeoutSeconds = _intAt(map, 'waitTimeoutSeconds', 90);
    if (timeoutSeconds <= 0) {
      throw E2eFailure('message.waitTimeoutSeconds must be greater than 0.');
    }
    return MessageConfig(waitTimeout: Duration(seconds: timeoutSeconds));
  }
}

class DevicePair {
  DevicePair({required this.a, required this.b});

  final E2eDevice a;
  final E2eDevice b;
}

class E2eDevice {
  E2eDevice({required this.label, required this.id});

  final String label;
  final String id;
}

class RunnerOptions {
  RunnerOptions({
    required this.configPath,
    required this.skipBuild,
    required this.dryRun,
    required this.help,
  });

  final String configPath;
  final bool skipBuild;
  final bool dryRun;
  final bool help;

  static RunnerOptions parse(List<String> args) {
    var configPath = 'tests/e2e_test/configs/mobile.local.yaml';
    var skipBuild = false;
    var dryRun = false;
    var help = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--config':
          index += 1;
          if (index >= args.length) {
            throw E2eFailure('--config requires a path.');
          }
          configPath = args[index];
          break;
        case '--skip-build':
          skipBuild = true;
          break;
        case '--dry-run':
          dryRun = true;
          break;
        case '-h':
        case '--help':
          help = true;
          break;
        default:
          throw E2eFailure('Unknown argument: $arg');
      }
    }
    return RunnerOptions(
      configPath: configPath,
      skipBuild: skipBuild,
      dryRun: dryRun,
      help: help,
    );
  }

  static void printUsage() {
    stdout.writeln('''
Run the AWiki Me two-device E2E smoke test.

Usage:
  dart run tests/e2e_test/harness/mobile_e2e_runner.dart [--config tests/e2e_test/configs/mobile.local.yaml] [--skip-build] [--dry-run]

Options:
  --config      Local YAML config path. Defaults to tests/e2e_test/configs/mobile.local.yaml.
  --skip-build  Reuse an existing Flutter debug build.
  --dry-run     Print commands without running them.
''');
  }
}

class E2eFailure implements Exception {
  E2eFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, Object?> _toStringKeyMap(Object? value, {required String path}) {
  if (value == null) {
    return <String, Object?>{};
  }
  if (value is! YamlMap && value is! Map) {
    throw E2eFailure('$path must be a map.');
  }
  final map = value as Map;
  return <String, Object?>{
    for (final entry in map.entries)
      entry.key.toString(): _normalizeYamlValue(entry.value),
  };
}

Object? _normalizeYamlValue(Object? value) {
  if (value is YamlMap || value is Map) {
    return _toStringKeyMap(value, path: 'nested map');
  }
  if (value is YamlList || value is List) {
    return [for (final item in value as Iterable) _normalizeYamlValue(item)];
  }
  return value;
}

Map<String, Object?> _mapAt(
  Map<String, Object?> map,
  String key, {
  bool optional = false,
}) {
  final value = map[key];
  if (value == null && optional) {
    return <String, Object?>{};
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  throw E2eFailure('$key must be configured as a map.');
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = _optionalStringAt(map, key);
  if (value == null || value.isEmpty) {
    throw E2eFailure('$key is required.');
  }
  return value;
}

String _stringAt(Map<String, Object?> map, String key, String fallback) {
  return _optionalStringAt(map, key) ?? fallback;
}

String? _optionalStringAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intAt(Map<String, Object?> map, String key, int fallback) {
  final value = map[key];
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse(value.toString()) ??
      (throw E2eFailure('$key must be an integer.'));
}

bool _boolAt(Map<String, Object?> map, String key, bool fallback) {
  final value = map[key];
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  return switch (value.toString().trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => throw E2eFailure('$key must be true or false.'),
  };
}

Future<String?> _findExecutable(String executable) async {
  final fromPath = await _which(executable);
  if (fromPath != null) {
    return fromPath;
  }
  for (final envKey in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final root = Platform.environment[envKey];
    if (root == null || root.trim().isEmpty) {
      continue;
    }
    final candidate = File('$root/emulator/$executable');
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  return null;
}

Future<String?> _which(String executable) async {
  final command = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(command, [executable], runInShell: false);
  if (result.exitCode != 0) {
    return null;
  }
  final out = result.stdout.toString().trim();
  return out.isEmpty ? null : out.split('\n').first.trim();
}

void _pipe(
  Stream<List<int>> stream,
  String label,
  IOSink? sink, {
  bool isError = false,
}) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final prefix = '[$label] ';
    if (isError) {
      stderr.writeln('$prefix$line');
    } else {
      stdout.writeln('$prefix$line');
    }
    sink?.writeln(line);
  });
}

String _newRunId() {
  final now = DateTime.now().toUtc();
  final timestamp = now
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
  final suffix = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36)
      .substring(4);
  return '$timestamp-$suffix';
}

void _section(String title) {
  stdout.writeln('\n== $title ==');
}

void _line(String message) {
  stdout.writeln(message);
}

String _formatDuration(Duration duration) {
  if (duration.inHours > 0) {
    return '${duration.inHours}h '
        '${duration.inMinutes.remainder(60)}m '
        '${duration.inSeconds.remainder(60)}s';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
  if (duration.inSeconds > 0) {
    final tenths = duration.inMilliseconds.remainder(1000) ~/ 100;
    return '${duration.inSeconds}.${tenths}s';
  }
  return '${duration.inMilliseconds}ms';
}

void _command(
  String executable,
  List<String> args, {
  void Function(String line)? logLine,
}) {
  final line = '\$ $executable ${args.map(_quoteCommandArg).join(' ')}';
  (logLine ?? _line)(line);
}

String _messageIdentifier(String content) {
  final normalized = content
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'e2e-message-${normalized.isEmpty ? 'empty' : normalized}';
}

String _redactUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    return '<redacted-url>';
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.isEmpty ? '' : uri.path;
  return '${uri.scheme}://${uri.host}$port$path';
}

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '<redacted-empty>';
  }
  var hash = 0;
  for (final codeUnit in trimmed.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x3fffffff;
  }
  return '<redacted:${hash.toRadixString(36)}>';
}

String _quoteCommandArg(String arg) {
  if (arg.isEmpty) {
    return "''";
  }
  final redacted = _redactCommandArg(arg);
  if (!RegExp(r'''[\s'"$`\\]''').hasMatch(redacted)) {
    return redacted;
  }
  return "'${redacted.replaceAll("'", r"'\''")}'";
}

String _redactCommandArg(String arg) {
  if (arg.startsWith('--dart-define=')) {
    final define = arg.substring('--dart-define='.length);
    final separator = define.indexOf('=');
    if (separator <= 0) {
      return arg;
    }
    final key = define.substring(0, separator);
    final value = define.substring(separator + 1);
    return '--dart-define=$key=${_redactCommandValue(key, value)}';
  }
  final separator = arg.indexOf('=');
  if (separator > 0) {
    final key = arg.substring(0, separator);
    final value = arg.substring(separator + 1);
    if (_isSensitiveCommandKey(key)) {
      return '$key=<redacted>';
    }
    if (key.toUpperCase().endsWith('_URL')) {
      return '$key=${_redactUrl(value)}';
    }
  }
  return arg;
}

String _redactCommandValue(String key, String value) {
  if (_isSensitiveCommandKey(key)) {
    return '<redacted>';
  }
  final upper = key.toUpperCase();
  if (upper.endsWith('_URL') || upper.endsWith('_BASE_URL')) {
    return _redactUrl(value);
  }
  return value;
}

bool _isSensitiveCommandKey(String key) {
  final upper = key.toUpperCase();
  if (upper.contains('OTP_TIMEOUT')) {
    return false;
  }
  return upper.contains('PHONE') ||
      upper.contains('OTP_CODE') ||
      upper == 'OTP' ||
      upper.contains('TOKEN') ||
      upper.contains('JWT') ||
      upper.contains('PRIVATE') ||
      upper.contains('SECRET');
}
