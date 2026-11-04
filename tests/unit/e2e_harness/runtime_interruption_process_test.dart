import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/runtime_control/invocation.dart';
import '../../e2e/prepared_integration_process.dart';

void main() {
  for (final mode in ['checkpoint', 'wrong_pid', 'early_exit']) {
    test(
      'expected interruption owns its process and rejects $mode as a pass',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'interruption-process-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final plan = E2eInvocation(
          artifact: 'recovery-crash-a',
          runId: 'unit-run',
          scenario: 'unit-scenario',
          invocationId: 'unit-invocation',
          platform: 'windows',
          caseIds: const ['CASE-001'],
          artifactSha256: 'a' * 64,
          interruption: 'recoveryBeforeProductReset',
        );
        final planFile = File('${dir.path}/private/plan.json');
        plan.write(planFile);
        final checkpoint = File('${planFile.path}.checkpoint');
        final completion = File('${dir.path}/completion.json');
        final sentinel = File('${dir.path}/graceful-finally');
        final exe = File('${dir.path}/fixture.exe');
        final source = File('${dir.path}/fixture.cs');
        String b64(String value) => base64Encode(utf8.encode(value));
        final event = jsonEncode({
          'schemaVersion': 1,
          'invocationId': plan.invocationId,
          'planDigest': plan.digest,
          'checkpoint': plan.interruption,
          'pid': 0,
          'occurrence': 1,
        });
        await source.writeAsString('''
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
public class Fixture {
  static string Decode(string s) { return Encoding.UTF8.GetString(Convert.FromBase64String(s)); }
  public static void Main() {
    if (Environment.GetEnvironmentVariable("AWIKI_FIXTURE_EARLY_EXIT") == "1") return;
    string path=Decode("${b64(checkpoint.path)}");
    string payload=Decode("${b64(event)}").Replace(((char)34)+"pid"+((char)34)+":0", ((char)34)+"pid"+((char)34)+":"+(Process.GetCurrentProcess().Id${mode == 'wrong_pid' ? '+1' : ''}).ToString());
    File.WriteAllText(path+".tmp",payload,new UTF8Encoding(false));
    var acl=File.GetAccessControl(path+".tmp");
    acl.SetOwner(System.Security.Principal.WindowsIdentity.GetCurrent().User);
    File.SetAccessControl(path+".tmp",acl);
    File.Move(path+".tmp",path);
    try { System.Threading.Thread.Sleep(30000); }
    finally { File.WriteAllText(Decode("${b64(sentinel.path)}"),"graceful"); }
  }
}
''');
        final compilation = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            r'Add-Type -TypeDefinition ([IO.File]::ReadAllText($env:AWIKI_FIXTURE_SOURCE)) -OutputAssembly $env:AWIKI_FIXTURE_EXE -OutputType ConsoleApplication',
          ],
          environment: {
            'AWIKI_FIXTURE_SOURCE': source.path,
            'AWIKI_FIXTURE_EXE': exe.path,
          },
        );
        expect(
          compilation.exitCode,
          0,
          reason: 'Native unit fixture must compile.',
        );
        final env = {
          invocationPathEnvironment: planFile.path,
          invocationDigestEnvironment: plan.digest,
          if (mode == 'early_exit') 'AWIKI_FIXTURE_EARLY_EXIT': '1',
          'AWIKI_E2E_RUN_ID': plan.runId,
          'AWIKI_E2E_SCENARIO': plan.scenario,
          'AWIKI_E2E_CASE_IDS': plan.caseIds.join(','),
        };
        final execution = runPreparedIntegrationExecutable(
          executable: exe,
          operatingSystem: 'windows',
          environment: env,
          completionFile: completion,
          expectedScenario: plan.scenario,
          expectedRunId: plan.runId,
          expectedCaseIds: plan.caseIds,
          timeout: const Duration(seconds: 10),
          expectedInterruption: plan,
        );
        if (mode == 'checkpoint') {
          final result = await execution;
          expect(result.terminatedAfterCheckpoint, isTrue);
          expect(result.terminatedAfterCompletion, isFalse);
          expect(completion.existsSync(), isFalse);
          expect(sentinel.existsSync(), isFalse);
        } else {
          await expectLater(
            execution,
            throwsA(
              isA<PreparedIntegrationProcessException>().having(
                (error) => error.message,
                'failure boundary',
                contains(
                  mode == 'wrong_pid'
                      ? 'Checkpoint identity or lifecycle is invalid'
                      : 'exited before completion',
                ),
              ),
            ),
          );
        }
      },
      skip: !Platform.isWindows,
    );
  }
}
