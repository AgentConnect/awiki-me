import 'package:awiki_me/src/domain/entities/agent/agent_availability.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/presentation/agents/agent_availability_provider.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  for (final width in [320.0, 800.0]) {
    for (final locale in [const Locale('zh'), const Locale('en')]) {
      testWidgets(
        'unavailable member retains identity and removal at width=$width locale=$locale',
        (tester) async {
          var removed = false;
          const did = 'did:agent:retired';
          const name = 'A very long Agent name 智能体名称需要保留';
          await tester.pumpWidget(
            buildLocalizedTestApp(
              locale: locale,
              providerOverrides: [
                effectiveAgentAvailabilityProvider.overrideWith(
                  (ref) => const {
                    did: AgentAvailability(
                      agentDid: did,
                      state: AgentAvailabilityState.unavailable,
                      reason: 'agent_retired',
                    ),
                  },
                ),
              ],
              home: CupertinoPageScaffold(
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                      ),
                      child: GroupMemberRow(
                        item: const GroupMemberSummary(
                          userId: did,
                          did: did,
                          handle: 'agent.test',
                          role: 'member',
                          displayName: name,
                          subjectType: GroupMemberSubjectType.agent,
                        ),
                        onRemove: () => removed = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(name), findsOneWidget);
          expect(find.text('@agent.test'), findsOneWidget);
          expect(
            find.text(locale.languageCode == 'zh' ? '不可用' : 'Unavailable'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final remove = tester.widget<AppIconButton>(
            find.byType(AppIconButton),
          );
          expect(remove.onPressed, isNotNull);
          await tester.tap(find.byType(AppIconButton));
          expect(removed, isTrue);
        },
      );
    }
  }
}
