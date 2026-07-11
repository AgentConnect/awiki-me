import 'dart:convert';
import 'dart:io';

import '../../application/tenant/app_tenant.dart';

enum StorageScopeLifecycle {
  provisioning,
  ready,
  deleting,
  blocked;

  static StorageScopeLifecycle parse(Object? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => throw const FormatException('scope_lifecycle_invalid'),
  );
}

class StorageScopeManifest {
  const StorageScopeManifest({
    required this.storageScopeId,
    required this.ownerTenantProfileId,
    required this.lifecycle,
    required this.didHostAtCreation,
    required this.createdAt,
    required this.updatedAt,
    this.remoteRealmId,
  });

  factory StorageScopeManifest.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != 1 || json['layout_version'] != 1) {
      throw const FormatException('scope_schema_unsupported');
    }
    if (json['vault_context_version'] != 1 ||
        json['secret_envelope_schema'] != 1) {
      throw const FormatException('scope_contract_unsupported');
    }
    final realm = json['realm_binding'];
    if (realm is! Map) throw const FormatException('scope_manifest_invalid');
    return StorageScopeManifest(
      storageScopeId: StorageScopeId.parse(_required(json, 'storage_scope_id')),
      ownerTenantProfileId: TenantProfileId.parse(
        _required(json, 'owner_tenant_profile_id'),
      ),
      lifecycle: StorageScopeLifecycle.parse(json['lifecycle']),
      remoteRealmId: _optional(realm['remote_realm_id']),
      didHostAtCreation: _required(
        realm.map((key, value) => MapEntry(key.toString(), value)),
        'did_host_at_creation',
      ),
      createdAt: _timestamp(json, 'created_at'),
      updatedAt: _timestamp(json, 'updated_at'),
    );
  }

  final StorageScopeId storageScopeId;
  final TenantProfileId ownerTenantProfileId;
  final StorageScopeLifecycle lifecycle;
  final String? remoteRealmId;
  final String didHostAtCreation;
  final String createdAt;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 1,
    'layout_version': 1,
    'storage_scope_id': storageScopeId.value,
    'owner_tenant_profile_id': ownerTenantProfileId.value,
    'lifecycle': lifecycle.name,
    'realm_binding': <String, Object?>{
      'remote_realm_id': remoteRealmId,
      'did_host_at_creation': didHostAtCreation,
    },
    'vault_context_version': 1,
    'secret_envelope_schema': 1,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  StorageScopeManifest copyWith({
    StorageScopeLifecycle? lifecycle,
    String? updatedAt,
  }) => StorageScopeManifest(
    storageScopeId: storageScopeId,
    ownerTenantProfileId: ownerTenantProfileId,
    lifecycle: lifecycle ?? this.lifecycle,
    remoteRealmId: remoteRealmId,
    didHostAtCreation: didHostAtCreation,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class StorageScopeManifestStore {
  const StorageScopeManifestStore();

  Future<StorageScopeManifest> readExisting(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('scope_manifest_missing');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('scope_manifest_invalid');
    return StorageScopeManifest.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> writeAtomic(String path, StorageScopeManifest manifest) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File(
      '$path.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
      flush: true,
    );
    await temp.rename(path);
  }
}

String _required(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('${key}_invalid');
  }
  return value;
}

String _timestamp(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (DateTime.tryParse(value) == null) {
    throw FormatException('${key}_invalid');
  }
  return value;
}

String? _optional(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('realm_id_invalid');
  }
  return value;
}
