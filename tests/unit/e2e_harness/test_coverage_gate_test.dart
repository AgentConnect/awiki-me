import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_coverage_gate.dart';

void main() {
  test('coverage gate enforces line and branch floors per critical file', () {
    final report = LcovReport.parse('''
SF:lib/critical.dart
DA:1,1
DA:2,0
BRDA:1,0,0,1
BRDA:1,0,1,0
end_of_record
''');
    const gate = CoverageGate(
      overall: CoverageThreshold(
        minimumLinePercent: 50,
        minimumBranchPercent: 50,
      ),
      files: <String, CoverageThreshold>{
        'lib/critical.dart': CoverageThreshold(
          minimumLinePercent: 50,
          minimumBranchPercent: 50,
        ),
      },
    );

    expect(gate.validate(report), isEmpty);
    const strict = CoverageGate(
      overall: CoverageThreshold(
        minimumLinePercent: 51,
        minimumBranchPercent: 51,
      ),
      files: <String, CoverageThreshold>{
        'lib/missing.dart': CoverageThreshold(
          minimumLinePercent: 1,
          minimumBranchPercent: 1,
        ),
      },
    );

    expect(
      strict.validate(report),
      allOf(
        contains('overall line coverage 50.00% is below 51.00%'),
        contains('overall branch coverage 50.00% is below 51.00%'),
        contains('coverage is missing required source lib/missing.dart'),
      ),
    );
  });

  test('coverage gate fails when branch records are absent', () {
    final report = LcovReport.parse('''
SF:lib/no_branches.dart
DA:1,1
end_of_record
''');
    const gate = CoverageGate(
      overall: CoverageThreshold(
        minimumLinePercent: 100,
        minimumBranchPercent: 0,
      ),
      files: <String, CoverageThreshold>{},
    );

    expect(gate.validate(report), <String>[
      'overall has no branch coverage records',
    ]);
  });
}
