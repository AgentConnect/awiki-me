import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares complete SemVer prerelease precedence and ignores build', () {
    expect(compareAppVersions('1.0.0-beta.2', '1.0.0-beta.11'), lessThan(0));
    expect(compareAppVersions('1.0.0-rc.1', '1.0.0'), lessThan(0));
    expect(compareAppVersions('1.0.0+build.2', '1.0.0+build.1'), 0);
  });

  test('rejects leading zero numeric prerelease identifiers', () {
    expect(
      () => compareAppVersions('1.0.0-beta.01', '1.0.0'),
      throwsFormatException,
    );
  });
}
