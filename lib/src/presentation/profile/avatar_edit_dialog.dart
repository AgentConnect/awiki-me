import 'dart:math';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/avatar/avatar_image_processor.dart';
import '../../data/avatar/avatar_picker_recovery.dart';
import '../../data/avatar/avatar_picker_files.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import 'profile_provider.dart';
import 'avatar_crop_editor.dart';

Future<void> showAvatarEditor(BuildContext context) =>
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AvatarEditDialog(),
    );

class AvatarEditDialog extends ConsumerStatefulWidget {
  const AvatarEditDialog({super.key});
  @override
  ConsumerState<AvatarEditDialog> createState() => _AvatarEditDialogState();
}

class _AvatarEditDialogState extends ConsumerState<AvatarEditDialog> {
  final _crop = CropController();
  SessionEpoch? _epoch;
  Uint8List? _preview;
  Uint8List? _pendingJpeg;
  String? _requestId;
  String? _expectedVersion;
  String? _error;
  bool _busy = true;
  bool _ready = false;

  bool get _current =>
      mounted && _epoch == ref.read(sessionProvider).activeEpoch;
  bool get _mobile =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _epoch = ref.read(sessionProvider).activeEpoch;
    Future.microtask(() async {
      await _refresh();
      final file = await AvatarPickerRecovery.instance.takeForOwner(
        _pickerOwner,
      );
      if (!mounted || !_current || file == null) return;
      final resume = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(context.l10n.avatarRecoverTitle),
          content: Text(context.l10n.avatarRecoverHint),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.commonCancel),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.avatarRecoverContinue),
            ),
          ],
        ),
      );
      if (resume == true && _current) {
        setState(() => _busy = true);
        try {
          await _prepare(file);
        } catch (_) {
          if (mounted && _current) {
            setState(() => _error = context.l10n.avatarImageRejected);
          }
        } finally {
          if (_current) setState(() => _busy = false);
        }
      }
      await discardAvatarPickerFile(file.path);
    });
  }

  Future<void> _refresh() async {
    try {
      await ref.read(profileProvider.notifier).loadAvatarProfile();
    } catch (_) {
      if (mounted && _current) _error = context.l10n.avatarLoadFailed;
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  String get _pickerOwner => '${_epoch?.ownerDid}|${_epoch?.identityKey}';

  Future<void> _prepare(XFile file) async {
    if (await file.length() > avatarSourceByteLimit) {
      throw const FormatException('avatar.source_size');
    }
    final preview = await prepareAvatarPreview(await file.readAsBytes());
    if (!_current) return;
    setState(() {
      _preview = preview;
      _ready = false;
    });
  }

  Future<void> _pick({bool camera = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? pickerToken;
    XFile? file;
    try {
      if (_mobile) {
        pickerToken = await AvatarPickerRecovery.instance.begin(_pickerOwner);
        if (!_current) return;
        file = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          requestFullMetadata: false,
          imageQuality: 100,
        );
      } else {
        file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'JPEG, PNG, WebP',
              extensions: ['jpg', 'jpeg', 'png', 'webp'],
              uniformTypeIdentifiers: [
                'public.jpeg',
                'public.png',
                'org.webmproject.webp',
              ],
            ),
          ],
        );
      }
      if (!mounted || !_current || file == null) return;
      await _prepare(file);
    } catch (_) {
      if (_current) setState(() => _error = context.l10n.avatarImageRejected);
    } finally {
      if (_mobile && file != null) await discardAvatarPickerFile(file.path);
      await AvatarPickerRecovery.instance.finish(pickerToken);
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _cropped(CropResult result) async {
    try {
      if (result is! CropSuccess) throw const FormatException('avatar.crop');
      final jpeg = await compute(encodeAvatarJpeg, result.croppedImage);
      if (!_current) return;
      _pendingJpeg = jpeg;
      await _save();
    } catch (_) {
      if (_current) {
        setState(() {
          _busy = false;
          _error = context.l10n.avatarImageRejected;
        });
      }
    }
  }

  Future<void> _confirmClear() async {
    final l10n = context.l10n;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.avatarReset),
        actions: [
          CupertinoDialogAction(
            key: const Key('avatar-clear-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          CupertinoDialogAction(
            key: const Key('avatar-clear-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && _current) await _save();
  }

  Future<void> _save() async {
    if (!_current) return;
    final profile = ref.read(profileProvider).profile;
    final version = _expectedVersion ?? profile?.profileVersion;
    if (version == null || profile?.avatarUploadEnabled != true) return;
    _expectedVersion = version;
    _requestId ??= _uuid();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileProvider.notifier)
          .mutateAvatar(
            requestId: _requestId!,
            expectedVersion: version,
            jpeg: _pendingJpeg,
          );
      if (mounted && _current) Navigator.of(context).pop();
    } catch (_) {
      if (!_current) return;
      // Preserve the exact UUID, bytes and expected version on uncertain outcome.
      // A newer authoritative version requires a deliberate new user operation.
      try {
        final latest = await ref
            .read(profileProvider.notifier)
            .loadAvatarProfile();
        if (!_current) return;
        if (latest.profileVersion != _expectedVersion) {
          _requestId = null;
          _expectedVersion = null;
          _pendingJpeg = null;
          _preview = null;
          setState(() => _error = context.l10n.avatarReconciled);
        } else {
          setState(() => _error = context.l10n.avatarSaveFailed);
        }
      } catch (_) {
        if (_current) setState(() => _error = context.l10n.avatarSaveFailed);
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((state) => state.activeEpoch), (_, next) {
      if (next != _epoch && mounted) Navigator.of(context).pop();
    });
    final profile = ref.watch(profileProvider).profile;
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final enabled = !_busy && profile?.avatarUploadEnabled == true;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 760),
        child: CupertinoPopupSurface(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.profileAvatarLabel,
                          style: TextStyle(
                            color: theme.title,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('avatar-close'),
                        padding: const EdgeInsets.all(8),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_preview != null)
                    AvatarCropEditor(
                      key: ValueKey(_preview),
                      bytes: _preview!,
                      controller: _crop,
                      enabled: enabled && _requestId == null,
                      onReady: (ready) {
                        if (mounted) setState(() => _ready = ready);
                      },
                      onCropped: _cropped,
                      currentAvatar: AvatarBadge(
                        seed: profile?.displayName ?? '',
                        userId: profile?.did,
                        avatarUri: profile?.avatarUri,
                        size: 72,
                      ),
                    )
                  else
                    AvatarBadge(
                      seed: profile?.displayName ?? '',
                      userId: profile?.did,
                      avatarUri: profile?.avatarUri,
                      size: 112,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _preview == null
                        ? l10n.avatarImageHint
                        : l10n.avatarCropHint,
                    style: TextStyle(color: theme.secondaryText, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const Key('avatar-error'),
                          style: TextStyle(color: theme.secondaryText),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CupertinoActivityIndicator(),
                    ),
                  if (!_busy && profile?.avatarUploadEnabled != true)
                    Text(l10n.avatarUnavailable),
                  if (_requestId != null)
                    CupertinoButton.filled(
                      key: const Key('avatar-retry'),
                      onPressed: enabled ? _save : null,
                      child: Text(l10n.avatarRetry),
                    )
                  else if (_preview != null) ...[
                    CupertinoButton(
                      key: const Key('avatar-pick'),
                      onPressed: enabled ? _pick : null,
                      child: Text(l10n.avatarChoose),
                    ),
                    CupertinoButton.filled(
                      key: const Key('avatar-save'),
                      onPressed: enabled && _ready
                          ? () {
                              setState(() => _busy = true);
                              _crop.crop();
                            }
                          : null,
                      child: Text(l10n.commonSave),
                    ),
                  ] else ...[
                    CupertinoButton(
                      key: const Key('avatar-pick'),
                      onPressed: enabled ? _pick : null,
                      child: Text(l10n.avatarChoose),
                    ),
                    if (_mobile)
                      CupertinoButton(
                        key: const Key('avatar-camera'),
                        onPressed: enabled ? () => _pick(camera: true) : null,
                        child: Text(l10n.avatarCamera),
                      ),
                    if (profile?.avatarUri != null)
                      CupertinoButton(
                        key: const Key('avatar-clear'),
                        onPressed: enabled ? _confirmClear : null,
                        child: Text(
                          l10n.avatarReset,
                          style: const TextStyle(
                            color: CupertinoColors.destructiveRed,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
