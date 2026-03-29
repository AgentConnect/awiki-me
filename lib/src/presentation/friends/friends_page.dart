import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../../domain/entities/conversation_summary.dart';
import '../app_shell/app_controller.dart';
import '../chat/chat_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({
    super.key,
    required this.controller,
    required this.onOpenGroups,
    required this.onOpenSettings,
    required this.onOpenQuickActions,
  });

  final AppController controller;
  final VoidCallback onOpenGroups;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenQuickActions;

  static final RegExp _didUserPattern = RegExp(r':(?:user:)?([^:]+):k1_');
  static final RegExp _didTailPattern = RegExp(r':([^:]+)$');

  String _calcThreadId(String myDid, String peerDid) {
    final list = [myDid, peerDid]..sort();
    return 'dm:${list[0]}:${list[1]}';
  }

  String _compactUserName(String displayName, String did) {
    if (displayName.isNotEmpty && !displayName.startsWith('did:')) {
      return displayName;
    }
    final didMatch = _didUserPattern.firstMatch(did);
    if (didMatch != null) {
      return didMatch.group(1)!;
    }
    final tailMatch = _didTailPattern.firstMatch(did);
    if (tailMatch != null) {
      return tailMatch.group(1)!;
    }
    return did;
  }

  Future<void> _sendMessage(
    BuildContext context,
    String peerDid,
    String peerName,
  ) async {
    final myDid = controller.profile?.did;
    if (myDid == null) return;

    final threadId = _calcThreadId(myDid, peerDid);
    ConversationSummary? targetConv;
    for (final conv in controller.conversations) {
      if (conv.threadId == threadId) {
        targetConv = conv;
        break;
      }
    }

    targetConv ??= ConversationSummary(
      threadId: threadId,
      displayName: peerName.isNotEmpty ? peerName : peerDid,
      lastMessagePreview: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      isGroup: false,
      targetDid: peerDid,
    );

    await controller.openConversation(targetConv);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ChatPage(
          controller: controller,
          conversation: targetConv!,
        ),
      ),
    );
  }

  List<_FriendListItem> _items() {
    final items = <_FriendListItem>[
      const _FriendListItem.group(),
    ];

    for (final item in controller.following) {
      items.add(
        _FriendListItem.contact(
          title: _compactUserName(item.displayName, item.did),
          did: item.did,
          seed: _compactUserName(item.displayName, item.did),
        ),
      );
    }

    if (items.length == 1) {
      for (final item in controller.followers) {
        items.add(
          _FriendListItem.contact(
            title: _compactUserName(item.displayName, item.did),
            did: item.did,
            seed: _compactUserName(item.displayName, item.did),
          ),
        );
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Stack(
      children: <Widget>[
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return AwikiMeTopBar(
                title: '朋友',
                leading: GestureDetector(
                  onTap: onOpenSettings,
                  child: const Icon(
                    Icons.settings_outlined,
                    size: 24,
                    color: AwikiMeColors.title,
                  ),
                ),
                trailing: GestureDetector(
                  onTap: onOpenQuickActions,
                  child: const Icon(
                    Icons.add,
                    size: 26,
                    color: AwikiMeColors.title,
                  ),
                ),
              );
            }

            final item = items[index - 1];
            if (item.isGroup) {
              return _FriendRow.group(onTap: onOpenGroups);
            }
            return _FriendRow.contact(
              seed: item.seed!,
              title: item.title!,
              onTap: () => _sendMessage(context, item.did!, item.title!),
            );
          },
        ),
        const Positioned(
          right: 10,
          top: 220,
          bottom: 130,
          child: _IndexRail(),
        ),
      ],
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow.contact({
    required this.seed,
    required this.title,
    required this.onTap,
  }) : isGroup = false;

  const _FriendRow.group({required this.onTap})
      : isGroup = true,
        seed = 'group',
        title = 'group';

  final bool isGroup;
  final String seed;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEAE7F2)),
          ),
        ),
        child: Row(
          children: <Widget>[
            isGroup
                ? Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCE9FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.group,
                      color: Color(0xFF2F6BFF),
                      size: 20,
                    ),
                  )
                : AvatarBadge(seed: seed, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AwikiMeColors.title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexRail extends StatelessWidget {
  const _IndexRail();

  @override
  Widget build(BuildContext context) {
    const letters = <String>[
      'A',
      'B',
      'C',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'M',
      'S',
      '#',
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters
          .map(
            (letter) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: letter == 'E' ? FontWeight.w700 : FontWeight.w500,
                  color: letter == 'E'
                      ? AwikiMeColors.primaryDark
                      : const Color(0xFFC4A981),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FriendListItem {
  const _FriendListItem.contact({
    required this.title,
    required this.did,
    required this.seed,
  }) : isGroup = false;

  const _FriendListItem.group()
      : isGroup = true,
        title = null,
        did = null,
        seed = null;

  final bool isGroup;
  final String? title;
  final String? did;
  final String? seed;
}
