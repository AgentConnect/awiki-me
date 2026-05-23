import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/im_core_runtime_port.dart';
import 'awiki_im_core_config.dart';
import 'awiki_im_core_paths.dart';

typedef AwikiImCoreOpen =
    Future<core.AwikiImCore> Function({
      required core.AwikiImCoreConfig config,
      required core.AwikiImCorePaths paths,
    });

class AwikiImCoreRuntime implements ImCoreRuntimePort {
  AwikiImCoreRuntime({
    required AwikiImCoreEnvironmentConfig config,
    required AwikiImCorePathLayout paths,
    AwikiImCoreOpen? openCore,
  }) : _config = config,
       _paths = paths,
       _openCore = openCore ?? core.AwikiImCore.open;

  static Future<AwikiImCoreRuntime> fromEnvironment() async {
    return AwikiImCoreRuntime(
      config: AwikiImCoreEnvironmentConfig.fromEnvironment(),
      paths: await AwikiImCorePathLayout.fromPlatform(),
    );
  }

  final AwikiImCoreEnvironmentConfig _config;
  final AwikiImCorePathLayout _paths;
  final AwikiImCoreOpen _openCore;

  core.AwikiImCore? _core;
  core.AwikiImClient? _currentClient;

  AwikiImCoreEnvironmentConfig get config => _config;

  AwikiImCorePathLayout get paths => _paths;

  @override
  bool get isOpen => _core != null;

  @override
  Future<void> open() async {
    if (_core != null) {
      return;
    }
    await _paths.ensureDirectories();
    _core = await _openCore(
      config: _config.toCoreConfig(),
      paths: _paths.toCorePaths(),
    );
  }

  Future<void> openAndValidate() async {
    await open();
    await validate();
  }

  @override
  Future<List<String>> validate() async {
    return (await coreInstance()).validatePaths();
  }

  Future<core.AwikiImCore> coreInstance() async {
    final existing = _core;
    if (existing != null) {
      return existing;
    }
    await open();
    return _core!;
  }

  Future<core.AwikiImClient> clientFor(core.IdentitySelector selector) async {
    return (await coreInstance()).client(selector);
  }

  Future<core.AwikiImClient> currentClient() async {
    final client = _currentClient;
    if (client == null) {
      throw StateError('IM Core identity is not selected.');
    }
    return client;
  }

  @override
  Future<void> switchIdentity(String identityIdOrAlias) {
    return selectIdentity(_selectorFromString(identityIdOrAlias));
  }

  Future<void> selectIdentity(core.IdentitySelector selector) async {
    final nextClient = await clientFor(selector);
    final previousClient = _currentClient;
    _currentClient = nextClient;
    await previousClient?.dispose();
  }

  @override
  Future<void> dispose() async {
    final client = _currentClient;
    _currentClient = null;
    await client?.dispose();

    final core = _core;
    _core = null;
    await core?.dispose();
  }
}

core.IdentitySelector _selectorFromString(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'identityIdOrAlias', 'must not be empty');
  }
  if (trimmed == 'default') {
    return const core.IdentitySelector.defaultIdentity();
  }
  if (trimmed.startsWith('did:')) {
    return core.IdentitySelector.did(trimmed);
  }
  if (trimmed.contains('.')) {
    return core.IdentitySelector.handle(trimmed);
  }
  return core.IdentitySelector.id(trimmed);
}
