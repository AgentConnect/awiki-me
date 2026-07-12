import 'dart:convert';
import 'dart:io';

const String defaultCoveragePath = 'coverage/lcov.info';
const String defaultCoveragePolicyPath = 'tests/quality/coverage_baseline.json';

class CoverageMetric {
  const CoverageMetric({
    required this.linesFound,
    required this.linesHit,
    required this.branchesFound,
    required this.branchesHit,
  });

  final int linesFound;
  final int linesHit;
  final int branchesFound;
  final int branchesHit;

  double get linePercent => _percent(linesHit, linesFound);
  double get branchPercent => _percent(branchesHit, branchesFound);

  CoverageMetric operator +(CoverageMetric other) => CoverageMetric(
    linesFound: linesFound + other.linesFound,
    linesHit: linesHit + other.linesHit,
    branchesFound: branchesFound + other.branchesFound,
    branchesHit: branchesHit + other.branchesHit,
  );
}

class LcovReport {
  const LcovReport(this.files);

  final Map<String, CoverageMetric> files;

  CoverageMetric get overall => files.values.fold(
    const CoverageMetric(
      linesFound: 0,
      linesHit: 0,
      branchesFound: 0,
      branchesHit: 0,
    ),
    (total, current) => total + current,
  );

  factory LcovReport.parse(String value) {
    final files = <String, CoverageMetric>{};
    String? currentPath;
    final lineHits = <int, int>{};
    final branchHits = <bool>[];

    void finishRecord() {
      final path = currentPath;
      if (path == null) {
        return;
      }
      files[path] = CoverageMetric(
        linesFound: lineHits.length,
        linesHit: lineHits.values.where((hits) => hits > 0).length,
        branchesFound: branchHits.length,
        branchesHit: branchHits.where((hit) => hit).length,
      );
      currentPath = null;
      lineHits.clear();
      branchHits.clear();
    }

    for (final rawLine in const LineSplitter().convert(value)) {
      if (rawLine.startsWith('SF:')) {
        finishRecord();
        currentPath = _normalizeSourcePath(rawLine.substring(3));
      } else if (rawLine.startsWith('DA:') && currentPath != null) {
        final fields = rawLine.substring(3).split(',');
        if (fields.length >= 2) {
          lineHits[int.parse(fields[0])] = int.parse(fields[1]);
        }
      } else if (rawLine.startsWith('BRDA:') && currentPath != null) {
        final taken = rawLine.substring(5).split(',').last;
        branchHits.add(taken != '-' && int.parse(taken) > 0);
      } else if (rawLine == 'end_of_record') {
        finishRecord();
      }
    }
    finishRecord();
    if (files.isEmpty) {
      throw const FormatException('LCOV report contains no source records');
    }
    return LcovReport(Map<String, CoverageMetric>.unmodifiable(files));
  }
}

class CoverageGate {
  const CoverageGate({required this.overall, required this.files});

  final CoverageThreshold overall;
  final Map<String, CoverageThreshold> files;

  factory CoverageGate.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('coverage policy must use schemaVersion 1');
    }
    final rawFiles = _object(json['files'], label: 'coverage policy files');
    return CoverageGate(
      overall: CoverageThreshold.fromJson(
        _object(json['overall'], label: 'coverage policy overall'),
        label: 'overall',
      ),
      files: Map<String, CoverageThreshold>.unmodifiable(
        <String, CoverageThreshold>{
          for (final entry in rawFiles.entries)
            entry.key: CoverageThreshold.fromJson(
              _object(entry.value, label: 'coverage policy ${entry.key}'),
              label: entry.key,
            ),
        },
      ),
    );
  }

  List<String> validate(LcovReport report) {
    final errors = <String>[
      ...overall.validate(report.overall, label: 'overall'),
    ];
    for (final entry in files.entries) {
      final metric = report.files[entry.key];
      if (metric == null) {
        errors.add('coverage is missing required source ${entry.key}');
        continue;
      }
      errors.addAll(entry.value.validate(metric, label: entry.key));
    }
    return errors;
  }
}

class CoverageThreshold {
  const CoverageThreshold({
    required this.minimumLinePercent,
    required this.minimumBranchPercent,
  });

  final double minimumLinePercent;
  final double minimumBranchPercent;

  factory CoverageThreshold.fromJson(
    Map<String, Object?> json, {
    required String label,
  }) {
    double requirePercent(String key) {
      final value = json[key];
      if (value is! num || value < 0 || value > 100) {
        throw FormatException('$label $key must be between 0 and 100');
      }
      return value.toDouble();
    }

    return CoverageThreshold(
      minimumLinePercent: requirePercent('minimumLinePercent'),
      minimumBranchPercent: requirePercent('minimumBranchPercent'),
    );
  }

  List<String> validate(CoverageMetric metric, {required String label}) {
    final errors = <String>[];
    if (metric.linePercent + 0.000001 < minimumLinePercent) {
      errors.add(
        '$label line coverage ${metric.linePercent.toStringAsFixed(2)}% is below '
        '${minimumLinePercent.toStringAsFixed(2)}%',
      );
    }
    if (metric.branchesFound == 0) {
      errors.add('$label has no branch coverage records');
    } else if (metric.branchPercent + 0.000001 < minimumBranchPercent) {
      errors.add(
        '$label branch coverage ${metric.branchPercent.toStringAsFixed(2)}% is below '
        '${minimumBranchPercent.toStringAsFixed(2)}%',
      );
    }
    return errors;
  }
}

Future<void> main(List<String> args) async {
  try {
    final coveragePath = _argumentValue(
      args,
      '--coverage',
      fallback: defaultCoveragePath,
    );
    final policyPath = _argumentValue(
      args,
      '--policy',
      fallback: defaultCoveragePolicyPath,
    );
    final report = LcovReport.parse(File(coveragePath).readAsStringSync());
    final decoded = jsonDecode(File(policyPath).readAsStringSync());
    final policy = CoverageGate.fromJson(
      _object(decoded, label: 'coverage policy'),
    );
    final errors = policy.validate(report);
    if (errors.isNotEmpty) {
      throw StateError(errors.join('\n'));
    }
    final overall = report.overall;
    stdout.writeln(
      'Coverage gate passed: lines '
      '${overall.linePercent.toStringAsFixed(2)}% '
      '(${overall.linesHit}/${overall.linesFound}), branches '
      '${overall.branchPercent.toStringAsFixed(2)}% '
      '(${overall.branchesHit}/${overall.branchesFound}).',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

String _argumentValue(
  List<String> args,
  String name, {
  required String fallback,
}) {
  final index = args.indexOf(name);
  if (index < 0) {
    return fallback;
  }
  if (index + 1 >= args.length) {
    throw FormatException('$name requires a value');
  }
  return args[index + 1];
}

Map<String, Object?> _object(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be an object');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String _normalizeSourcePath(String value) {
  const sourceMarker = '/lib/';
  final sourceIndex = value.indexOf(sourceMarker);
  if (sourceIndex >= 0) {
    return value.substring(sourceIndex + 1);
  }
  return value.replaceFirst(RegExp(r'^\./'), '');
}

double _percent(int hit, int found) => found == 0 ? 100 : hit * 100 / found;
