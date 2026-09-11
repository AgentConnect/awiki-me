// [INPUT]: Isolated E2E App builder command-line arguments.
// [OUTPUT]: One machine-readable prepared artifact or a stable non-zero error.
// [POS]: Thin CLI entrypoint; build/cache implementation lives in isolated_e2e_app_builder.dart.

import 'dart:convert';
import 'dart:io';

import 'isolated_e2e_app_builder.dart';

export 'isolated_e2e_app_builder.dart';

Future<void> main(List<String> args) async {
  try {
    final request = IsolatedE2eAppBuildRequest.parse(
      args,
      projectRoot: Directory.current,
    );
    final artifact = await IsolatedE2eAppBuilder().build(request);
    stdout.writeln(jsonEncode(artifact.toJson()));
  } on IsolatedE2eAppBuildException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
