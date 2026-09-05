import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _override = '''
{
  "schema_version": 1,
  "default_slot": "secondary",
  "tenants": {
    "primary": {
      "display_name": {"zh-CN": "甲租户", "en": "Alpha tenant"},
      "backend_origin": "https://alpha.example",
      "did_host": "alpha.example"
    },
    "secondary": {
      "display_name": {"zh-CN": "乙租户", "en": "Beta tenant"},
      "backend_origin": "https://beta.example",
      "did_host": "beta.example"
    }
  }
}
''';

void main() {
  test('a complete package override has no hidden official fallback', () {
    final catalog = decodeBuiltinTenantCatalog(_override, localeName: 'en_US');

    expect(catalog.defaultSlot, BuiltinTenantSlot.secondary);
    expect(catalog.primary.displayName, 'Alpha tenant');
    expect(catalog.primary.backendOrigin, 'https://alpha.example');
    expect(catalog.secondary.backendOrigin, 'https://beta.example');
  });

  test('localized display names come from the same package config', () {
    final catalog = decodeBuiltinTenantCatalog(_override, localeName: 'zh_CN');

    expect(catalog.primary.displayName, '甲租户');
    expect(catalog.secondary.displayName, '乙租户');
  });

  test('partial and duplicate tenant configs fail closed', () {
    expect(
      () => decodeBuiltinTenantCatalog(
        '{"schema_version":1,"default_slot":"primary","tenants":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeBuiltinTenantCatalog(
        _override.replaceFirst('https://beta.example', 'https://alpha.example'),
      ),
      throwsFormatException,
    );
  });
}
