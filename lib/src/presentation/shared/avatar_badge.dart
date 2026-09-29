import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/avatar/avatar_image_cache.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import '../profile/profile_provider.dart';

import '../group/group_provider.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/l10n.dart';
import 'awiki_me_design.dart';
import 'default_avatar_generator.dart';

final avatarImageCacheProvider = Provider<AvatarImageCache>((ref) {
  final epoch = ref.watch(sessionProvider.select((state) => state.activeEpoch));
  final cache = AvatarImageCache(epoch?.ownerDid ?? '');
  ref.onDispose(cache.dispose);
  return cache;
});

typedef AvatarReferenceInput = ({String? did, String? uri, String? thumbnail});
typedef AvatarReference = ({String? uri, String? thumbnail});

/// An authoritative null must not fall back to an older widget snapshot.
final avatarReferenceProvider =
    Provider.family<AvatarReference, AvatarReferenceInput>((ref, input) {
      final own = ref.watch(
        profileProvider.select(
          (state) => input.did != null && state.profile?.did == input.did
              ? state.profile
              : null,
        ),
      );
      final peer = ref.watch(
        peerDisplayProfileProvider.select((state) => state.forDid(input.did)),
      );
      if (own != null) {
        return (uri: own.avatarUri, thumbnail: own.avatarThumbnailUri);
      }
      if (peer != null) {
        return (uri: peer.avatarUri, thumbnail: peer.avatarThumbnailUri);
      }
      return (uri: input.uri, thumbnail: input.thumbnail);
    });

class AvatarBadge extends ConsumerStatefulWidget {
  const AvatarBadge({
    super.key,
    required this.seed,
    this.size = 48,
    this.labelOverride,
    this.avatarUri,
    this.avatarThumbnailUri,
    this.userId,
    this.groupId,
  });
  final String seed;
  final double size;
  final String? labelOverride;
  final String? avatarUri;
  final String? avatarThumbnailUri;
  final String? userId;
  final String? groupId;
  @override
  ConsumerState<AvatarBadge> createState() => _AvatarBadgeState();
}

class _AvatarBadgeState extends ConsumerState<AvatarBadge> {
  ui.Image? _image;
  String? _key;
  int _generation = 0;
  AvatarImageCache? _cache;
  Timer? _refreshTimer;
  Timer? _imageTimer;
  String? _profileDemand;
  void _refreshProfiles(List<String> dids) {
    final session = ref.read(sessionProvider);
    if (!mounted ||
        session.session == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    unawaited(
      ref
          .read(peerDisplayProfileProvider.notifier)
          .refreshDisplayProfiles(
            ownerDid: session.session!.did,
            dids: dids,
            expectedEpoch: session.activeEpoch,
          ),
    );
  }

  void _loadImage(
    AvatarImageCache cache,
    String uri,
    int edge,
    int generation,
  ) {
    if (!mounted || generation != _generation) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _imageTimer = Timer(
        const Duration(seconds: 30),
        () => _loadImage(cache, uri, edge, generation),
      );
      return;
    }
    cache.load(uri, edge: edge).then((image) {
      if (!mounted || generation != _generation) {
        image?.dispose();
        return;
      }
      if (image != null) {
        setState(() {
          _image?.dispose();
          _image = image;
        });
      }
      _imageTimer?.cancel();
      _imageTimer = Timer(
        image == null
            ? const Duration(seconds: 30)
            : const Duration(minutes: 5),
        () {
          if (!mounted || generation != _generation) return;
          if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.paused) {
            _imageTimer = Timer(const Duration(seconds: 30), () {
              if (mounted && generation == _generation) {
                _loadImage(cache, uri, edge, generation);
              }
            });
            return;
          }
          _loadImage(cache, uri, edge, generation);
        },
      );
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _imageTimer?.cancel();
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(
      groupAvatarSummariesProvider.select((groups) => groups[widget.groupId]),
    );
    final members = group?.avatarMembers ?? const <GroupAvatarMember>[];
    final demand = members.isNotEmpty
        ? members.map((m) => m.did).toList()
        : widget.userId == null
        ? <String>[]
        : [widget.userId!];
    final demandKey =
        '${ref.watch(sessionProvider.select((s) => s.activeEpoch))?.hashCode}:${demand.join('|')}';
    if (_profileDemand != demandKey) {
      _profileDemand = demandKey;
      _refreshTimer?.cancel();
      if (demand.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshProfiles(demand);
        });
        _refreshTimer = Timer.periodic(
          const Duration(minutes: 5),
          (_) => _refreshProfiles(demand),
        );
      }
    }
    if ((group?.avatarUri ?? widget.avatarUri) == null &&
        members.isNotEmpty &&
        members.length <= 4) {
      _imageTimer?.cancel();
      if (_key != null) {
        _generation++;
        _key = null;
        _image?.dispose();
        _image = null;
      }
      return _GroupAvatarTiles(members: members, size: widget.size);
    }
    final reference = ref.watch(
      avatarReferenceProvider((
        did: widget.userId,
        uri: group?.avatarUri ?? widget.avatarUri,
        thumbnail: widget.avatarThumbnailUri,
      )),
    );
    final main = reference.uri;
    final thumbnail = reference.thumbnail;
    final raw = main == null
        ? null
        : widget.size <= 64
        ? thumbnail ?? main
        : main;
    final uri = safeAvatarUri(raw)?.toString();
    final cache = ref.watch(avatarImageCacheProvider);
    final key = '$uri@${widget.size <= 64 ? 128 : 512}';
    if (_key != key || _cache != cache) {
      _key = key;
      _cache = cache;
      final generation = ++_generation;
      _imageTimer?.cancel();
      _image?.dispose();
      _image = null;
      if (uri != null) {
        _imageTimer?.cancel();
        _loadImage(cache, uri, widget.size <= 64 ? 128 : 512, generation);
      }
    }
    if (_image == null) {
      return _FallbackAvatarBadge(
        seed: widget.seed,
        size: widget.size,
        labelOverride: widget.labelOverride,
        userId: widget.userId,
      );
    }
    return ClipOval(
      child: RawImage(
        image: _image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _FallbackAvatarBadge extends StatelessWidget {
  const _FallbackAvatarBadge({
    required this.seed,
    required this.size,
    this.labelOverride,
    this.userId,
  });

  final String seed;
  final double size;
  final String? labelOverride;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final generated = generateDefaultAvatar(name: seed, userId: userId);
    final label = labelOverride?.trim().isNotEmpty == true
        ? labelOverride!.trim()
        : generated.text;
    final labelLength = label.runes.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.avatarBackground,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: labelLength > 2
              ? size / 4
              : labelLength > 1
              ? size / 3.1
              : size / 2.4,
          color: theme.avatarForeground,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _GroupAvatarTiles extends StatelessWidget {
  const _GroupAvatarTiles({required this.members, required this.size});
  final List<GroupAvatarMember> members;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (members.length == 1) {
      return AvatarBadge(
        seed: members.first.handle ?? members.first.did,
        userId: members.first.did,
        size: size,
      );
    }
    Widget tile(GroupAvatarMember member) => AvatarBadge(
      key: ValueKey(member.memberKey),
      seed: member.handle ?? member.did,
      userId: member.did,
      size: (size - 6) / 2,
    );
    return Semantics(
      label: context.l10n.groupAvatarLabel,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: context.awikiTheme.avatarBackground,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tile(members[0]),
                if (members.length != 3) ...[
                  const SizedBox(width: 2),
                  tile(members[1]),
                ],
              ],
            ),
            if (members.length > 2) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  tile(members[members.length == 3 ? 1 : 2]),
                  const SizedBox(width: 2),
                  tile(members.last),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
