// [INPUT]: Product-owned prepared App artifact specification JSON.
// [OUTPUT]: Validated artifact identities and suite-to-artifact closure.
// [POS]: Single source of truth shared by the AWiki Me runner and orchestrator.

import 'dart:convert';
import 'dart:io';

final class E2eAppArtifactSpec {
  const E2eAppArtifactSpec({
    required this.name,
    required this.target,
    required this.bundleId,
    required this.supportedPlatforms,
    required this.dartDefines,
    required this.consumerSuites,
  });

  final String name;
  final String target;
  final String bundleId;
  final List<String> supportedPlatforms;
  final List<String> dartDefines;
  final List<String> consumerSuites;
}

final class E2eAppArtifactSpecManifest {
  const E2eAppArtifactSpecManifest({
    required this.sourceRevision,
    required this.specs,
  });

  final String sourceRevision;
  final Map<String, E2eAppArtifactSpec> specs;

  factory E2eAppArtifactSpecManifest.load(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'App artifact specs must use schemaVersion 1.',
      );
    }
    final sourceRevision = decoded['sourceRevision'];
    final entries = decoded['artifacts'];
    if (sourceRevision is! String ||
        sourceRevision.trim().isEmpty ||
        entries is! List ||
        entries.isEmpty) {
      throw const FormatException('App artifact spec manifest is incomplete.');
    }
    final specs = <String, E2eAppArtifactSpec>{};
    for (final entry in entries) {
      if (entry is! Map) {
        throw const FormatException('App artifact spec must be an object.');
      }
      final name = _requiredString(entry, 'name');
      final target = _requiredString(entry, 'target');
      final bundleId = _requiredString(entry, 'bundleId');
      if (!RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(name) ||
          !target.startsWith('integration_test/') ||
          !target.endsWith('_test.dart') ||
          target.contains('..') ||
          !RegExp(
            r'^[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+$',
          ).hasMatch(bundleId)) {
        throw FormatException('App artifact spec identity is invalid: $name');
      }
      if (specs.containsKey(name)) {
        throw FormatException('Duplicate App artifact spec: $name');
      }
      final platforms = _uniqueStrings(entry, 'supportedPlatforms');
      if (platforms.isEmpty ||
          platforms.any((value) => !const {'macos', 'linux'}.contains(value))) {
        throw FormatException(
          'App artifact spec has invalid supportedPlatforms: $name',
        );
      }
      final consumers = _uniqueStrings(entry, 'consumerSuites');
      if (consumers.isEmpty) {
        throw FormatException('App artifact spec has no consumers: $name');
      }
      specs[name] = E2eAppArtifactSpec(
        name: name,
        target: target,
        bundleId: bundleId,
        supportedPlatforms: platforms,
        dartDefines: canonicalCompileTimeDartDefines(
          _uniqueStrings(entry, 'dartDefines'),
        ),
        consumerSuites: consumers,
      );
    }
    return E2eAppArtifactSpecManifest(
      sourceRevision: sourceRevision,
      specs: Map<String, E2eAppArtifactSpec>.unmodifiable(specs),
    );
  }

  E2eAppArtifactSpec requireSpec(String name) {
    final spec = specs[name];
    if (spec == null) {
      throw FormatException('Unknown App artifact spec: $name');
    }
    return spec;
  }

  List<E2eAppArtifactSpec> specsForSuite(
    String suite, {
    required String platform,
  }) => List<E2eAppArtifactSpec>.unmodifiable(
    specs.values.where(
      (spec) =>
          spec.consumerSuites.contains(suite) &&
          spec.supportedPlatforms.contains(platform),
    ),
  );
}

List<String> canonicalCompileTimeDartDefines(Iterable<String> values) {
  final definitions = <String, String>{};
  for (final define in values) {
    final separator = define.indexOf('=');
    if (separator <= 0 || separator == define.length - 1) {
      throw const FormatException(
        'Each App artifact dartDefine must contain KEY=VALUE.',
      );
    }
    final key = define.substring(0, separator).trim();
    if (key.isEmpty || definitions.containsKey(key)) {
      throw const FormatException(
        'Each App artifact dartDefine key must be unique and non-empty.',
      );
    }
    definitions[key] = define.substring(separator + 1);
  }
  final keys = definitions.keys.toList()..sort();
  return List<String>.unmodifiable(
    keys.map((key) => '$key=${definitions[key]}'),
  );
}

String _requiredString(Map<dynamic, dynamic> value, String key) {
  final selected = value[key];
  if (selected is! String || selected.trim().isEmpty) {
    throw FormatException('App artifact spec omitted $key.');
  }
  return selected.trim();
}

List<String> _uniqueStrings(Map<dynamic, dynamic> value, String key) {
  final selected = value[key];
  if (selected is! List ||
      selected.any((item) => item is! String || item.trim().isEmpty)) {
    throw FormatException('App artifact spec has invalid $key.');
  }
  final values = selected.cast<String>().map((item) => item.trim()).toList();
  if (values.length != values.toSet().length) {
    throw FormatException('App artifact spec has duplicate $key.');
  }
  return List<String>.unmodifiable(values);
}
