import 'dart:async';
import 'dart:math';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/account_state_sync_request_bus.dart';
import '../../application/models/product_local_models.dart';
import '../../application/ports/agent_avatar_port.dart';
import '../../data/avatar/avatar_image_processor.dart';
import '../../data/avatar/agent_avatar_upload.dart';
import '../../data/services/awiki_onboarding_utility_client.dart';
import '../../domain/entities/agent/agent_avatar.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/avatar_crop_editor.dart';
import '../profile/peer_display_profile_provider.dart';
import '../shared/agent_avatar_image.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import 'agents_provider.dart';

Future<void> showAgentAvatarEditor(BuildContext context, AgentSummary agent) =>
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AgentAvatarEditor(agent: agent),
    );

final agentAvatarPortProvider = Provider<AgentAvatarPort?>((ref) {
  final port = ref.watch(agentInventoryPortProvider);
  return port is AgentAvatarPort ? port as AgentAvatarPort : null;
});

class AgentAvatarEditor extends ConsumerStatefulWidget {
  const AgentAvatarEditor({super.key, required this.agent});
  final AgentSummary agent;
  @override
  ConsumerState<AgentAvatarEditor> createState() => _AgentAvatarEditorState();
}

class _AgentAvatarEditorState extends ConsumerState<AgentAvatarEditor> {
  final _crop = CropController();
  final _responsibility = TextEditingController();
  final _description = TextEditingController();
  AgentAvatarCapabilities? _capabilities;
  SessionEpoch? _epoch;
  Timer? _poll;
  String? _preset;
  String? _action;
  String? _requestId;
  Uint8List? _image;
  Uint8List? _preview;
  Uint8List? _uploadCover;
  String? _error;
  bool _busy = true;
  bool _cropReady = false;
  bool get _current =>
      mounted && ref.read(sessionProvider).activeEpoch == _epoch;

  @override
  void initState() {
    super.initState();
    _epoch = ref.read(sessionProvider).activeEpoch;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _responsibility.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final port = ref.read(agentAvatarPortProvider);
      if (port == null) throw StateError('agent_avatar.unsupported');
      final value = await port.loadAgentAvatar(widget.agent.agentDid);
      if (!_current) return;
      ref
          .read(agentsProvider.notifier)
          .applyAvatarProjection(widget.agent.agentDid, value.avatar);
      setState(() {
        _capabilities = value;
        _error = null;
        _busy = false;
      });
      _poll?.cancel();
      if (value.avatar.isGenerating) {
        _poll = Timer(const Duration(seconds: 2), _load);
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _error = context.l10n.avatarLoadFailed;
          _busy = false;
        });
      }
    }
  }

  void _draft(String action, {String? preset, Uint8List? image}) {
    _poll?.cancel();
    setState(() {
      _action = action;
      _preset = preset;
      _image = image;
      _preview = null;
      _uploadCover = null;
      _requestId = null;
      _error = null;
    });
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['gif', 'png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/gif', 'image/png', 'image/jpeg', 'image/webp'],
          ),
        ],
      );
      if (!_current || file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('agent_avatar.size');
      }
      final bytes = await file.readAsBytes();
      if (!_current) return;
      if (bytes.length >= 6 &&
          String.fromCharCodes(bytes.take(6)).startsWith('GIF8')) {
        final cover = await agentAnimationCover(bytes);
        if (!_current) return;
        _draft(
          'upload',
          image: bytes,
        ); // Animation bytes never enter the crop/PNG path.
        setState(() => _uploadCover = cover);
      } else {
        final preview = await prepareAvatarPreview(bytes);
        if (_current) {
          setState(() {
            _preview = preview;
            _cropReady = false;
            _error = null;
          });
        }
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = context.l10n.agentAvatarImageRejected);
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _cropped(CropResult result) async {
    if (result is! CropSuccess) {
      if (_current) {
        setState(() {
          _busy = false;
          _error = context.l10n.agentAvatarImageRejected;
        });
      }
      return;
    }
    try {
      final image = await compute(encodeAvatarJpeg, result.croppedImage);
      if (_current) {
        _draft('upload', image: image);
        setState(() => _busy = false);
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _busy = false;
          _error = context.l10n.avatarImageRejected;
        });
      }
    }
  }

  String _newRequestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _save() async {
    final port = ref.read(agentAvatarPortProvider);
    final avatar = _capabilities?.avatar;
    if (port == null || avatar == null || _action == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _poll?.cancel();
    _requestId ??= _newRequestId();
    try {
      final result = await port.setAgentAvatar(
        agentDid: widget.agent.agentDid,
        requestId: _requestId!,
        expectedVersion: avatar.version,
        action: _action!,
        presetId: _preset,
        image: _image,
        name: _action == 'generate' ? widget.agent.displayName : null,
        responsibility: _action == 'generate'
            ? _responsibility.text.trim()
            : null,
        imageDescription: _action == 'generate'
            ? _description.text.trim()
            : null,
      );
      if (!_current) return;
      ref
          .read(agentsProvider.notifier)
          .applyAvatarProjection(widget.agent.agentDid, result.avatar);
      ref
          .read(accountStateSyncRequestBusProvider)
          .request(
            'agent_avatar_updated',
            force: true,
            minimumVersion: AccountStateVersionFloor(
              domain: ProductAccountDomain.agentInventory,
              version: result.inventoryVersion,
            ),
          );
      await ref
          .read(agentsProvider.notifier)
          .load(showLoading: false, surfaceError: false);
      if (!_current) return;
      final session = ref.read(sessionProvider);
      if (session.session != null) {
        unawaited(
          ref
              .read(peerDisplayProfileProvider.notifier)
              .refreshDisplayProfiles(
                ownerDid: session.session!.did,
                dids: [widget.agent.agentDid],
                force: true,
                expectedEpoch: _epoch,
              ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (_current) {
        if (error is AwikiOnboardingUtilityError &&
            error.message.contains('agent_avatar.version_conflict')) {
          try {
            final fresh = await port.loadAgentAvatar(widget.agent.agentDid);
            if (!_current) return;
            _capabilities = fresh;
            _requestId = null;
          } catch (_) {
            // Preserve the draft when refreshing the authoritative version fails.
          }
        }
        if (_current) {
          setState(() {
            _busy = false;
            _error = context.l10n.avatarSaveFailed;
          });
        }
      }
      // Retry uses the same UUID/version and payload until the draft changes.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((state) => state.activeEpoch), (_, next) {
      if (next != _epoch && mounted) Navigator.of(context).pop();
    });
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final width = (MediaQuery.sizeOf(context).width - 40).clamp(240.0, 560.0);
    final height = (MediaQuery.sizeOf(context).height - 80).clamp(160.0, 640.0);
    final avatar = _capabilities?.avatar;
    Widget preview = AvatarBadge(
      seed: widget.agent.displayName,
      userId: widget.agent.agentDid,
      size: 96,
      isAgent: true,
      staticOnly: avatar?.isGenerating == true,
      avatarUri: avatar?.animatedUri,
      avatarThumbnailUri: avatar?.posterUri,
    );
    final previewPreset = _action == 'reset' && avatar != null
        ? AgentAvatar.defaultPreset(avatar.agentId)
        : _preset;
    if (previewPreset != null) {
      preview = AgentAvatarImage(
        uri: '/avatars/presets/$previewPreset.gif',
        posterUri: '/avatars/presets/$previewPreset.png',
        size: 96,
        fallback: const Icon(CupertinoIcons.person),
      );
    }
    if (_image != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.memory(
          MediaQuery.disableAnimationsOf(context)
              ? _uploadCover ?? _image!
              : _image!,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          cacheWidth: 256,
          errorBuilder: (_, __, ___) =>
              const Icon(CupertinoIcons.person_crop_square),
        ),
      );
    }
    return Center(
      child: CupertinoPopupSurface(
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.profileAvatarChange)),
                    CupertinoButton(
                      key: const Key('agent-avatar-cancel'),
                      padding: const EdgeInsets.all(8),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: CupertinoColors.systemRed),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_preview != null)
                          AvatarCropEditor(
                            isAgent: true,
                            bytes: _preview!,
                            controller: _crop,
                            onCropped: _cropped,
                            onReady: (value) {
                              if (mounted) setState(() => _cropReady = value);
                            },
                            currentAvatar: preview,
                            enabled: !_busy,
                          )
                        else ...[
                          preview,
                          const SizedBox(height: 12),
                          if (avatar?.isGenerating == true)
                            Text(l10n.agentAvatarGenerating),
                          if (avatar?.status == 'failed')
                            Text(switch (avatar?.errorCode) {
                              'agent_avatar.generation_timeout' =>
                                l10n.agentAvatarGenerationTimeout,
                              'agent_avatar.generation_interrupted' =>
                                l10n.agentAvatarGenerationInterrupted,
                              'agent_avatar.generated_image_invalid' =>
                                l10n.agentAvatarGeneratedImageInvalid,
                              _ => l10n.agentAvatarGenerationFailed,
                            }),
                          if (_capabilities != null)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final id in agentAvatarPresetIds)
                                  CupertinoButton(
                                    key: ValueKey('agent-avatar-preset-$id'),
                                    padding: const EdgeInsets.all(4),
                                    onPressed: _busy
                                        ? null
                                        : () => _draft('preset', preset: id),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _preset == id
                                              ? theme.primaryDark
                                              : theme.border,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: AgentAvatarImage(
                                        uri: null,
                                        posterUri: '/avatars/presets/$id.png',
                                        size: 56,
                                        staticOnly: true,
                                        fallback: const Icon(
                                          CupertinoIcons.person,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          if (_capabilities?.uploadEnabled == true)
                            CupertinoButton(
                              key: const Key('agent-avatar-upload'),
                              onPressed: _busy ? null : _pick,
                              child: Text(l10n.avatarChoose),
                            ),
                          if (_capabilities != null)
                            CupertinoButton(
                              key: const Key('agent-avatar-reset'),
                              onPressed: _busy ? null : () => _draft('reset'),
                              child: Text(l10n.avatarReset),
                            ),
                          if (_capabilities?.generationEnabled == true) ...[
                            Text(l10n.agentAvatarGenerationPrivacy),
                            CupertinoTextField(
                              controller: _responsibility,
                              onChanged: (_) => _requestId = null,
                              enabled: !_busy,
                              maxLength: 512,
                              placeholder: l10n.agentAvatarResponsibility,
                            ),
                            const SizedBox(height: 8),
                            CupertinoTextField(
                              controller: _description,
                              onChanged: (_) => _requestId = null,
                              enabled: !_busy,
                              maxLength: 512,
                              placeholder: l10n.agentAvatarDescription,
                            ),
                            CupertinoButton(
                              key: const Key('agent-avatar-generate'),
                              onPressed: _busy
                                  ? null
                                  : () => _draft('generate'),
                              child: Text(l10n.agentAvatarRegenerate),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                if (_busy) const CupertinoActivityIndicator(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_error != null && _capabilities == null)
                      CupertinoButton(
                        key: const Key('agent-avatar-retry-load'),
                        onPressed: _busy ? null : _load,
                        child: Text(l10n.commonRetry),
                      ),
                    CupertinoButton(
                      key: const Key('agent-avatar-save'),
                      onPressed: _busy
                          ? null
                          : _preview != null
                          ? (_cropReady
                                ? () {
                                    setState(() => _busy = true);
                                    _crop.crop();
                                  }
                                : null)
                          : _action == null
                          ? null
                          : _save,
                      child: Text(
                        _preview != null ? l10n.commonNext : l10n.commonSave,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
