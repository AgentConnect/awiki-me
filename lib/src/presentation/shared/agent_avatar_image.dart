import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import '../../data/avatar/avatar_image_cache.dart';
import 'dart:async';
import '../../app/app_services.dart';
import '../../domain/services/realtime_gateway.dart';
import 'avatar_badge.dart';

final agentAvatarBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, uri) async {
      final cache = ref.watch(avatarImageCacheProvider);
      return cache is AvatarByteCache
          ? (cache as AvatarByteCache).loadBytes(uri)
          : null;
    });

/// All individual and mosaic agent images share one fallback/motion policy.
class AgentAvatarImage extends ConsumerStatefulWidget {
  const AgentAvatarImage({
    super.key,
    required this.uri,
    required this.posterUri,
    required this.size,
    required this.fallback,
    this.staticOnly = false,
    this.refreshOnOpen = false,
  });
  final String? uri;
  final String? posterUri;
  final double size;
  final Widget fallback;
  final bool staticOnly;
  final bool refreshOnOpen;

  @override
  ConsumerState<AgentAvatarImage> createState() => _AgentAvatarImageState();
}

class _AgentAvatarImageState extends ConsumerState<AgentAvatarImage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;
  bool _inViewport = true;
  ScrollPosition? _scroll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.refreshOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.removeListener(_scheduleVisibility);
      _scroll = scroll;
      _scroll?.addListener(_scheduleVisibility);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
    _timer?.cancel();
    if (_visible) {
      _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
    }
  }

  void _scheduleVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
  }

  void _updateVisibility() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final visible = rect.overlaps(Offset.zero & MediaQuery.sizeOf(context));
    if (_inViewport != visible) setState(() => _inViewport = visible);
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
  }

  Future<void> _refresh() async {
    if (!_foreground || !_visible || !_inViewport || !mounted) return;
    for (final uri in {
      widget.posterUri,
      if (!widget.staticOnly && !MediaQuery.disableAnimationsOf(context))
        widget.uri,
    }) {
      if (safeAvatarUri(uri) != null) {
        final cache = ref.read(avatarImageCacheProvider);
        if (cache is AvatarByteCache) {
          await (cache as AvatarByteCache).loadBytes(uri!, force: true);
        }
        if (!mounted || !identical(cache, ref.read(avatarImageCacheProvider))) {
          return;
        }
        ref.invalidate(agentAvatarBytesProvider(uri!));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll?.removeListener(_scheduleVisibility);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeConnectionStatusProvider, (previous, next) {
      if (next.valueOrNull == RealtimeConnectionStatus.connected &&
          previous?.valueOrNull != next.valueOrNull) {
        _refresh();
      }
    });
    final uri = widget.uri, posterUri = widget.posterUri;
    final size = widget.size;
    final fallback = widget.fallback;
    final still =
        widget.staticOnly ||
        !_foreground ||
        !_inViewport ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    Widget image(String? value, Widget onError) {
      final safe = safeAvatarUri(value);
      if (safe == null) return onError;
      final result = ref.watch(agentAvatarBytesProvider(safe.toString()));
      final bytes = result.isReloading ? null : result.valueOrNull;
      if (bytes == null) return onError;
      final edge = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
        1,
        512,
      );
      return Image(
        image: ResizeImage(
          MemoryImage(bytes),
          width: edge,
          height: edge,
          policy: ResizeImagePolicy.fit,
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => onError,
      );
    }

    final poster = image(posterUri, fallback);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: still || uri == null || uri == posterUri
            ? poster
            : image(uri, poster),
      ),
    );
  }
}
