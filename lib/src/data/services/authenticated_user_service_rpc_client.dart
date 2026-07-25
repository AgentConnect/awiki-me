import '../../application/auth/auth_session_coordinator.dart';
import 'awiki_onboarding_utility_client.dart';

class AuthenticatedUserServiceRpcClient {
  AuthenticatedUserServiceRpcClient({
    required AwikiOnboardingUtilityHttpClient client,
    required AuthSessionCoordinator sessions,
  }) : _client = client,
       _sessions = sessions;

  final AwikiOnboardingUtilityHttpClient _client;
  final AuthSessionCoordinator _sessions;

  String get baseUrl => _client.baseUrl;

  Future<Map<String, Object?>> rpcCall({
    required String path,
    required String method,
    required Map<String, Object?> params,
    String requestId = 'req-1',
  }) async {
    final session = await _sessions.ensureBearerSession();
    try {
      return await _client.rpcCall(
        path: path,
        method: method,
        params: params,
        bearerToken: session.bearerToken,
        requestId: requestId,
      );
    } on AwikiOnboardingUtilityError catch (error) {
      if (!_isAuthFailure(error)) {
        rethrow;
      }
      final refreshed = await _sessions.ensureBearerSession(
        forceRefresh: true,
        expectedTransition: session.transition,
      );
      return _client.rpcCall(
        path: path,
        method: method,
        params: params,
        bearerToken: refreshed.bearerToken,
        requestId: requestId,
      );
    }
  }
}

bool _isAuthFailure(AwikiOnboardingUtilityError error) {
  if (error.statusCode == 401 || error.rpcCode == -32000) {
    return true;
  }
  final message = error.message.toLowerCase();
  return message.contains('authorization') ||
      message.contains('invalid token') ||
      message.contains('token expired') ||
      message.contains('session expired') ||
      message.contains('unauthenticated');
}
