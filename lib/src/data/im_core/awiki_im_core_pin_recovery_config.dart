import 'dart:convert';
import 'package:awiki_im_core/awiki_im_core.dart' as core;

/// Installed public trust anchors, injected by a reviewed Host build. No trust on
/// first use: downloading a config cannot install its own signing key.
const pinRecoveryTenantsEnvironmentKey = 'AWIKI_PIN_RECOVERY_TENANTS_BASE64';
const _installed = String.fromEnvironment(pinRecoveryTenantsEnvironmentKey);
List<core.PinRecoveryTenantConfig> installedPinRecoveryTenants() =>
    decodePinRecoveryTenants(_installed);

List<core.PinRecoveryTenantConfig> decodePinRecoveryTenants(String encoded) {
  if (encoded.isEmpty) return const [];
  final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
  if (decoded is! List) {
    throw const FormatException('pin_recovery_trust_invalid');
  }
  final seen = <String>{};
  return List.unmodifiable(
    decoded.map((value) {
      if (value is! Map<String, dynamic> ||
          value['tenant_id'] is! String ||
          value['deployment_id'] is! String ||
          value['control_base_url'] is! String ||
          value['config_signing_keys'] is! Map) {
        throw const FormatException('pin_recovery_trust_invalid');
      }
      final tenant = value['tenant_id'] as String;
      final url = Uri.tryParse(value['control_base_url'] as String);
      if (tenant.isEmpty ||
          !seen.add(tenant) ||
          url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment) {
        throw const FormatException('pin_recovery_trust_invalid');
      }
      return core.PinRecoveryTenantConfig(
        tenantId: tenant,
        deploymentId: value['deployment_id'] as String,
        controlBaseUrl: value['control_base_url'] as String,
        configSigningKeys: Map<String, String>.from(
          value['config_signing_keys'] as Map,
        ),
      );
    }),
  );
}
