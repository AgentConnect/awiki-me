import 'package:awiki_me/src/application/desktop_startup_presentation_service.dart';
import 'package:awiki_me/src/presentation/shared/desktop_startup_ready_boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingPresentationService
    implements DesktopStartupPresentationService {
  int callCount = 0;

  @override
  Future<void> presentReadyContent() async {
    callCount += 1;
  }
}

final class _ThrowingPresentationService
    implements DesktopStartupPresentationService {
  const _ThrowingPresentationService();

  @override
  Future<void> presentReadyContent() async {
    throw StateError('native channel unavailable');
  }
}

void main() {
  testWidgets('reports ready once after the destination frame', (tester) async {
    final service = _RecordingPresentationService();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DesktopStartupReadyBoundary(
          presentationService: service,
          child: const SizedBox(key: Key('ready-destination')),
        ),
      ),
    );

    expect(find.byKey(const Key('ready-destination')), findsOneWidget);
    expect(service.callCount, 1);

    await tester.pump();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DesktopStartupReadyBoundary(
          presentationService: service,
          child: const SizedBox(key: Key('updated-destination')),
        ),
      ),
    );

    expect(find.byKey(const Key('updated-destination')), findsOneWidget);
    expect(service.callCount, 1);
  });

  testWidgets('native presentation failure does not break rendered content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DesktopStartupReadyBoundary(
          presentationService: _ThrowingPresentationService(),
          child: SizedBox(key: Key('ready-despite-native-failure')),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('ready-despite-native-failure')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
