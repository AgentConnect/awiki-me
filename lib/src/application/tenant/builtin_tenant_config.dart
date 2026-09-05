import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const String builtinTenantsBase64EnvironmentKey =
    'AWIKI_BUILTIN_TENANTS_BASE64';
const String builtinTenantsSha256EnvironmentKey =
    'AWIKI_BUILTIN_TENANTS_SHA256';
const String _injectedBase64 = String.fromEnvironment(
  builtinTenantsBase64EnvironmentKey,
);
const String _injectedSha256 = String.fromEnvironment(
  builtinTenantsSha256EnvironmentKey,
);
const String builtinTenantsDefaultAsset =
    'assets/config/builtin-tenants.default.json';

enum BuiltinTenantSlot { primary, secondary }

class BuiltinTenantDefinition {
  const BuiltinTenantDefinition({
    required this.displayName,
    required this.backendOrigin,
    required this.didHost,
  });

  final String displayName;
  final String backendOrigin;
  final String didHost;
}

class BuiltinTenantCatalog {
  const BuiltinTenantCatalog({
    required this.defaultSlot,
    required this.primary,
    required this.secondary,
  });

  final BuiltinTenantSlot defaultSlot;
  final BuiltinTenantDefinition primary;
  final BuiltinTenantDefinition secondary;

  BuiltinTenantDefinition forSlot(BuiltinTenantSlot slot) =>
      slot == BuiltinTenantSlot.primary ? primary : secondary;
}

BuiltinTenantCatalog? _catalog;

BuiltinTenantCatalog get builtinTenantCatalog {
  final loaded = _catalog;
  if (loaded != null) return loaded;
  // Unit tests run from the package root before main() initializes assets.
  final source = File(builtinTenantsDefaultAsset);
  if (!source.existsSync()) {
    throw StateError('builtin_tenant_config_not_initialized');
  }
  return _catalog = decodeBuiltinTenantCatalog(
    source.readAsStringSync(),
    localeName: Platform.localeName,
  );
}

Future<void> initializeBuiltinTenantCatalog({AssetBundle? bundle}) async {
  final raw = _injectedBase64.isEmpty
      ? await (bundle ?? rootBundle).loadString(builtinTenantsDefaultAsset)
      : utf8.decode(base64Decode(_injectedBase64));
  if (_injectedBase64.isNotEmpty) {
    final actual = sha256.convert(utf8.encode(raw)).toString();
    if (_injectedSha256.length != 64 || actual != _injectedSha256) {
      throw const FormatException('builtin_tenant_config_digest_mismatch');
    }
  }
  _catalog = decodeBuiltinTenantCatalog(raw, localeName: Platform.localeName);
}

BuiltinTenantCatalog decodeBuiltinTenantCatalog(
  String raw, {
  String localeName = 'en',
}) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map || decoded['schema_version'] != 1) {
    throw const FormatException('builtin_tenant_config_invalid');
  }
  final defaultSlot = switch (decoded['default_slot']) {
    'primary' => BuiltinTenantSlot.primary,
    'secondary' => BuiltinTenantSlot.secondary,
    _ => throw const FormatException('builtin_tenant_default_invalid'),
  };
  final tenants = decoded['tenants'];
  if (tenants is! Map ||
      tenants.length != 2 ||
      !tenants.containsKey('primary') ||
      !tenants.containsKey('secondary')) {
    throw const FormatException('builtin_tenant_slots_invalid');
  }
  final primary = _decodeDefinition(tenants['primary'], localeName);
  final secondary = _decodeDefinition(tenants['secondary'], localeName);
  if (primary.backendOrigin == secondary.backendOrigin ||
      primary.didHost == secondary.didHost) {
    throw const FormatException('builtin_tenant_endpoints_duplicate');
  }
  return BuiltinTenantCatalog(
    defaultSlot: defaultSlot,
    primary: primary,
    secondary: secondary,
  );
}

BuiltinTenantDefinition _decodeDefinition(Object? value, String localeName) {
  if (value is! Map || value['display_name'] is! Map) {
    throw const FormatException('builtin_tenant_definition_invalid');
  }
  final names = value['display_name']! as Map;
  final zhName = names['zh-CN']?.toString().trim() ?? '';
  final enName = names['en']?.toString().trim() ?? '';
  final displayName = localeName.toLowerCase().startsWith('zh')
      ? zhName
      : enName;
  final backendRaw = value['backend_origin']?.toString().trim() ?? '';
  final didHost = value['did_host']?.toString().trim().toLowerCase() ?? '';
  final uri = Uri.tryParse(backendRaw);
  final loopback =
      uri != null &&
      uri.scheme == 'http' &&
      (uri.host == 'localhost' ||
          InternetAddress.tryParse(uri.host)?.isLoopback == true);
  if (displayName.isEmpty ||
      zhName.isEmpty ||
      enName.isEmpty ||
      uri == null ||
      uri.host != didHost ||
      (uri.scheme != 'https' && !loopback) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && !loopback) ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('builtin_tenant_definition_invalid');
  }
  return BuiltinTenantDefinition(
    displayName: displayName,
    backendOrigin: uri.origin,
    didHost: didHost,
  );
}
