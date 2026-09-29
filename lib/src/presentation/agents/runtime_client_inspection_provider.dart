import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/agent/runtime_client_inspection_service.dart';
import '../../domain/entities/agent/runtime_client_installation.dart';
import '../app_shell/providers/session_provider.dart';

final runtimeClientInspectionServiceProvider =
    Provider<RuntimeClientInspectionService>(
      (ref) =>
          RuntimeClientInspectionService(ref.watch(messagingServiceProvider)),
    );

class RuntimeClientInspectionState {
  const RuntimeClientInspectionState({
    this.loading = false,
    this.failed = false,
    this.report,
  });
  final bool loading;
  final bool failed;
  final RuntimeClientInstallationReport? report;
}

class RuntimeClientInspectionController
    extends StateNotifier<RuntimeClientInspectionState> {
  RuntimeClientInspectionController(this.service, this.daemonDid)
    : super(const RuntimeClientInspectionState());
  final RuntimeClientInspectionService service;
  final String daemonDid;
  int _generation = 0;

  Future<void> inspect({bool refresh = false}) async {
    if (state.loading) return;
    final generation = ++_generation;
    state = RuntimeClientInspectionState(loading: true, report: state.report);
    try {
      final report = await service.inspect(daemonDid, refresh: refresh);
      if (mounted && generation == _generation) {
        state = RuntimeClientInspectionState(report: report);
      }
    } on Object {
      if (mounted && generation == _generation) {
        state = RuntimeClientInspectionState(
          failed: true,
          report: state.report,
        );
      }
    }
  }
}

final runtimeClientInspectionProvider = StateNotifierProvider.autoDispose
    .family<
      RuntimeClientInspectionController,
      RuntimeClientInspectionState,
      String
    >((ref, daemonDid) {
      ref.watch(sessionProvider.select((state) => state.activeEpoch));
      return RuntimeClientInspectionController(
        ref.watch(runtimeClientInspectionServiceProvider),
        daemonDid,
      );
    });
