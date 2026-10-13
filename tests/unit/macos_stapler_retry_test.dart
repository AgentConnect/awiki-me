import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (name: 'success', failures: 0, network: true, attempts: 1, succeeds: true),
    (
      name: 'transport recovers',
      failures: 2,
      network: true,
      attempts: 3,
      succeeds: true,
    ),
    (
      name: 'transport remains unavailable',
      failures: 9,
      network: true,
      attempts: 5,
      succeeds: false,
    ),
    (
      name: 'invalid ticket fails immediately',
      failures: 9,
      network: false,
      attempts: 1,
      succeeds: false,
    ),
  ]) {
    test('stapler ${scenario.name}', () {
      final temporary = Directory.systemTemp.createTempSync(
        'awiki-stapler-test-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final counter = File('${temporary.path}/attempts')
        ..writeAsStringSync('0');
      final result = Process.runSync('bash', [
        '-c',
        r'''
set -euo pipefail
source "$1"
test_counter="$2"
test_failures="$3"
test_network="$4"
sleep() { :; }
xcrun() {
  [[ "$1 $2 $3" == 'stapler validate candidate.dmg' ]] || return 99
  local n
  n="$(cat "$test_counter")"
  n=$((n + 1))
  printf '%s' "$n" > "$test_counter"
  if [[ "$n" -le "$test_failures" ]]; then
    if [[ "$test_network" == true ]]; then
      printf '%s\n' 'Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost."'
    else
      printf '%s\n' 'The validate action failed! Error 68. Ticket is invalid.'
    fi
    return 68
  fi
  printf '%s\n' 'The validate action worked!'
}
awiki_stapler_with_network_retry validate candidate.dmg
''',
        'stapler-test',
        File('scripts/lib/macos_signing.sh').absolute.path,
        counter.path,
        '${scenario.failures}',
        '${scenario.network}',
      ]);
      expect(
        result.exitCode == 0,
        scenario.succeeds,
        reason: '${result.stderr}',
      );
      expect(int.parse(counter.readAsStringSync()), scenario.attempts);
    });
  }
}
