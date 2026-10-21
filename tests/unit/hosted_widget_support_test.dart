import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/presentation/onboarding/onboarding_outlined_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../e2e/flutter/support/hosted_widget_support.dart';

void main() {
  test('hosted failure diagnostics never echo arbitrary private details', () {
    expect(hostedFailureCode(StateError('private-token')), 'StateError');
    expect(
      hostedFailureCode(
        const core.AwikiImCoreException(
          code: 'local_state_unavailable',
          message: 'private-token',
          serviceDataJson: 'private-payload',
        ),
      ),
      'core_local_state_unavailable',
    );
    expect(
      hostedFailureCode(
        const core.AwikiImCoreException(
          code: 'private-token',
          message: 'private-token',
        ),
      ),
      'AwikiImCoreException',
    );
    expect(
      hostedFailureCode(StateError('hosted_app_field_missing')),
      'hosted_app_field_missing',
    );
  });
  testWidgets('hosted input locates the rendered onboarding field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: OnboardingOutlinedField(
            controller: controller,
            label: 'Handle',
            placeholder: 'Handle',
            semanticsIdentifier: 'synthetic-field',
          ),
        ),
      ),
    );
    await input(tester, 'synthetic-field', 'synthetic');
    expect(controller.text, 'synthetic');
  });
}
