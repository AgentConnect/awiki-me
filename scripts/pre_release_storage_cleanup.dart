import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const String archiveConfirmation = 'ARCHIVE_PRE_RELEASE_STORAGE';
const String deleteConfirmation = 'DELETE_PRE_RELEASE_STORAGE';
const List<String> legacyKeychainServices = <String>[
  'ai.awiki.awikime.secure_storage',
  'flutter_secure_storage_service',
];
const List<String> _defaultLegacyNamespaces = <String>[
  'awiki.ai',
  'tenant-default',
];

enum PreReleaseCleanupMode { dryRun, archive, delete }

class LegacyKeychainLocator {
  const LegacyKeychainLocator({required this.service, required this.account});
  final String service;
  final String account;
  Map<String, String> toJson() => <String, String>{
    'service': service,
    'account': account,
  };
}

abstract interface class LegacyKeychainAccess {
  Future<bool> exists(LegacyKeychainLocator locator);
  Future<void> delete(LegacyKeychainLocator locator);
}

class MacOsSecurityLegacyKeychainAccess implements LegacyKeychainAccess {
  const MacOsSecurityLegacyKeychainAccess();

  @override
  Future<bool> exists(LegacyKeychainLocator locator) async {
    if (!Platform.isMacOS) return false;
    final result = await Process.run('security', <String>[
      'find-generic-password',
      '-s',
      locator.service,
      '-a',
      locator.account,
    ]);
    if (result.exitCode == 0) return true;
    if (result.exitCode == 44) return false;
    throw StateError('legacy_keychain_inventory_failed');
  }

  @override
  Future<void> delete(LegacyKeychainLocator locator) async {
    if (!Platform.isMacOS) return;
    final result = await Process.run('security', <String>[
      'delete-generic-password',
      '-s',
      locator.service,
      '-a',
      locator.account,
    ]);
    if (result.exitCode != 0 && result.exitCode != 44) {
      throw StateError('legacy_keychain_delete_failed');
    }
  }
}

class PreReleaseCleanupPlan {
  const PreReleaseCleanupPlan({
    required this.supportRoot,
    required this.legacyEnvironmentsRoot,
    required this.legacyEnvironmentsType,
    required this.namespaces,
    required this.existingKeychainItems,
  });
  final String supportRoot;
  final String legacyEnvironmentsRoot;
  final FileSystemEntityType legacyEnvironmentsType;
  final List<String> namespaces;
  final List<LegacyKeychainLocator> existingKeychainItems;

  Map<String, Object?> toJson() => <String, Object?>{
    'support_root': supportRoot,
    'legacy_environments_root': legacyEnvironmentsRoot,
    'legacy_environments_type': _entityTypeName(legacyEnvironmentsType),
    'namespaces': namespaces,
    'existing_keychain_items': existingKeychainItems
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

class PreReleaseStorageCleanup {
  PreReleaseStorageCleanup({
    required String supportRoot,
    LegacyKeychainAccess? keychain,
    DateTime Function()? clock,
  }) : supportRoot = p.normalize(p.absolute(supportRoot)),
       keychain = keychain ?? const MacOsSecurityLegacyKeychainAccess(),
       clock = clock ?? DateTime.now {
    _validateSupportRoot(this.supportRoot);
  }

  final String supportRoot;
  final LegacyKeychainAccess keychain;
  final DateTime Function() clock;
  String get legacyEnvironmentsRoot =>
      p.join(supportRoot, 'awiki-me', 'environments');
  String get archiveRoot =>
      p.join(supportRoot, 'awiki-me', 'pre-release-archive');

  Future<PreReleaseCleanupPlan> inspect({
    Iterable<String> additionalNamespaces = const <String>[],
  }) async {
    await _assertNoSymlinkBelowSupport(legacyEnvironmentsRoot);
    final type = await FileSystemEntity.type(
      legacyEnvironmentsRoot,
      followLinks: false,
    );
    final namespaces = <String>{..._defaultLegacyNamespaces};
    for (final value in additionalNamespaces) {
      namespaces.add(_validatedNamespace(value));
    }
    if (type == FileSystemEntityType.directory) {
      await for (final entity in Directory(
        legacyEnvironmentsRoot,
      ).list(followLinks: false)) {
        final namespace = p.basename(entity.path);
        if (_isSafeNamespace(namespace)) namespaces.add(namespace);
      }
    }
    final sortedNamespaces = namespaces.toList()..sort();
    final existingItems = <LegacyKeychainLocator>[];
    for (final locator in legacyLocatorsForNamespaces(sortedNamespaces)) {
      if (await keychain.exists(locator)) existingItems.add(locator);
    }
    return PreReleaseCleanupPlan(
      supportRoot: supportRoot,
      legacyEnvironmentsRoot: legacyEnvironmentsRoot,
      legacyEnvironmentsType: type,
      namespaces: List<String>.unmodifiable(sortedNamespaces),
      existingKeychainItems: List<LegacyKeychainLocator>.unmodifiable(
        existingItems,
      ),
    );
  }

  Future<String?> execute(
    PreReleaseCleanupPlan plan, {
    required PreReleaseCleanupMode mode,
    String? confirmation,
  }) async {
    if (plan.supportRoot != supportRoot ||
        plan.legacyEnvironmentsRoot != legacyEnvironmentsRoot) {
      throw StateError('cleanup_plan_root_mismatch');
    }
    if (mode == PreReleaseCleanupMode.dryRun) return null;
    final expected = mode == PreReleaseCleanupMode.archive
        ? archiveConfirmation
        : deleteConfirmation;
    if (confirmation != expected) {
      throw StateError('cleanup_confirmation_required');
    }
    if (plan.legacyEnvironmentsType == FileSystemEntityType.link) {
      throw StateError('legacy_environments_symlink_forbidden');
    }
    if (plan.legacyEnvironmentsType != FileSystemEntityType.notFound &&
        plan.legacyEnvironmentsType != FileSystemEntityType.directory) {
      throw StateError('legacy_environments_type_invalid');
    }

    String? archivedPath;
    if (plan.legacyEnvironmentsType == FileSystemEntityType.directory) {
      if (mode == PreReleaseCleanupMode.archive) {
        await _assertNoSymlinkBelowSupport(archiveRoot);
        await Directory(archiveRoot).create(recursive: true);
        await _assertNoSymlinkBelowSupport(archiveRoot);
        await _chmodDirectoryPrivate(archiveRoot);
        archivedPath = await _availableArchivePath();
        await Directory(legacyEnvironmentsRoot).rename(archivedPath);
      } else {
        await Directory(legacyEnvironmentsRoot).delete(recursive: true);
      }
    }
    if (mode == PreReleaseCleanupMode.delete) {
      for (final locator in plan.existingKeychainItems) {
        _validateLegacyLocator(locator);
        await keychain.delete(locator);
      }
    }
    if (mode == PreReleaseCleanupMode.archive) {
      final manifest = File(
        p.join(archiveRoot, 'cleanup-${_timestamp(clock())}.json'),
      );
      await manifest.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schema_version': 1, 'mode': 'archive', 'archived_path': archivedPath, 'preserved_keychain_items': plan.existingKeychainItems.map((item) => item.toJson()).toList(growable: false)})}\n',
        flush: true,
      );
      await _chmodPrivate(manifest.path);
    }
    return archivedPath;
  }

  Future<String> _availableArchivePath() async {
    final base = p.join(archiveRoot, 'environments-${_timestamp(clock())}');
    for (var index = 0; index < 1000; index += 1) {
      final candidate = index == 0 ? base : '$base-$index';
      if (await FileSystemEntity.type(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return candidate;
      }
    }
    throw StateError('cleanup_archive_path_exhausted');
  }

  Future<void> _assertNoSymlinkBelowSupport(String target) async {
    var current = p.normalize(p.absolute(target));
    if (current != supportRoot && !p.isWithin(supportRoot, current)) {
      throw StateError('cleanup_path_escape');
    }
    while (current != supportRoot) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('cleanup_symlink_forbidden');
      }
      final parent = p.dirname(current);
      if (parent == current) throw StateError('cleanup_path_escape');
      current = parent;
    }
  }
}

List<LegacyKeychainLocator> legacyLocatorsForNamespaces(
  Iterable<String> namespaces,
) {
  final locators = <LegacyKeychainLocator>[];
  for (final rawNamespace in namespaces) {
    final namespace = _validatedNamespace(rawNamespace);
    for (final service in legacyKeychainServices) {
      for (final suffix in const <String>[
        'root_key_b64',
        'device_id',
        'secrets_v1',
      ]) {
        locators.add(
          LegacyKeychainLocator(
            service: service,
            account: 'awiki_me.im_core.identity_vault.$namespace.$suffix',
          ),
        );
      }
    }
  }
  return List<LegacyKeychainLocator>.unmodifiable(locators);
}

void _validateLegacyLocator(LegacyKeychainLocator locator) {
  if (!legacyKeychainServices.contains(locator.service) ||
      !locator.account.startsWith('awiki_me.im_core.identity_vault.') ||
      locator.account.startsWith('scope/')) {
    throw StateError('cleanup_locator_forbidden');
  }
}

void _validateSupportRoot(String value) {
  final home = Platform.environment['HOME'];
  if (value.isEmpty ||
      value == p.rootPrefix(value) ||
      (home != null && p.equals(value, p.normalize(p.absolute(home))))) {
    throw ArgumentError.value(value, 'supportRoot', 'unsafe cleanup root');
  }
}

String _validatedNamespace(String value) {
  final normalized = value.trim().toLowerCase();
  if (!_isSafeNamespace(normalized)) {
    throw ArgumentError.value(value, 'namespace', 'invalid legacy namespace');
  }
  return normalized;
}

bool _isSafeNamespace(String value) =>
    RegExp(r'^[a-z0-9][a-z0-9._-]{0,127}$').hasMatch(value) &&
    value != '.' &&
    value != '..';

String _timestamp(DateTime value) => value
    .toUtc()
    .toIso8601String()
    .replaceAll(RegExp(r'[^0-9]'), '')
    .substring(0, 14);

Future<void> _chmodPrivate(String path) async {
  if (!(Platform.isMacOS || Platform.isLinux)) return;
  final result = await Process.run('chmod', <String>['600', path]);
  if (result.exitCode != 0) throw StateError('cleanup_manifest_chmod_failed');
}

Future<void> _chmodDirectoryPrivate(String path) async {
  if (!(Platform.isMacOS || Platform.isLinux)) return;
  final result = await Process.run('chmod', <String>['700', path]);
  if (result.exitCode != 0) throw StateError('cleanup_directory_chmod_failed');
}

String _entityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.notFound) return 'not_found';
  if (type == FileSystemEntityType.directory) return 'directory';
  if (type == FileSystemEntityType.file) return 'file';
  if (type == FileSystemEntityType.link) return 'link';
  return 'other';
}

Future<void> main(List<String> args) async {
  try {
    final options = _CleanupOptions.parse(args);
    if (options.help) {
      _CleanupOptions.printUsage();
      return;
    }
    final cleanup = PreReleaseStorageCleanup(supportRoot: options.supportRoot!);
    final plan = await cleanup.inspect(
      additionalNamespaces: options.namespaces,
    );
    stdout.writeln(
      const JsonEncoder.withIndent(
        ' ',
      ).convert(<String, Object?>{'mode': options.mode.name, ...plan.toJson()}),
    );
    final archivedPath = await cleanup.execute(
      plan,
      mode: options.mode,
      confirmation: options.confirmation,
    );
    if (options.mode == PreReleaseCleanupMode.dryRun) {
      stdout.writeln('dry_run_complete: no files or Keychain items changed');
    } else if (options.mode == PreReleaseCleanupMode.archive) {
      stdout.writeln(
        'archive_complete: ${archivedPath ?? 'no_legacy_directory'}',
      );
      stdout.writeln('keychain_items_preserved: true');
    } else {
      stdout.writeln('delete_complete');
    }
  } on Object catch (error) {
    stderr.writeln('pre_release_storage_cleanup_failed: $error');
    exitCode = 2;
  }
}

class _CleanupOptions {
  const _CleanupOptions({
    required this.supportRoot,
    required this.mode,
    required this.confirmation,
    required this.namespaces,
    required this.help,
  });
  final String? supportRoot;
  final PreReleaseCleanupMode mode;
  final String? confirmation;
  final List<String> namespaces;
  final bool help;

  static _CleanupOptions parse(List<String> args) {
    String? supportRoot;
    var mode = PreReleaseCleanupMode.dryRun;
    String? confirmation;
    final namespaces = <String>[];
    var help = false;
    var modeSelected = false;
    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--support-root':
          supportRoot = _take(args, ++index, '--support-root');
          break;
        case '--namespace':
          namespaces.add(_take(args, ++index, '--namespace'));
          break;
        case '--archive':
          if (modeSelected) throw ArgumentError('cleanup mode repeated');
          mode = PreReleaseCleanupMode.archive;
          modeSelected = true;
          break;
        case '--delete':
          if (modeSelected) throw ArgumentError('cleanup mode repeated');
          mode = PreReleaseCleanupMode.delete;
          modeSelected = true;
          break;
        case '--confirm':
          confirmation = _take(args, ++index, '--confirm');
          break;
        case '-h':
        case '--help':
          help = true;
          break;
        default:
          throw ArgumentError('unknown option: ${args[index]}');
      }
    }
    if (!help && (supportRoot == null || supportRoot.trim().isEmpty)) {
      throw ArgumentError('--support-root is required');
    }
    return _CleanupOptions(
      supportRoot: supportRoot,
      mode: mode,
      confirmation: confirmation,
      namespaces: List<String>.unmodifiable(namespaces),
      help: help,
    );
  }

  static String _take(List<String> args, int index, String option) {
    if (index >= args.length) throw ArgumentError('$option requires a value');
    return args[index];
  }

  static void printUsage() {
    stdout.writeln('''
Inventory or clean pre-release AWiki Me namespace storage.

Default mode is dry-run. The tool never reads or prints Keychain values.

Usage:
  dart run scripts/pre_release_storage_cleanup.dart --support-root PATH [--namespace NAME]
  dart run scripts/pre_release_storage_cleanup.dart --support-root PATH --archive --confirm $archiveConfirmation
  dart run scripts/pre_release_storage_cleanup.dart --support-root PATH --delete --confirm $deleteConfirmation
''');
  }
}
