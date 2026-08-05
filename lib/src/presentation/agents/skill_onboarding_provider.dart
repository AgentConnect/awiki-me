import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/auth/auth_session_coordinator.dart';
import '../../application/config/awiki_environment_config.dart';
import '../../application/models/app_session.dart';
import '../../application/ports/skill_onboarding_port.dart';
import '../../data/agent/user_service_agent_inventory_adapter.dart';
import '../../data/agent/user_service_skill_onboarding_adapter.dart';
import '../../data/services/authenticated_user_service_rpc_client.dart';
import '../../data/services/awiki_onboarding_utility_client.dart';
import '../../domain/entities/agent/skill_onboarding_instruction.dart';
import '../app_shell/providers/session_provider.dart';

enum SkillOnboardingError {
  loginRequired,
  handleRequired,
  unsupportedTenant,
  invalidResponse,
  requestFailed,
}

class SkillOnboardingState {
  const SkillOnboardingState({
    this.instruction,
    this.isLoading = false,
    this.error,
  });

  final SkillOnboardingInstruction? instruction;
  final bool isLoading;
  final SkillOnboardingError? error;
}

final skillOnboardingPortProvider = Provider<SkillOnboardingPort>((ref) {
  final environment = ref.watch(awikiEnvironmentConfigProvider);
  final adapter = UserServiceSkillOnboardingAdapter(
    userServiceUrl: environment.userServiceUrl,
  );
  final coordinator = AuthSessionCoordinator(
    sessions: ref.watch(appSessionServiceProvider),
    onSessionUpdated: (session) {
      ref
          .read(sessionProvider.notifier)
          .setSession(session.toLegacySessionIdentity());
    },
  );
  return adapter.withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient(
      client: adapter.httpClient,
      sessions: coordinator,
    ),
  );
});

final skillOnboardingProvider =
    StateNotifierProvider<SkillOnboardingController, SkillOnboardingState>((
      ref,
    ) {
      return SkillOnboardingController(ref);
    });

class SkillOnboardingController extends StateNotifier<SkillOnboardingState> {
  SkillOnboardingController(this.ref) : super(const SkillOnboardingState()) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (previous?.session?.did != next.session?.did ||
          previous?.session?.handle != next.session?.handle) {
        clear();
      }
    });
  }

  final Ref ref;
  Timer? _expiryTimer;
  int _generation = 0;
  static const _capabilityTimeout = Duration(seconds: 10);

  Future<void> generate() async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = const SkillOnboardingState(
        error: SkillOnboardingError.loginRequired,
      );
      return;
    }
    final handle = session.handle?.trim();
    if (handle == null || handle.isEmpty) {
      state = const SkillOnboardingState(
        error: SkillOnboardingError.handleRequired,
      );
      return;
    }
    final environment = ref.read(awikiEnvironmentConfigProvider);
    if (!isAgentDaemonTenantRealmAllowed(
      backendBaseUrl: environment.userServiceUrl,
      didHost: environment.didDomain,
    )) {
      state = const SkillOnboardingState(
        error: SkillOnboardingError.unsupportedTenant,
      );
      return;
    }

    _expiryTimer?.cancel();
    final generation = ++_generation;
    state = const SkillOnboardingState(isLoading: true);
    try {
      final serverInfo = await ref
          .read(onboardingSupportServiceProvider)
          .loadServerInfo()
          .timeout(_capabilityTimeout);
      final capability = serverInfo.agents.skillOnboarding;
      if (!capability.supportsCurrentProtocol) {
        _setError(generation, SkillOnboardingError.unsupportedTenant);
        return;
      }
      if (!_isCurrent(generation, session.did, handle)) {
        return;
      }
      final grant = await ref
          .read(skillOnboardingPortProvider)
          .issueSkillToken(
            controllerDid: session.did,
            controllerHandle: handle,
            clientPlatform: awikiClientPlatform(),
          );
      final instruction = buildSkillOnboardingInstruction(
        grant: grant,
        capability: capability,
        expectedServiceOrigin: environment.userServiceUrl,
        expectedControllerDid: session.did,
        expectedControllerHandle: handle,
      );
      if (!_isCurrent(generation, session.did, handle)) {
        return;
      }
      state = SkillOnboardingState(instruction: instruction);
      _expiryTimer = Timer(
        instruction.expiresAt.difference(DateTime.now()),
        () {
          if (mounted && generation == _generation) {
            state = const SkillOnboardingState();
          }
        },
      );
    } on FormatException {
      _setError(generation, SkillOnboardingError.invalidResponse);
    } on AwikiOnboardingUtilityError catch (error) {
      final data = error.data;
      final reason = data is Map ? data['reason']?.toString() : null;
      if (reason == 'skill_onboarding_capability_disabled') {
        _setError(generation, SkillOnboardingError.unsupportedTenant);
      } else {
        _setError(generation, SkillOnboardingError.requestFailed);
      }
    } on Object {
      _setError(generation, SkillOnboardingError.requestFailed);
    }
  }

  bool _isCurrent(int generation, String did, String handle) {
    final current = ref.read(sessionProvider).session;
    return mounted &&
        generation == _generation &&
        current?.did == did &&
        current?.handle?.trim() == handle;
  }

  void _setError(int generation, SkillOnboardingError error) {
    if (mounted && generation == _generation) {
      state = SkillOnboardingState(error: error);
    }
  }

  void clear() {
    _generation += 1;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (mounted) {
      state = const SkillOnboardingState();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
