import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/screenshot_failure.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

/// Recovery is user-driven: never reset TCC, quit, capture or change identities.
class ScreenshotPermissionDialog extends StatefulWidget {
  const ScreenshotPermissionDialog({
    super.key,
    this.diagnostics,
    this.openSettings,
    this.copyDiagnostics,
  });

  final ScreenshotAppDiagnostics? diagnostics;
  final Future<bool> Function()? openSettings;
  final Future<void> Function(String)? copyDiagnostics;

  @override
  State<ScreenshotPermissionDialog> createState() =>
      _ScreenshotPermissionDialogState();
}

class _ScreenshotPermissionDialogState
    extends State<ScreenshotPermissionDialog> {
  bool _busy = false;
  bool _settingsFailed = false;
  bool _copyFailed = false;
  bool _copied = false;
  bool _showRecovery = false;
  bool _showDiagnostics = false;

  String get _buildMode =>
      kDebugMode ? 'Debug' : (kProfileMode ? 'Profile' : 'Release');

  String get _diagnosticsText {
    final info = widget.diagnostics;
    return [
      'code: screenshot_screen_recording_permission_required',
      'build_mode: $_buildMode',
      if (info != null) ...[
        'application: ${info.applicationName}',
        'bundle_id: ${info.bundleIdentifier}',
        'version: ${info.version}',
        'application_path: ${info.applicationPath}',
      ] else
        'application_info: unavailable',
    ].join('\n');
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _settingsFailed = false;
    });
    var opened = false;
    try {
      opened =
          await (widget.openSettings?.call() ??
              launchUrl(
                Uri.parse(
                  'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
                ),
              ));
    } catch (_) {
      // Keep a manual path visible; never expose native exception text.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _settingsFailed = !opened;
    });
  }

  Future<void> _copy() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _copyFailed = false;
      _copied = false;
    });
    var copied = false;
    try {
      await (widget.copyDiagnostics?.call(_diagnosticsText) ??
          Clipboard.setData(ClipboardData(text: _diagnosticsText)));
      copied = true;
    } catch (_) {
      // Copying is optional and must not break the recovery UI.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _copyFailed = !copied;
      _copied = copied;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final info = widget.diagnostics;
    return AppDialogScaffold(
      maxWidth: 560,
      compactCentered: true,
      padding: EdgeInsets.all(responsive.spacing(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDialogHeader(
            title: l10n.screenshotPermissionTitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: responsive.spacing(12)),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.screenshotPermissionRequired),
                  SizedBox(height: responsive.spacing(12)),
                  _disclosure(
                    key: const Key('screenshot-recovery-toggle'),
                    label: l10n.screenshotPermissionHelp,
                    expanded: _showRecovery,
                    onTap: () => setState(() => _showRecovery = !_showRecovery),
                  ),
                  if (_showRecovery) ...[
                    SizedBox(height: responsive.spacing(8)),
                    Text(l10n.screenshotPermissionRecovery),
                    SizedBox(height: responsive.spacing(12)),
                    Text(
                      l10n.screenshotCurrentApplication,
                      style: TextStyle(
                        color: theme.title,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(6)),
                    Text(
                      info == null
                          ? l10n.screenshotApplicationUnavailable
                          : '${info.applicationName}\n${info.applicationPath}',
                    ),
                    SizedBox(height: responsive.spacing(12)),
                    _disclosure(
                      key: const Key('screenshot-diagnostics-toggle'),
                      label: l10n.screenshotShowDiagnostics,
                      expanded: _showDiagnostics,
                      onTap: () =>
                          setState(() => _showDiagnostics = !_showDiagnostics),
                    ),
                    if (_showDiagnostics) ...[
                      SizedBox(height: responsive.spacing(8)),
                      Text('${l10n.screenshotBuildMode}: $_buildMode'),
                      if (info != null)
                        Text(
                          '${info.applicationName} ${info.version}\n'
                          'Bundle ID: ${info.bundleIdentifier}',
                        ),
                      SizedBox(height: responsive.spacing(8)),
                      Text(
                        l10n.screenshotDiagnosticsPrivacy,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: responsive.metaSm,
                        ),
                      ),
                      if (_copyFailed)
                        Text(
                          l10n.commonCopyFailed,
                          style: TextStyle(color: theme.danger),
                        ),
                      SizedBox(height: responsive.spacing(8)),
                      AppSecondaryButton(
                        key: const Key('screenshot-copy-diagnostics'),
                        label: _copied
                            ? l10n.commonCopied
                            : l10n.screenshotCopyDiagnostics,
                        onPressed: _busy ? null : _copy,
                      ),
                    ],
                  ],
                  if (_settingsFailed) ...[
                    SizedBox(height: responsive.spacing(12)),
                    Text(
                      l10n.screenshotPermissionSettingsFailed,
                      style: TextStyle(color: theme.danger),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: responsive.spacing(16)),
          // Keep the next action reachable even when recovery details scroll.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPrimaryButton(
                key: const Key('screenshot-open-settings'),
                label: l10n.screenshotPermissionSettings,
                onPressed: _busy ? null : _openSettings,
              ),
              SizedBox(height: responsive.spacing(8)),
              AppSecondaryButton(
                key: const Key('screenshot-not-now'),
                label: l10n.screenshotPermissionLater,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _disclosure({
    required Key key,
    required String label,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Semantics(
      expanded: expanded,
      child: AppPressable(
        key: key,
        onTap: onTap,
        semanticLabel: label,
        focusColor: theme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: theme.primary)),
              ),
              SizedBox(width: responsive.spacing(8)),
              Icon(
                expanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                color: theme.primary,
                size: responsive.iconSm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
