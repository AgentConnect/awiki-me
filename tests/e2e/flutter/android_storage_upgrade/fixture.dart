import 'dart:convert';

// Synthetic values only. These never represent a real account or vault.
const fixturePackage = 'ai.awiki.forensics.storage_lab';
const fixtureScope = '11111111-1111-4111-8111-111111111111';
const fixtureIdentity = 'fixture-local-identity';
const fixtureSelectionKey = 'awiki_me_active_identity.scope.$fixtureScope';
const fixtureSecretKey = 'scope/$fixtureScope';
final fixtureEnvelope = jsonEncode({
  'schema_version': 1,
  'scope_id': fixtureScope,
  'revision': 1,
  'active_secrets': {
    'identity_vault_root': {
      'key_id': '22222222-2222-4222-8222-222222222222',
      'key_version': 1,
      'algorithm': 'raw-256',
      'material_b64': base64Encode(List<int>.generate(32, (i) => i)),
    },
  },
});
