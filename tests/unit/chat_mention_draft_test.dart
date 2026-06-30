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
        expect(
          candidates
              .where((candidate) => candidate.id.startsWith('selector:'))
              .map((candidate) => candidate.surface),
          isEmpty,
        );
        expect(human.enabled, isTrue);
        expect(human.subjectType, GroupMemberSubjectType.human);
        expect(human.target.kind, ChatMentionTargetKind.human);
        expect(agent.enabled, isTrue);
        expect(agent.subjectType, GroupMemberSubjectType.agent);
        expect(agent.target.kind, ChatMentionTargetKind.agent);
      },
    );

    test(
      'filters by displayName, handle, and DID while inserting agent handle',
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
        expect(member.surface, '@hermes1');
        expect(member.title, 'hermes1');
        expect(member.enabled, isTrue);
        expect(member.target.did, 'did:wba:awiki.info:u:hermes');
        expect(member.target.handle, 'hermes1');
        expect(member.target.displayName, 'Hermes One');
        expect(member.target.kind, ChatMentionTargetKind.agent);
      },
    );

    test('empty query only exposes mentionable group members', () {
      final candidates =
          ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'did:wba:awiki.info:u:zhuocheng',
              did: 'did:wba:awiki.info:u:zhuocheng',
              handle: 'zhuocheng',
              role: 'member',
              displayName: 'Zhuocheng',
              subjectType: GroupMemberSubjectType.human,
            ),
          ]);

      expect(candidates.map((candidate) => candidate.surface), ['@Zhuocheng']);
      expect(candidates.map((candidate) => candidate.subjectType), [
        GroupMemberSubjectType.human,
      ]);
      expect(
        candidates.where((candidate) => candidate.id.startsWith('selector:')),
        isEmpty,
      );
    });

    test('filters current user by DID and handle', () {
      final candidates = ChatMentionCandidate.forGroupMembers(
        const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:user:me:e1_current',
            did: 'did:wba:awiki.info:user:me:e1_current',
            handle: 'unexpected',
            role: 'member',
            displayName: 'Me By DID',
            subjectType: GroupMemberSubjectType.human,
          ),
          GroupMemberSummary(
            userId: 'member-me-handle',
            did: 'did:wba:awiki.info:user:other:e1_other',
            handle: 'me.awiki.info',
            role: 'member',
            displayName: 'Me By Handle',
            subjectType: GroupMemberSubjectType.human,
          ),
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:user:alice:e1_alice',
            did: 'did:wba:awiki.info:user:alice:e1_alice',
            handle: 'alice',
            role: 'member',
            displayName: 'Alice',
            subjectType: GroupMemberSubjectType.human,
          ),
        ],
        currentUserDid: 'did:wba:awiki.info:user:me:e1_current',
        currentUserHandle: 'ME.awiki.info',
      );

      expect(candidates.map((candidate) => candidate.surface), ['@Alice']);
    });

    test(
      'human WBA DID remains human even when handle contains no type data',
      () {
        final candidates =
            ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
              GroupMemberSummary(
                userId: 'did:wba:awiki.info:user:zhuocheng:e1',
                did: 'did:wba:awiki.info:user:zhuocheng:e1',
                handle: 'zhuocheng',
                role: 'member',
                displayName: 'zhuocheng',
              ),
            ], query: 'zhuocheng');

        final member = candidates.singleWhere(
          (candidate) => candidate.id.startsWith('member:'),
        );
        expect(member.enabled, isTrue);
        expect(member.subjectType, GroupMemberSubjectType.human);
        expect(member.target.kind, ChatMentionTargetKind.human);
        expect(member.surface, '@zhuocheng');
      },
    );

    test('agent mention ignores DID-like display name when handle exists', () {
      final candidates =
          ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'did:agent:runtime-hermes',
              did: 'did:agent:runtime-hermes',
              handle: '@hermes',
              role: 'member',
              displayName: 'did:agent:runtime-hermes',
              subjectType: GroupMemberSubjectType.agent,
            ),
          ]);

      final member = candidates.singleWhere(
        (candidate) => candidate.id == 'member:did:agent:runtime-hermes',
      );
      expect(member.surface, '@hermes');
      expect(member.title, 'hermes');
      expect(member.subtitle, '@hermes · did:agent:…hermes');
      final insertion = const ChatMentionTrigger(
        start: 0,
        end: 4,
        query: 'her',
      ).insert(member).applyTo('@her');
      expect(insertion.text, '@hermes ');
      expect(insertion.mention.surface, '@hermes');
      expect(insertion.mention.target.did, 'did:agent:runtime-hermes');
    });

    test('agent mention displays short handle for full handle values', () {
      final candidates =
          ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'did:wba:awiki.info:agent:runtime:hermes:e1_member',
              did: 'did:wba:awiki.info:agent:runtime:hermes:e1_member',
              handle: 'hermes.awiki.info',
              role: 'member',
              displayName: 'Hermes Agent',
              subjectType: GroupMemberSubjectType.agent,
            ),
          ], query: 'hermes.awiki');

      final member = candidates.singleWhere(
        (candidate) => candidate.id.startsWith('member:'),
      );
      expect(member.surface, '@hermes');
      expect(member.title, 'hermes');
      expect(member.subtitle, '@hermes · did:wba:aw…member');
      const original = '@hermes.awiki';
      final insertion = const ChatMentionTrigger(
        start: 0,
        end: original.length,
        query: 'hermes.awiki',
      ).insert(member).applyTo(original);
      expect(insertion.text, '@hermes ');
      expect(insertion.mention.surface, '@hermes');
      expect(
        insertion.mention.target.did,
        'did:wba:awiki.info:agent:runtime:hermes:e1_member',
      );
    });

    test('keeps unknown subjectType visible but not selectable', () {
      final candidates =
          ChatMentionCandidate.forGroupMembers(const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'local-member-without-did',
              did: 'local-member-without-did',
              handle: 'unknown',
              role: 'member',
            ),
          ], query: 'unknown');

      final member = candidates.singleWhere(
        (candidate) => candidate.id.startsWith('member:'),
      );
      expect(member.enabled, isFalse);
      expect(
        member.disabledReasonCode,
        ChatMentionDisabledReasonCode.unknownMemberType,
      );
      expect(member.target.isP9Sendable, isFalse);
    });
  });

  group('mention draft range', () {
    test(
      'computes P9 unicode code point offsets for Chinese and emoji text',
      () {
        const text = 'Hi 😊 @小智\n请总结';
        final start = text.indexOf('@');
        final mention = ChatMentionDraft(
          localId: 'men_1',
          surface: '@小智',
          start: start,
          end: start + '@小智'.length,
          target: const ChatMentionTargetDraft.member(
            kind: ChatMentionTargetKind.agent,
            did: 'did:wba:awiki.info:agent:runtime:xiaozhi:e1_agent',
            handle: 'xiaozhi',
          ),
        );

        final range = mention.toWireRange(text);

        expect(range.toJson(), <String, Object?>{
          'start': 5,
          'end': 8,
          'unit': 'unicode_code_point',
        });
      },
    );

    test(
      'shifts preceding edits and invalidates edits inside mention surface',
      () {
        const original = 'hi @小明';
        const mention = ChatMentionDraft(
          localId: 'men_1',
          surface: '@小明',
          start: 3,
          end: 6,
          target: ChatMentionTargetDraft.member(
            kind: ChatMentionTargetKind.human,
            did: 'did:wba:awiki.info:user:xiaoming',
            handle: 'xiaoming',
          ),
        );

        final shifted = ChatMentionDraft.transformMentions(
          oldText: original,
          newText: '你好 hi @小明',
          oldMentions: <ChatMentionDraft>[mention],
        );
        expect(shifted, hasLength(1));
        expect(shifted.single.start, 6);
        expect(shifted.single.toWireRange('你好 hi @小明').start, 6);

        final invalidated = ChatMentionDraft.transformMentions(
          oldText: original,
          newText: 'hi @小',
          oldMentions: <ChatMentionDraft>[mention],
        );
        expect(invalidated, isEmpty);
      },
    );
  });
}
