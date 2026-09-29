import 'dart:io';

import 'package:awiki_me/src/app/tenant_aware_awiki_me_app.dart';
import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manual physical-device diagnostics with production adapters and an isolated
/// state root. No fake identity, notification, sync, or secret-store providers.
Future<void> main() async {
  if (!kDebugMode || !Platform.isAndroid) {
    throw StateError('notify_diagnostic_requires_android_debug');
  }
  if (const bool.fromEnvironment('AWIKI_E2E')) {
    throw StateError('notify_diagnostic_requires_platform_secret_store');
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBuiltinTenantCatalog();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final support = await getApplicationSupportDirectory();
  runApp(
    TenantAwareAwikiMeApp(
      appStateRoot: p.join(support.path, 'notify-diagnostic'),
    ),
  );
}
