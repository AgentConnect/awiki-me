import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mention trigger detection', () {
    test('detects group @ query and ignores direct chat', () {
      final trigger = ChatMentionTrigger.detect(
        text: 'hello @her',
        selectionBaseOffset: 'hello @her'.length,
        selectionExtentOffset: 'hello @her'.length,
        composingStart: -1,
        composingEnd: -1,
        isGroup: true,
      );

      expect(trigger, isNotNull);
      expect(trigger!.query, 'her');
      expect(trigger.start, 6);
      expect(
        ChatMentionTrigger.detect(
          text: 'hello @her',
          selectionBaseOffset: 'hello @her'.length,
          selectionExtentOffset: 'hello @her'.length,
          composingStart: -1,
          composingEnd: -1,
          isGroup: false,
        ),
        isNull,
      );
    });

    test('mention trigger ignores active IME composing range', () {
      expect(
        ChatMentionTrigger.detect(
          text: '@he',
          selectionBaseOffset: 3,
          selectionExtentOffset: 3,
          composingStart: 1,
          composingEnd: 3,
          isGroup: true,
        ),
        isNull,
      );
    });
  });

  group('mention candidate search', () {
    test(
      'typed human and agent members are selectable with explicit badges',
      () {
        final candidates =
            ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
              GroupMemberSummary(
                userId: 'did:wba:awiki.info:u:alice',
                did: 'did:wba:awiki.info:u:alice',
                handle: 'alice',
                role: 'member',
                displayName: 'Alice',
                subjectType: GroupMemberSubjectType.human,
              ),
              GroupMemberSummary(
                userId: 'did:agent:hermes',
                did: 'did:agent:hermes',
                handle: 'hermes',
                role: 'member',
                displayName: 'Hermes',
                subjectType: GroupMemberSubjectType.agent,
              ),
            ], query: '');

        final human = candidates.singleWhere(
          (candidate) => candidate.id == 'member:did:wba:awiki.info:u:alice',
        );
        final agent = candidates.singleWhere(
          (candidate) => candidate.id == 'member:did:agent:hermes',
        );
        expect(human.enabled, isTrue);
        expect(human.badge, '用户');
        expect(human.target.kind, ChatMentionTargetKind.human);
        expect(agent.enabled, isTrue);
        expect(agent.badge, '智能体');
        expect(agent.target.kind, ChatMentionTargetKind.agent);
      },
    );

    test(
      'filters by displayName, handle, and DID without using displayName as identity',
      () {
        final candidates =
            ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
              GroupMemberSummary(
                userId: 'did:wba:awiki.info:u:hermes',
                did: 'did:wba:awiki.info:u:hermes',
                handle: 'hermes1',
                role: 'member',
                displayName: 'Hermes One',
                subjectType: GroupMemberSubjectType.agent,
              ),
            ], query: 'Hermes');

        final member = candidates.singleWhere(
          (candidate) => candidate.id.startsWith('member:'),
        );
        expect(member.surface, '@Hermes One');
        expect(member.enabled, isTrue);
        expect(member.target.did, 'did:wba:awiki.info:u:hermes');
        expect(member.target.displayName, 'Hermes One');
        expect(member.target.kind, ChatMentionTargetKind.agent);
      },
    );

    test('keeps unknown subjectType visible but not selectable', () {
      final candidates =
          ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'did:wba:awiki.info:u:unknown',
              did: 'did:wba:awiki.info:u:unknown',
              handle: 'unknown',
              role: 'member',
            ),
          ], query: 'unknown');

      final member = candidates.singleWhere(
        (candidate) => candidate.id.startsWith('member:'),
      );
      expect(member.enabled, isFalse);
      expect(member.disabledReason, contains('类型未知'));
      expect(member.target.isP9Sendable, isFalse);
    });
  });

  group('mention draft range', () {
    test(
      'computes P9 unicode code point offsets for Chinese and emoji text',
      () {
        const text = 'Hi 😊 @所有 Agents\n请总结';
        final start = text.indexOf('@');
        final mention = ChatMentionDraft(
          localId: 'men_1',
          surface: '@所有 Agents',
          start: start,
          end: start + '@所有 Agents'.length,
          target: const ChatMentionTargetDraft.groupSelector(
            ChatMentionSelector.agents,
          ),
        );

        final range = mention.toWireRange(text);

        expect(range.toJson(), <String, Object?>{
          'start': 5,
          'end': 15,
          'unit': 'unicode_code_point',
        });
      },
    );

    test(
      'shifts preceding edits and invalidates edits inside mention surface',
      () {
        const original = 'hi @所有人';
        const mention = ChatMentionDraft(
          localId: 'men_1',
          surface: '@所有人',
          start: 3,
          end: 7,
          target: ChatMentionTargetDraft.groupSelector(ChatMentionSelector.all),
        );

        final shifted = ChatMentionDraft.transformMentions(
          oldText: original,
          newText: '你好 hi @所有人',
          oldMentions: <ChatMentionDraft>[mention],
        );
        expect(shifted, hasLength(1));
        expect(shifted.single.start, 6);
        expect(shifted.single.toWireRange('你好 hi @所有人').start, 6);

        final invalidated = ChatMentionDraft.transformMentions(
          oldText: original,
          newText: 'hi @所有',
          oldMentions: <ChatMentionDraft>[mention],
        );
        expect(invalidated, isEmpty);
      },
    );
  });
}
