part of '../desktop_cli_peer_e2e.dart';

class _DesktopCliPeerSmokeConfig {
  const _DesktopCliPeerSmokeConfig({
    required this.runId,
    required this.platform,
    required this.e2eCase,
    required this.environment,
    required this.appHandle,
    required this.cliHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.cliBin,
    required this.cliWorkspace,
    required this.cliHome,
    required this.appStateRoot,
    required this.performance,
  });

  factory _DesktopCliPeerSmokeConfig.load() {
    final config = tryLoad();
    if (config == null) {
      throw StateError(
        'Desktop CLI peer E2E config file was not found: '
        '$_desktopCliPeerRunConfigPath. Run '
        '`dart run tests/e2e/runner.dart --case full`.',
      );
    }
    return config;
  }

  static bool exists() => File(_desktopCliPeerRunConfigPath).existsSync();

  static _DesktopCliPeerSmokeConfig? tryLoad() {
    final file = File(_desktopCliPeerRunConfigPath);
    if (!file.existsSync()) {
      return null;
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw StateError('$_desktopCliPeerRunConfigPath must be a JSON object.');
    }
    final map = _stringKeyMap(raw, path: _desktopCliPeerRunConfigPath);
    final service = _mapAt(map, 'service');
    final otp = _mapAt(map, 'otp');
    final accounts = _mapAt(map, 'accounts');
    final appUser = _mapAt(accounts, 'appUser');
    final cliPeerAccount = _mapAt(accounts, 'cliPeer');
    final cliPeer = _mapAt(map, 'cliPeer');
    final app = _mapAt(map, 'app');
    final performance = _mapAt(map, 'performance', optional: true);
    final baseUrl = _requiredConfig(service, 'baseUrl', 'service.baseUrl');
    final didDomain = _requiredConfig(
      service,
      'didDomain',
      'service.didDomain',
    );
    return _DesktopCliPeerSmokeConfig(
      runId: _requiredConfig(map, 'runId', 'runId'),
      platform: _requiredConfig(map, 'platform', 'platform'),
      e2eCase: DesktopCliPeerIntegrationCase.parse(
        _optionalConfig(map, 'case') ?? 'full',
      ),
      environment: AwikiEnvironmentConfig(
        baseUrl: baseUrl,
        userServiceUrl: _optionalConfig(service, 'userServiceUrl') ?? baseUrl,
        messageServiceUrl:
            _optionalConfig(service, 'messageServiceUrl') ?? baseUrl,
        mailServiceUrl: _optionalConfig(service, 'mailServiceUrl') ?? baseUrl,
        didDomain: didDomain,
        anpServiceUrl:
            _optionalConfig(service, 'anpServiceUrl') ?? '$baseUrl/anp-im/rpc',
        anpServiceDid:
            _optionalConfig(service, 'anpServiceDid') ?? 'did:wba:$didDomain',
        agentImEnabled: true,
      ),
      appHandle: _requiredConfig(appUser, 'handle', 'accounts.appUser.handle'),
      cliHandle: _requiredConfig(
        cliPeerAccount,
        'handle',
        'accounts.cliPeer.handle',
      ),
      otpPhone: _requiredConfig(otp, 'phone', 'otp.phone'),
      otpCode: _requiredConfig(otp, 'code', 'otp.code'),
      cliBin: _requiredConfig(cliPeer, 'binary', 'cliPeer.binary'),
      cliWorkspace: _requiredConfig(cliPeer, 'workspace', 'cliPeer.workspace'),
      cliHome: _requiredConfig(cliPeer, 'home', 'cliPeer.home'),
      appStateRoot: _requiredConfig(app, 'stateRoot', 'app.stateRoot'),
      performance: _DesktopPerformanceRunConfig.fromJson(performance),
    );
  }

  final String runId;
  final String platform;
  final DesktopCliPeerIntegrationCase e2eCase;
  final AwikiEnvironmentConfig environment;
  final String appHandle;
  final String cliHandle;
  final String otpPhone;
  final String otpCode;
  final String cliBin;
  final String cliWorkspace;
  final String cliHome;
  final String appStateRoot;
  final _DesktopPerformanceRunConfig performance;

  List<String> get secrets => <String>[
    otpPhone,
    otpCode,
    cliWorkspace,
    cliHome,
    appStateRoot,
  ].where((value) => value.trim().isNotEmpty).toList(growable: false);
}

class _DesktopPerformanceRunConfig {
  const _DesktopPerformanceRunConfig({
    required this.enabled,
    required this.productTimingsPath,
    required this.datasetConversationCount,
    required this.longThreadMessageCount,
    required this.requiredMetrics,
    required this.hardBudgetMs,
    required this.softBudgetMs,
    required this.maxFullRefreshDuringSendReceive,
  });

  factory _DesktopPerformanceRunConfig.fromJson(Map<String, Object?> map) {
    return _DesktopPerformanceRunConfig(
      enabled: _optionalBool(map, 'enabled') ?? false,
      productTimingsPath: _optionalConfig(map, 'productTimingsPath'),
      datasetConversationCount:
          _optionalInt(map, 'datasetConversationCount') ?? 100,
      longThreadMessageCount:
          _optionalInt(map, 'longThreadMessageCount') ?? 100,
      requiredMetrics: _optionalStringList(map, 'requiredMetrics'),
      hardBudgetMs: _optionalIntMap(map, 'hardBudgetMs'),
      softBudgetMs: _optionalIntMap(map, 'softBudgetMs'),
      maxFullRefreshDuringSendReceive:
          _optionalInt(map, 'maxFullRefreshDuringSendReceive') ?? 0,
    );
  }

  final bool enabled;
  final String? productTimingsPath;
  final int datasetConversationCount;
  final int longThreadMessageCount;
  final List<String> requiredMetrics;
  final Map<String, int> hardBudgetMs;
  final Map<String, int> softBudgetMs;
  final int maxFullRefreshDuringSendReceive;
}

class _AppIdentityAttempt {
  const _AppIdentityAttempt._({this.session, required this.errorText});

  factory _AppIdentityAttempt.session(AppSession session) {
    return _AppIdentityAttempt._(session: session, errorText: '');
  }

  factory _AppIdentityAttempt.error(String errorText) {
    return _AppIdentityAttempt._(errorText: errorText);
  }

  final AppSession? session;
  final String errorText;
}

Map<String, Object?> _stringKeyMap(Object? value, {required String path}) {
  if (value is! Map) {
    throw StateError('$path must be a JSON object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _mapAt(
  Map<String, Object?> map,
  String key, {
  bool optional = false,
}) {
  final value = map[key];
  if (value == null && optional) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

String _requiredConfig(Map<String, Object?> map, String key, String name) {
  final value = _optionalConfig(map, key);
  if (value == null) {
    throw StateError('$name is required in $_desktopCliPeerRunConfigPath.');
  }
  return value;
}

String? _optionalConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

bool? _optionalBool(Map<String, Object?> map, String key) {
  final raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is bool) {
    return raw;
  }
  return switch (raw.toString().trim().toLowerCase()) {
    'true' || '1' || 'yes' || 'on' => true,
    'false' || '0' || 'no' || 'off' => false,
    _ => null,
  };
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.round();
  }
  return int.tryParse(raw.toString().trim());
}

List<String> _optionalStringList(Map<String, Object?> map, String key) {
  final raw = map[key];
  if (raw is! List) {
    return const <String>[];
  }
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, int> _optionalIntMap(Map<String, Object?> map, String key) {
  final raw = map[key];
  if (raw is! Map) {
    return const <String, int>{};
  }
  return <String, int>{
    for (final entry in raw.entries)
      entry.key.toString(): entry.value is num
          ? (entry.value as num).round()
          : int.tryParse(entry.value.toString().trim()) ?? 0,
  };
}

String _messageNonce() {
  final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
  return micros.toRadixString(36);
}

String _groupSlug(String runId, String nonce) {
  final raw = 'awiki-e2e-$runId-$nonce'.toLowerCase();
  final slug = raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (slug.length <= 48) {
    return slug;
  }
  return slug.substring(0, 48).replaceAll(RegExp(r'-$'), '');
}

String _normalizeIdentityRef(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.endsWith('.awiki.ai')) {
    return normalized.substring(0, normalized.length - '.awiki.ai'.length);
  }
  return normalized;
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String _sanitizeDiagnostic(
  String input, {
  Iterable<String> secrets = const [],
}) {
  var output = input;
  for (final secret in secrets) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      output = output.replaceAll(trimmed, '<redacted>');
    }
  }
  output = output.replaceAll(
    RegExp(
      r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    '<redacted-key>=<redacted>',
  );
  output = output.replaceAllMapped(
    RegExp(r'(--otp|--phone)\s+([^\s]+)', caseSensitive: false),
    (match) => '${match.group(1)} <redacted>',
  );
  return output;
}
