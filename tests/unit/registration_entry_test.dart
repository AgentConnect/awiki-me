// StateNotifier direct controller tests intentionally inspect transient state.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/presentation/onboarding/registration_entry_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class CheckSupport extends FakeOnboardingSupportService {
  CheckSupport() : super(FakeAwikiGateway());
  final calls = <Map<String, Object?>>[];
  Future<RegistrationCheck> Function(String, bool)? responder;

  @override
  Future<RegistrationCheck> checkRegistration({
    required String handle,
    required String domain,
    String? inviteCode,
    String? phone,
    String? email,
    bool checkInvite = false,
  }) {
    calls.add({
      'handle': handle,
      'domain': domain,
      'inviteCode': inviteCode,
      'phone': phone,
      'email': email,
      'checkInvite': checkInvite,
    });
    return responder?.call(handle, checkInvite) ??
        Future.value(
          result(
            handle,
            required: handle.length == 3,
            status: checkInvite && handle.length == 3 ? "valid" : null,
          ),
        );
  }
}

RegistrationCheck result(
  String handle, {
  bool required = false,
  String decision = 'register',
  String? status,
}) => RegistrationCheck(
  fullHandle: '$handle.example.com',
  decision: decision,
  inviteRequired: required,
  inviteStatus: status ?? (required ? 'required' : 'not_required'),
  reason: status == 'invalid' ? 'invite_invalid' : null,
);

void main() {
  late CheckSupport support;
  late RegistrationEntryController controller;
  setUp(() {
    support = CheckSupport();
    controller = RegistrationEntryController(support);
  });
  tearDown(() => controller.dispose());

  test('three-character name requires invite before verification', () async {
    await controller.checkAccount(' ABC ', 'EXAMPLE.COM');
    expect(controller.state.step, RegistrationEntryStep.invite);
    await controller.continueWithInvite(' ');
    expect(controller.state.error, 'invite_required');
    expect(
      await controller.prepareVerification(phone: '+12025550123'),
      isFalse,
    );
    expect(support.calls, hasLength(1));
    await controller.continueWithInvite(' fixture ');
    expect(controller.state.step, RegistrationEntryStep.verification);
    expect(controller.state.inviteCode, 'fixture');
  });

  test(
    'invite next rejects invalid code before contact entry and allows retry',
    () async {
      await controller.checkAccount('abc', 'example.com');
      support.responder = (handle, _) async =>
          result(handle, required: true, status: 'invalid');
      await controller.continueWithInvite('wrong');
      expect(controller.state.step, RegistrationEntryStep.invite);
      expect(controller.state.error, 'invite_invalid');
      expect(support.calls.last, containsPair('checkInvite', true));
      expect(support.calls.last['phone'], isNull);
      expect(
        await controller.prepareVerification(phone: '+12025550123'),
        isFalse,
      );
      support.responder = (handle, _) async =>
          result(handle, required: true, status: 'valid');
      await controller.continueWithInvite('valid');
      expect(controller.state.step, RegistrationEntryStep.verification);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'invite request is single flight and reset discards late success',
    () async {
      await controller.checkAccount('abc', 'example.com');
      final pending = Completer<RegistrationCheck>();
      support.responder = (_, _) => pending.future;
      final check = controller.continueWithInvite('valid');
      await controller.continueWithInvite('other');
      expect(support.calls, hasLength(2));
      expect(controller.state.busy, isTrue);
      controller.reset();
      pending.complete(result('abc', required: true, status: 'valid'));
      await check;
      expect(controller.state.step, RegistrationEntryStep.account);
      expect(controller.state.inviteCode, isEmpty);
    },
  );

  test('invite request failure remains on invite page and can retry', () async {
    await controller.checkAccount('abc', 'example.com');
    support.responder = (_, _) => Future.error(StateError('offline'));
    await controller.continueWithInvite('valid');
    expect(controller.state.step, RegistrationEntryStep.invite);
    expect(controller.state.error, 'check_failed');
    expect(controller.state.busy, isFalse);
  });

  test('server policy overrides local handle length', () async {
    support.responder = (handle, _) async => result(handle, required: true);
    await controller.checkAccount('longname', 'example.com');
    expect(controller.state.step, RegistrationEntryStep.invite);
  });

  test(
    'invite is checked with contact before permission to send verification',
    () async {
      await controller.checkAccount('abc', 'example.com');
      await controller.continueWithInvite('fixture');
      support.responder = (handle, _) async =>
          result(handle, required: true, status: 'valid');
      expect(
        await controller.prepareVerification(phone: '+12025550123'),
        isTrue,
      );
      expect(support.calls.last, containsPair('inviteCode', 'fixture'));
      expect(support.calls.last, containsPair('phone', '+12025550123'));
      expect(support.calls.last, containsPair('checkInvite', true));
    },
  );

  test('invalid invitation does not permit OTP or email activation', () async {
    await controller.checkAccount('abc', 'example.com');
    await controller.continueWithInvite('wrong');
    support.responder = (handle, _) async =>
        result(handle, required: true, status: 'invalid');
    expect(
      await controller.prepareVerification(email: 'person@example.net'),
      isFalse,
    );
    expect(controller.state.error, 'invite_invalid');
  });

  test(
    'existing short account never requires or validates invitation',
    () async {
      support.responder = (handle, _) async =>
          result(handle, decision: 'existing');
      await controller.checkAccount('abc', 'example.com');
      expect(
        await controller.prepareVerification(phone: '+12025550123'),
        isTrue,
      );
      expect(support.calls, hasLength(1));
      expect(controller.state.inviteCode, isEmpty);
    },
  );

  test(
    'failed discovery does not block explicit existing account path',
    () async {
      support.responder = (_, _) => Future.error(StateError('network'));
      await controller.checkAccount('abc', 'example.com');
      expect(controller.state.step, RegistrationEntryStep.account);
      expect(controller.state.error, 'check_failed');
      controller.continueExisting('abc', 'example.com');
      expect(
        await controller.prepareVerification(phone: '+12025550123'),
        isTrue,
      );
      expect(support.calls, hasLength(1));
    },
  );

  test('unknown discovery never silently permits new registration', () async {
    support.responder = (_, _) => Future.error(StateError('network'));
    await controller.checkAccount('alice', 'example.com');
    expect(
      await controller.prepareVerification(email: 'person@example.net'),
      isFalse,
    );
  });

  test('late name response cannot replace changed target', () async {
    final pending = Completer<RegistrationCheck>();
    support.responder = (_, _) => pending.future;
    final check = controller.checkAccount('abc', 'example.com');
    controller.reset();
    support.responder = (handle, _) async => result(handle);
    await controller.checkAccount('alice', 'example.com');
    pending.complete(result('abc', required: true));
    await check;
    expect(controller.state.handle, 'alice');
    expect(controller.state.step, RegistrationEntryStep.verification);
  });

  test(
    'contact or mode change cancels pending invitation permission',
    () async {
      await controller.checkAccount('abc', 'example.com');
      await controller.continueWithInvite('fixture');
      final pending = Completer<RegistrationCheck>();
      support.responder = (_, _) => pending.future;
      final verify = controller.prepareVerification(phone: '+12025550123');
      controller.invalidateVerification();
      pending.complete(result('abc', required: true, status: 'valid'));
      expect(await verify, isFalse);
      expect(controller.state.busy, isFalse);
    },
  );

  test(
    'changed or claimed name is decided again before verification',
    () async {
      await controller.checkAccount('alice', 'example.com');
      support.responder = (handle, _) async =>
          result(handle, decision: 'unavailable');
      expect(
        await controller.prepareVerification(email: 'person@example.net'),
        isFalse,
      );
      expect(controller.state.error, 'handle_unavailable');
    },
  );

  test(
    'reset discards invitation and repeated next only sends one request',
    () async {
      final pending = Completer<RegistrationCheck>();
      support.responder = (_, _) => pending.future;
      final first = controller.checkAccount('abc', 'example.com');
      await controller.checkAccount('abc', 'example.com');
      expect(support.calls, hasLength(1));
      pending.complete(result('abc', required: true));
      await first;
      await controller.continueWithInvite('fixture');
      controller.reset();
      expect(controller.state.inviteCode, isEmpty);
    },
  );

  test('wire result rejects wrong target and unknown/contradictory policy', () {
    final payload = <String, Object?>{
      'full_handle': 'abc.example.com',
      'decision': 'register',
      'invite_required': true,
      'invite_status': 'required',
    };
    expect(
      RegistrationCheck.fromJson(
        payload,
        expectedFullHandle: 'abc.example.com',
      ).canVerify,
      isFalse,
    );
    for (final patch in [
      {'full_handle': 'other.example.com'},
      {'decision': 'maybe'},
      {'decision': 'existing'},
      {'invite_status': 'not_required'},
    ]) {
      expect(
        () => RegistrationCheck.fromJson({
          ...payload,
          ...patch,
        }, expectedFullHandle: 'abc.example.com'),
        throwsFormatException,
      );
    }
  });
}
