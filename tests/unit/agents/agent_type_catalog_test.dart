import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/presentation/agents/agent_type_catalog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support.dart';

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final dimensions in [(320.0, 3.0), (720.0, 1.0), (720.0, 2.0)]) {
      testWidgets(
        'complete packaged catalogue ${locale.languageCode} width=${dimensions.$1} text=${dimensions.$2}',
        (tester) async {
          tester.view.physicalSize = Size(dimensions.$1, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = dimensions.$2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            buildLocalizedTestApp(
              locale: locale,
              home: CupertinoPageScaffold(
                child: SingleChildScrollView(
                  child: Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return Column(
                        children: [
                          Text(
                            l10n.agentInstallSupportedTypes(
                              AgentTypeCatalog.names(l10n),
                            ),
                          ),
                          AgentTypeGrid(
                            builder: (kind) => Container(
                              key: ValueKey(kind),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  AgentTypeIcon(kind: kind),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(kind.displayLabel),
                                        Text(
                                          AgentTypeCatalog.description(
                                            l10n,
                                            kind,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(AgentTypeIcon), findsNWidgets(7));
          final first = tester.getRect(
            find.byKey(const ValueKey(RuntimeAgentKind.hermes)),
          );
          final second = tester.getRect(
            find.byKey(const ValueKey(RuntimeAgentKind.codex)),
          );
          if (dimensions.$1 >= 640 && dimensions.$2 == 1) {
            expect(first.top, second.top);
            expect(second.left, greaterThan(first.right));
            expect(first.height, second.height);
          } else {
            expect(first.left, second.left);
            expect(second.top, greaterThan(first.bottom));
          }
          for (final kind in RuntimeAgentKind.values) {
            await tester.ensureVisible(find.byKey(ValueKey(kind)));
            await tester.pumpAndSettle();
            expect(find.text(kind.displayLabel), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
