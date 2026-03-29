import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../app_shell/app_controller.dart';
import '../chat/chat_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';

class PeerProfilePage extends StatefulWidget {
  const PeerProfilePage({
    super.key,
    required this.controller,
    required this.did,
  });

  final AppController controller;
  final String did;

  @override
  State<PeerProfilePage> createState() => _PeerProfilePageState();
}

class _PeerProfilePageState extends State<PeerProfilePage> {
  UserProfile? _profile;
  bool _loading = true;
  bool _actionBusy = false;
  String _relationship = 'none';

  static final RegExp _didUserPattern = RegExp(r':(?:user:)?([^:]+):k1_');
  static final RegExp _didTailPattern = RegExp(r':([^:]+)$');

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await widget.controller.loadPeerProfile(widget.did);
    final relationship = await widget.controller.checkRelationship(widget.did);
    UserProfile? resolved = profile;
    if (profile != null) {
      final homepageMarkdown = await _fetchHomepageMarkdown(_homepageUrl(profile));
      if (homepageMarkdown != null && homepageMarkdown.trim().isNotEmpty) {
        resolved = profile.copyWith(profileMarkdown: homepageMarkdown);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = resolved;
      _relationship = relationship?.relationship ?? 'none';
      _loading = false;
    });
  }

  Future<String?> _fetchHomepageMarkdown(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      final body = response.body.trim();
      if (body.isEmpty) {
        return null;
      }
      return body;
    } catch (_) {
      return null;
    }
  }

  String _calcThreadId(String myDid, String peerDid) {
    final list = <String>[myDid, peerDid]..sort();
    return 'dm:${list[0]}:${list[1]}';
  }

  String _compactUserName(UserProfile profile) {
    if (profile.nickName.trim().isNotEmpty) {
      return profile.nickName.trim();
    }
    final did = profile.did;
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

  String _homepageUrl(UserProfile profile) {
    final handle = profile.handle?.trim();
    if (handle != null && handle.isNotEmpty) {
      return 'https://$handle.awiki.ai';
    }
    return 'https://${_compactUserName(profile)}.awiki.ai';
  }

  Future<void> _sendMessage(BuildContext context) async {
    final profile = _profile;
    final myDid = widget.controller.profile?.did;
    if (profile == null || myDid == null) {
      return;
    }

    final threadId = _calcThreadId(myDid, profile.did);
    ConversationSummary? targetConv;
    for (final conv in widget.controller.conversations) {
      if (conv.threadId == threadId) {
        targetConv = conv;
        break;
      }
    }

    targetConv ??= ConversationSummary(
      threadId: threadId,
      displayName: _compactUserName(profile),
      lastMessagePreview: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      isGroup: false,
      targetDid: profile.did,
    );

    await _runAction(() async {
      await widget.controller.openConversation(targetConv!);
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ChatPage(
            controller: widget.controller,
            conversation: targetConv!,
          ),
        ),
      );
    });
  }

  Future<void> _unfollow() async {
    await _runAction(() async {
      await widget.controller.unfollowUser(widget.did);
      if (!mounted) {
        return;
      }
      setState(() {
        _relationship = 'none';
      });
      AwikiMeToast.show(context, '已取消关注');
    });
  }

  Future<void> _deleteLocalThread() async {
    final myDid = widget.controller.profile?.did;
    final peerDid = _profile?.did;
    if (myDid == null || peerDid == null) {
      return;
    }
    final threadId = _calcThreadId(myDid, peerDid);
    await _runAction(() async {
      await widget.controller.deleteThread(threadId);
      if (!mounted) {
        return;
      }
      AwikiMeToast.show(context, '本地聊天记录已删除');
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  String _profileContent(UserProfile profile) {
    final markdown = profile.profileMarkdown.trim();
    if (markdown.isNotEmpty) {
      return markdown;
    }
    return profile.bio.trim();
  }

  @override
  Widget build(BuildContext context) {
    final profileContent = _profile == null ? '' : _profileContent(_profile!);
    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: AwikiMeColors.background,
          child: SafeArea(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : _profile == null
                    ? const Center(
                        child: Text(
                          '无法加载该用户的信息',
                          style: TextStyle(color: AwikiMeColors.danger),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: <Widget>[
                          AwikiMeTopBar(
                            title: '个人资料',
                            padding: EdgeInsets.zero,
                            leading: GestureDetector(
                              onTap: _actionBusy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Icon(
                                Icons.arrow_back,
                                color: AwikiMeColors.primaryDark,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration:
                                AwikiMeDecorations.card(color: AwikiMeColors.surface),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    AvatarBadge(
                                      seed: _compactUserName(_profile!),
                                      size: 72,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            _compactUserName(_profile!),
                                            style: const TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: AwikiMeColors.title,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _profile!.did,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AwikiMeTextStyles.cardSubtitle,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    _Pill(label: _relationship),
                                    if (_profile!.handle?.isNotEmpty == true)
                                      _Pill(label: '@${_profile!.handle}'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: () async {
                                    final url = Uri.parse(_homepageUrl(_profile!));
                                    try {
                                      final launched = await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      if (!launched) {
                                        AwikiMeToast.show(context, '无法打开链接');
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        AwikiMeToast.show(context, '无法打开链接: $error');
                                      }
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AwikiMeColors.subtleSurface,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        const Icon(
                                          Icons.link,
                                          color: AwikiMeColors.primaryDark,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _homepageUrl(_profile!),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: AwikiMeColors.primaryDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration:
                                AwikiMeDecorations.card(color: AwikiMeColors.surface),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (profileContent.isEmpty)
                                  const Text(
                                    '暂无 profile',
                                    style: AwikiMeTextStyles.cardSubtitle,
                                  )
                                else
                                  MarkdownBody(data: profileContent),
                                if (_profile!.tags.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _profile!.tags
                                        .map((tag) => _Pill(label: tag))
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _actionBusy ? null : () => _sendMessage(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: AwikiMeColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '发消息',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AwikiMeColors.surface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (_relationship == 'following' ||
                              _relationship == 'friend') ...<Widget>[
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: _actionBusy ? null : _unfollow,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4D6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '取消关注',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AwikiMeColors.primaryDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _actionBusy ? null : _deleteLocalThread,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '删除本地聊天记录',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AwikiMeColors.danger,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        if (_actionBusy || widget.controller.isBusy)
          const AwikiMeLoadingMask(label: '请稍候...'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AwikiMeColors.primaryDark,
        ),
      ),
    );
  }
}
