import 'dart:io';

import 'package:yaml/yaml.dart';

final class AgentImDelegatedConfig {
  const AgentImDelegatedConfig({
    required this.service,
    required this.remote,
    required this.cliPeer,
    required this.app,
    required this.agent,
    required this.accounts,
    required this.timeouts,
  });

  factory AgentImDelegatedConfig.load(File file) {
    if (!file.existsSync()) {
      throw AgentImConfigFailure('Agent IM config was not found: ${file.path}');
    }
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) {
      throw const AgentImConfigFailure('Agent IM config must be a YAML map.');
    }
    final map = _asStringMap(yaml);
    final config = AgentImDelegatedConfig(
      service: AgentImServiceConfig.fromMap(_map(map, 'service')),
      remote: AgentImRemoteConfig.fromMap(_map(map, 'remote')),
      cliPeer: AgentImCliPeerConfig.fromMap(_map(map, 'cliPeer')),
      app: AgentImAppConfig.fromMap(_map(map, 'app')),
      agent: AgentImAgentConfig.fromMap(_map(map, 'agent')),
      accounts: AgentImAccountsConfig.fromMap(_map(map, 'accounts')),
      timeouts: AgentImTimeoutsConfig.fromMap(_map(map, 'timeouts')),
    );
    config.validate();
    return config;
  }

  final AgentImServiceConfig service;
  final AgentImRemoteConfig remote;
  final AgentImCliPeerConfig cliPeer;
  final AgentImAppConfig app;
  final AgentImAgentConfig agent;
  final AgentImAccountsConfig accounts;
  final AgentImTimeoutsConfig timeouts;

  void validate() {
    if (accounts.appUser.handle.toLowerCase() ==
        accounts.peerUser.handle.toLowerCase()) {
      throw const AgentImConfigFailure(
        'appUser.handle and peerUser.handle must differ.',
      );
    }
    _validateEnvName(accounts.appUser.phoneEnv, 'accounts.appUser.phoneEnv');
    _validateEnvName(accounts.appUser.otpEnv, 'accounts.appUser.otpEnv');
    _validateEnvName(accounts.peerUser.phoneEnv, 'accounts.peerUser.phoneEnv');
    _validateEnvName(accounts.peerUser.otpEnv, 'accounts.peerUser.otpEnv');
  }

  Map<String, Object?> toReportJson() => <String, Object?>{
    'service': service.toReportJson(),
    'remote': remote.toReportJson(),
    'cliPeer': cliPeer.toReportJson(),
    'app': app.toReportJson(),
    'agent': agent.toReportJson(),
    'accounts': accounts.toReportJson(),
    'timeouts': timeouts.toReportJson(),
  };
}

final class AgentImServiceConfig {
  const AgentImServiceConfig({
    required this.baseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.messageServiceWsUrl,
    required this.didDomain,
  });

  factory AgentImServiceConfig.fromMap(Map<String, Object?> map) {
    final baseUrl = _normalizedUrl(
      _string(map, 'baseUrl', 'https://awiki.info'),
    );
    return AgentImServiceConfig(
      baseUrl: baseUrl,
      userServiceUrl: _normalizedUrl(_string(map, 'userServiceUrl', baseUrl)),
      messageServiceUrl: _normalizedUrl(
        _string(map, 'messageServiceUrl', baseUrl),
      ),
      messageServiceWsUrl: _string(
        map,
        'messageServiceWsUrl',
        'wss://${Uri.parse(baseUrl).host}/im/ws',
      ),
      didDomain: _string(map, 'didDomain', Uri.parse(baseUrl).host),
    );
  }

  final String baseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String messageServiceWsUrl;
  final String didDomain;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'baseUrl': baseUrl,
    'userServiceUrl': userServiceUrl,
    'messageServiceUrl': messageServiceUrl,
    'messageServiceWsUrl': messageServiceWsUrl,
    'didDomain': didDomain,
  };
}

final class AgentImRemoteConfig {
  const AgentImRemoteConfig({
    required this.sshAlias,
    required this.collectLogs,
    required this.redactSecrets,
  });

  factory AgentImRemoteConfig.fromMap(Map<String, Object?> map) {
    return AgentImRemoteConfig(
      sshAlias: _string(map, 'sshAlias', 'ali'),
      collectLogs: _bool(map, 'collectLogs', defaultValue: true),
      redactSecrets: _bool(map, 'redactSecrets', defaultValue: true),
    );
  }

  final String sshAlias;
  final bool collectLogs;
  final bool redactSecrets;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'sshAlias': sshAlias,
    'collectLogs': collectLogs,
    'redactSecrets': redactSecrets,
  };
}

final class AgentImCliPeerConfig {
  const AgentImCliPeerConfig({
    required this.repo,
    required this.binary,
    required this.workspaceRoot,
  });

  factory AgentImCliPeerConfig.fromMap(Map<String, Object?> map) {
    return AgentImCliPeerConfig(
      repo: _string(map, 'repo', '../awiki-cli-rs2'),
      binary: _string(map, 'binary', 'target/debug/awiki-cli'),
      workspaceRoot: _string(map, 'workspaceRoot', '.e2e/agent-im/cli-peer'),
    );
  }

  final String repo;
  final String binary;
  final String workspaceRoot;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'repo': repo,
    'binary': binary,
    'workspaceRoot': workspaceRoot,
  };
}

final class AgentImAppConfig {
  const AgentImAppConfig({
    required this.platform,
    required this.runMode,
    required this.workspaceRoot,
    required this.appInstanceId,
  });

  factory AgentImAppConfig.fromMap(Map<String, Object?> map) {
    final platform = _string(map, 'platform', 'macos').toLowerCase();
    if (platform != 'macos' && platform != 'linux') {
      throw const AgentImConfigFailure(
        'app.platform must be macos or linux for desktop E2E.',
      );
    }
    return AgentImAppConfig(
      platform: platform,
      runMode: _string(map, 'runMode', 'integration_test'),
      workspaceRoot: _string(map, 'workspaceRoot', '.e2e/agent-im/app'),
      appInstanceId: _string(map, 'appInstanceId', 'macos-e2e-app'),
    );
  }

  final String platform;
  final String runMode;
  final String workspaceRoot;
  final String appInstanceId;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'platform': platform,
    'runMode': runMode,
    'workspaceRoot': workspaceRoot,
    'appInstanceId': appInstanceId,
  };
}

final class AgentImAgentConfig {
  const AgentImAgentConfig({
    required this.expectedRuntime,
    required this.delegatedKeyFragment,
    this.daemonDid,
  });

  factory AgentImAgentConfig.fromMap(Map<String, Object?> map) {
    return AgentImAgentConfig(
      expectedRuntime: _string(map, 'expectedRuntime', 'hermes'),
      delegatedKeyFragment: _string(
        map,
        'delegatedKeyFragment',
        'daemon-key-1',
      ),
      daemonDid: _optionalString(map, 'daemonDid'),
    );
  }

  final String expectedRuntime;
  final String delegatedKeyFragment;
  final String? daemonDid;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'expectedRuntime': expectedRuntime,
    'delegatedKeyFragment': delegatedKeyFragment,
    if (daemonDid != null) 'daemonDid': daemonDid,
  };
}

final class AgentImAccountsConfig {
  const AgentImAccountsConfig({required this.appUser, required this.peerUser});

  factory AgentImAccountsConfig.fromMap(Map<String, Object?> map) {
    return AgentImAccountsConfig(
      appUser: AgentImAccountConfig.fromMap(_map(map, 'appUser')),
      peerUser: AgentImAccountConfig.fromMap(_map(map, 'peerUser')),
    );
  }

  final AgentImAccountConfig appUser;
  final AgentImAccountConfig peerUser;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'appUser': appUser.toReportJson(),
    'peerUser': peerUser.toReportJson(),
  };
}

final class AgentImAccountConfig {
  const AgentImAccountConfig({
    required this.phoneEnv,
    required this.otpEnv,
    required this.handle,
  });

  factory AgentImAccountConfig.fromMap(Map<String, Object?> map) {
    return AgentImAccountConfig(
      phoneEnv: _requiredString(map, 'phoneEnv'),
      otpEnv: _requiredString(map, 'otpEnv'),
      handle: _requiredString(map, 'handle'),
    );
  }

  final String phoneEnv;
  final String otpEnv;
  final String handle;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'phoneEnv': phoneEnv,
    'otpEnv': otpEnv,
    'handle': handle,
  };
}

final class AgentImTimeoutsConfig {
  const AgentImTimeoutsConfig({
    required this.bootstrap,
    required this.daemonConnect,
    required this.messageProcess,
  });

  factory AgentImTimeoutsConfig.fromMap(Map<String, Object?> map) {
    return AgentImTimeoutsConfig(
      bootstrap: _durationSeconds(map, 'bootstrapSeconds', 60),
      daemonConnect: _durationSeconds(map, 'daemonConnectSeconds', 90),
      messageProcess: _durationSeconds(map, 'messageProcessSeconds', 120),
    );
  }

  final Duration bootstrap;
  final Duration daemonConnect;
  final Duration messageProcess;

  Map<String, Object?> toReportJson() => <String, Object?>{
    'bootstrapSeconds': bootstrap.inSeconds,
    'daemonConnectSeconds': daemonConnect.inSeconds,
    'messageProcessSeconds': messageProcess.inSeconds,
  };
}

Map<String, Object?> _asStringMap(YamlMap yaml) {
  return yaml.map(
    (key, value) => MapEntry(key.toString(), _normalizeYaml(value)),
  );
}

Object? _normalizeYaml(Object? value) {
  if (value is YamlMap) {
    return _asStringMap(value);
  }
  if (value is YamlList) {
    return value.map(_normalizeYaml).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _map(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  throw AgentImConfigFailure('$key must be a YAML map.');
}

String _string(Map<String, Object?> map, String key, String fallback) {
  final value = map[key];
  if (value == null) {
    return fallback;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw AgentImConfigFailure('$key must be a non-empty string.');
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw AgentImConfigFailure('$key must be a non-empty string.');
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  throw AgentImConfigFailure('$key must be a string when set.');
}

bool _bool(Map<String, Object?> map, String key, {required bool defaultValue}) {
  final value = map[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  throw AgentImConfigFailure('$key must be a boolean.');
}

Duration _durationSeconds(
  Map<String, Object?> map,
  String key,
  int defaultSeconds,
) {
  final value = map[key] ?? defaultSeconds;
  if (value is int && value > 0) {
    return Duration(seconds: value);
  }
  throw AgentImConfigFailure('$key must be greater than 0.');
}

String _normalizedUrl(String value) =>
    value.trim().replaceAll(RegExp(r'/+$'), '');

void _validateEnvName(String value, String field) {
  if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(value)) {
    throw AgentImConfigFailure('$field must be an environment variable name.');
  }
}

final class AgentImConfigFailure implements Exception {
  const AgentImConfigFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
