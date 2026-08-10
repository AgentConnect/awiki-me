import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../application/tenant/app_tenant.dart';
import '../../data/tenant/app_tenant_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import 'app_dialog.dart';
import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

/// Opens the complete tenant-management surface using the app's adaptive
/// dialog route on both compact and expanded layouts.
Future<void> showTenantManagementDialog(BuildContext context) async {
  await AppNavigator.showDialog<void>(
    context,
    (_) => const TenantManagementDialog(),
  );
}

/// Shared tenant-management UI used before and after authentication.
class TenantManagementDialog extends ConsumerStatefulWidget {
  const TenantManagementDialog({super.key});

  @override
  ConsumerState<TenantManagementDialog> createState() =>
      _TenantManagementDialogState();
}

class _TenantManagementDialogState
    extends ConsumerState<TenantManagementDialog> {
  final Set<String> _busyTenantIds = <String>{};
  _TenantUiError? _error;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(appTenantRegistryProvider);
    final activeTenant = registry.activeTenant;
    final tenants = registry.visibleTenants;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppDialogScaffold(
      maxWidth: 620,
      maxHeightFraction: 0.90,
      avoidViewInsets: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.spacing(18),
              responsive.spacing(18),
              responsive.spacing(18),
              responsive.spacing(12),
            ),
            child: AppDialogHeader(
              title: context.l10n.tenantManagementTitle,
              subtitle: context.l10n.tenantManagementSubtitle,
              leading: Container(
                width: responsive.displayScaled(36),
                height: responsive.displayScaled(36),
                decoration: BoxDecoration(
                  color: theme.primarySoft,
                  borderRadius: BorderRadius.circular(responsive.radius(8)),
                ),
                child: Icon(
                  CupertinoIcons.globe,
                  color: theme.primary,
                  size: responsive.iconMd,
                ),
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(18),
                responsive.spacing(4),
                responsive.spacing(18),
                responsive.spacing(12),
              ),
              itemCount: tenants.length,
              separatorBuilder: (_, __) =>
                  SizedBox(height: responsive.spacing(8)),
              itemBuilder: (context, index) {
                final tenant = tenants[index];
                return _TenantListTile(
                  key: Key('settings-tenant-option:${tenant.id}'),
                  tenant: tenant,
                  active: tenant.id == activeTenant.id,
                  busy: _busyTenantIds.contains(tenant.id),
                  onUse: () => _useTenant(tenant),
                  onEdit: tenant.isPrimaryTenant
                      ? null
                      : () => _openForm(tenant: tenant),
                  onDelete:
                      tenant.isPrimaryTenant || tenant.id == activeTenant.id
                      ? null
                      : () => _deleteTenant(tenant),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(18),
                0,
                responsive.spacing(18),
                responsive.spacing(10),
              ),
              child: _TenantInlineMessage(
                message: _tenantErrorMessage(context.l10n, _error!),
                danger: true,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.spacing(18),
              responsive.spacing(4),
              responsive.spacing(18),
              responsive.spacing(18),
            ),
            child: responsive.isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        context.l10n.tenantPrimaryAgentNote,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: responsive.metaSm,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: responsive.spacing(12)),
                      AppPrimaryButton(
                        key: const Key('tenant-management-create-button'),
                        label: context.l10n.tenantCreate,
                        onPressed: () => _openForm(),
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.l10n.tenantPrimaryAgentNote,
                          style: TextStyle(
                            color: theme.secondaryText,
                            fontSize: responsive.metaSm,
                            height: 1.3,
                          ),
                        ),
                      ),
                      SizedBox(width: responsive.spacing(14)),
                      SizedBox(
                        width: responsive.displayScaled(152),
                        child: AppPrimaryButton(
                          key: const Key('tenant-management-create-button'),
                          label: context.l10n.tenantCreate,
                          onPressed: () => _openForm(),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _useTenant(AppTenantProfile tenant) async {
    final active = ref.read(activeAppTenantProvider);
    if (tenant.id == active.id) {
      Navigator.of(context).pop();
      return;
    }
    await _runTenantAction(
      tenant.id,
      () => ref.read(appTenantActionsProvider).useTenant(tenant.id),
      closeDialog: true,
    );
  }

  Future<void> _deleteTenant(AppTenantProfile tenant) async {
    final confirmed = await AppNavigator.showDialog<bool>(
      context,
      (dialogContext) => AppConfirmationDialog(
        title: dialogContext.l10n.tenantDeleteTitle,
        message: dialogContext.l10n.tenantDeleteContent(tenant.name),
        confirmLabel: dialogContext.l10n.commonDelete,
        destructive: true,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runTenantAction(
      tenant.id,
      () => ref.read(appTenantActionsProvider).deleteTenant(tenant.id),
    );
  }

  Future<void> _openForm({AppTenantProfile? tenant}) async {
    final changedTenantId = await AppNavigator.showDialog<String>(
      context,
      (_) => _TenantFormDialog(tenant: tenant),
    );
    if (changedTenantId == null || !mounted) {
      return;
    }
    setState(() => _error = null);
  }

  Future<void> _runTenantAction(
    String tenantId,
    Future<AppTenantRegistry> Function() action, {
    bool closeDialog = false,
  }) async {
    if (_busyTenantIds.contains(tenantId)) {
      return;
    }
    setState(() {
      _error = null;
      _busyTenantIds.add(tenantId);
    });
    var completed = false;
    try {
      await action();
      completed = true;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _tenantUiError(error));
    } finally {
      if (mounted) {
        setState(() => _busyTenantIds.remove(tenantId));
      }
    }
    if (!completed || !mounted || !closeDialog) {
      return;
    }
    try {
      Navigator.of(context).pop();
    } catch (_) {
      // Switching tenants rebuilds the scoped app and can dispose this route.
    }
  }
}

class _TenantListTile extends StatelessWidget {
  const _TenantListTile({
    super.key,
    required this.tenant,
    required this.active,
    required this.busy,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final AppTenantProfile tenant;
  final bool active;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final identity = Row(
      children: <Widget>[
        Container(
          width: responsive.displayScaled(36),
          height: responsive.displayScaled(36),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            border: Border.all(color: theme.border),
          ),
          child: Center(
            child: Icon(
              tenant.isPrimaryTenant
                  ? CupertinoIcons.checkmark_seal_fill
                  : CupertinoIcons.square_stack_3d_up,
              color: tenant.isPrimaryTenant
                  ? theme.primary
                  : theme.secondaryText,
              size: responsive.iconSm,
            ),
          ),
        ),
        SizedBox(width: responsive.spacing(12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      tenant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (active) ...<Widget>[
                    SizedBox(width: responsive.spacing(8)),
                    _TenantStatusPill(label: context.l10n.tenantCurrent),
                  ],
                ],
              ),
              if (tenant.isPrimaryTenant) ...<Widget>[
                SizedBox(height: responsive.spacing(4)),
                _TenantManagedLabel(
                  key: Key('tenant-primary-managed:${tenant.id}'),
                  label: context.l10n.tenantDefaultBadge,
                ),
              ],
              SizedBox(height: responsive.spacing(4)),
              Text(
                '${tenant.backendBaseUrl} · ${tenant.didHost}',
                maxLines: responsive.isCompact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: responsive.metaSm,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final hasActions = !active || onEdit != null || onDelete != null;
    final Widget? actions = busy
        ? SizedBox(
            width: responsive.displayScaled(40),
            height: responsive.displayScaled(40),
            child: const Center(child: CupertinoActivityIndicator(radius: 8)),
          )
        : hasActions
        ? _TenantTileActions(
            tenant: tenant,
            active: active,
            onUse: onUse,
            onEdit: onEdit,
            onDelete: onDelete,
          )
        : null;
    final borderRadius = BorderRadius.circular(responsive.radius(8));
    return AppPressable(
      onTap: active || busy ? null : onUse,
      semanticLabel: active
          ? '${tenant.name}, ${context.l10n.tenantCurrent}'
          : '${context.l10n.tenantUse}: ${tenant.name}',
      borderRadius: borderRadius,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(12),
          responsive.spacing(12),
          responsive.spacing(10),
          responsive.spacing(responsive.isCompact ? 6 : 12),
        ),
        decoration: BoxDecoration(
          color: active ? theme.primarySoft : theme.subtleSurface,
          borderRadius: borderRadius,
          border: Border.all(
            color: active
                ? theme.primary.withValues(alpha: 0.26)
                : theme.border,
          ),
        ),
        child: responsive.isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  identity,
                  if (actions != null) ...<Widget>[
                    SizedBox(height: responsive.spacing(4)),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                ],
              )
            : actions == null
            ? identity
            : Row(
                children: <Widget>[
                  Expanded(child: identity),
                  SizedBox(width: responsive.spacing(10)),
                  actions,
                ],
              ),
      ),
    );
  }
}

class _TenantTileActions extends StatelessWidget {
  const _TenantTileActions({
    required this.tenant,
    required this.active,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final AppTenantProfile tenant;
  final bool active;
  final VoidCallback onUse;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final buttonSize = responsive.isCompact
        ? responsive.displayScaled(44).clamp(46, double.infinity).toDouble()
        : responsive.displayScaled(32);
    Widget actionButton({
      required String action,
      required String semanticLabel,
      required String tooltip,
      required VoidCallback? onPressed,
      required Widget child,
    }) {
      if (!responsive.isCompact) {
        return AppIconButton(
          onPressed: onPressed,
          semanticLabel: semanticLabel,
          tooltip: tooltip,
          size: buttonSize,
          backgroundColor: theme.surface,
          borderColor: theme.border,
          child: child,
        );
      }
      return AppIconButton(
        onPressed: onPressed,
        semanticLabel: semanticLabel,
        tooltip: tooltip,
        size: buttonSize,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: Key('tenant-action-visual-$action:${tenant.id}'),
            width: buttonSize,
            height: responsive.displayScaled(36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(responsive.radius(8)),
              border: Border.all(color: theme.border),
            ),
            child: child,
          ),
        ),
      );
    }

    return Wrap(
      spacing: responsive.spacing(4),
      children: <Widget>[
        if (!active)
          actionButton(
            action: 'use',
            onPressed: onUse,
            semanticLabel: context.l10n.tenantUse,
            tooltip: context.l10n.tenantUse,
            child: Icon(
              CupertinoIcons.arrow_right_circle,
              size: responsive.iconSm,
              color: theme.primary,
            ),
          ),
        if (onEdit != null)
          actionButton(
            action: 'edit',
            onPressed: onEdit,
            semanticLabel: context.l10n.tenantEdit,
            tooltip: context.l10n.tenantEdit,
            child: Icon(
              CupertinoIcons.pencil,
              size: responsive.iconSm,
              color: theme.secondaryText,
            ),
          ),
        if (onDelete != null)
          actionButton(
            action: 'delete',
            onPressed: onDelete,
            semanticLabel: context.l10n.commonDelete,
            tooltip: context.l10n.commonDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: responsive.iconSm,
              color: theme.danger,
            ),
          ),
      ],
    );
  }
}

class _TenantManagedLabel extends StatelessWidget {
  const _TenantManagedLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          CupertinoIcons.lock_fill,
          size: responsive.displayScaled(11),
          color: theme.secondaryText,
        ),
        SizedBox(width: responsive.spacing(4)),
        Text(
          label,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _TenantStatusPill extends StatelessWidget {
  const _TenantStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(7),
        vertical: responsive.spacing(3),
      ),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(responsive.radius(999)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.primaryForeground,
          fontSize: responsive.displayScaled(11),
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

class _TenantFormDialog extends ConsumerStatefulWidget {
  const _TenantFormDialog({this.tenant});

  final AppTenantProfile? tenant;

  @override
  ConsumerState<_TenantFormDialog> createState() => _TenantFormDialogState();
}

class _TenantFormDialogState extends ConsumerState<_TenantFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _backendController;
  late final TextEditingController _didHostController;
  bool _submitting = false;
  late bool _checkingData;
  bool _hasData = false;
  bool _dataStateCheckFailed = false;
  _TenantUiError? _error;

  bool get _editing => widget.tenant != null;

  @override
  void initState() {
    super.initState();
    final tenant = widget.tenant;
    _nameController = TextEditingController(text: tenant?.name ?? '');
    _backendController = TextEditingController(
      text: tenant?.backendBaseUrl ?? '',
    );
    _didHostController = TextEditingController(text: tenant?.didHost ?? '');
    _checkingData = tenant != null;
    if (tenant != null) {
      _loadDataState(tenant);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _backendController.dispose();
    _didHostController.dispose();
    super.dispose();
  }

  Future<void> _loadDataState(AppTenantProfile tenant) async {
    try {
      final hasData = await ref
          .read(appTenantActionsProvider)
          .tenantHasData(tenant.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _hasData = hasData;
        _dataStateCheckFailed = false;
        _checkingData = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasData = true;
        _dataStateCheckFailed = true;
        _checkingData = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final renameOnly = _editing && (_hasData || _dataStateCheckFailed);
    return AppDialogScaffold(
      maxWidth: 520,
      maxHeightFraction: 0.92,
      avoidViewInsets: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(responsive.spacing(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppDialogHeader(
              title: !_editing
                  ? context.l10n.tenantCreateTitle
                  : renameOnly
                  ? context.l10n.tenantRenameTitle
                  : context.l10n.tenantEditTitle,
              onClose: _submitting ? null : () => Navigator.of(context).pop(),
              isCloseEnabled: !_submitting,
            ),
            SizedBox(height: responsive.spacing(18)),
            if (_checkingData)
              const Center(child: CupertinoActivityIndicator())
            else ...<Widget>[
              if (_editing) ...<Widget>[
                _TenantInlineMessage(
                  message: _dataStateCheckFailed
                      ? context.l10n.tenantDataStateCheckFailed
                      : _hasData
                      ? context.l10n.tenantCannotEditWithData
                      : context.l10n.tenantDidHostImmutable,
                  danger: false,
                ),
                SizedBox(height: responsive.spacing(14)),
              ],
              AppTextField(
                key: const Key('tenant-name-field'),
                controller: _nameController,
                label: context.l10n.tenantName,
                placeholder: context.l10n.tenantNamePlaceholder,
                enabled: !_submitting,
              ),
              SizedBox(height: responsive.spacing(12)),
              if (renameOnly)
                _TenantReadOnlyField(
                  key: const Key('tenant-backend-readonly'),
                  label: context.l10n.tenantBackendBaseUrl,
                  value: widget.tenant!.backendBaseUrl,
                )
              else
                AppTextField(
                  key: const Key('tenant-backend-field'),
                  controller: _backendController,
                  label: context.l10n.tenantBackendBaseUrl,
                  placeholder: context.l10n.tenantBackendBaseUrlPlaceholder,
                  keyboardType: TextInputType.url,
                  enabled: !_submitting,
                ),
              SizedBox(height: responsive.spacing(12)),
              if (_editing)
                _TenantReadOnlyField(
                  key: const Key('tenant-did-host-readonly'),
                  label: context.l10n.tenantDidHost,
                  value: widget.tenant!.didHost,
                )
              else
                AppTextField(
                  key: const Key('tenant-did-host-field'),
                  controller: _didHostController,
                  label: context.l10n.tenantDidHost,
                  placeholder: context.l10n.tenantDidHostPlaceholder,
                  keyboardType: TextInputType.url,
                  enabled: !_submitting,
                ),
              if (_error != null) ...<Widget>[
                SizedBox(height: responsive.spacing(12)),
                _TenantInlineMessage(
                  message: _tenantErrorMessage(context.l10n, _error!),
                  danger: true,
                ),
              ],
              SizedBox(height: responsive.spacing(18)),
              if (responsive.isCompact) ...<Widget>[
                AppPrimaryButton(
                  key: const Key('tenant-form-submit-button'),
                  label: _submitLabel(context),
                  onPressed: _submitting ? null : _submit,
                ),
                SizedBox(height: responsive.spacing(10)),
                AppSecondaryButton(
                  label: context.l10n.commonCancel,
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ] else
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSecondaryButton(
                        label: context.l10n.commonCancel,
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(12)),
                    Expanded(
                      child: AppPrimaryButton(
                        key: const Key('tenant-form-submit-button'),
                        label: _submitLabel(context),
                        onPressed: _submitting ? null : _submit,
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _submitLabel(BuildContext context) {
    if (_submitting) {
      return context.l10n.tenantSaving;
    }
    if (!_editing) {
      return context.l10n.tenantCreate;
    }
    return _hasData || _dataStateCheckFailed
        ? context.l10n.tenantSaveName
        : context.l10n.commonSave;
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final normalizedName = normalizeTenantName(_nameController.text);
      final normalizedBackend = _editing && (_hasData || _dataStateCheckFailed)
          ? widget.tenant!.backendBaseUrl
          : normalizeTenantBackendBaseUrl(_backendController.text);
      if (_editing) {
        await ref
            .read(appTenantActionsProvider)
            .updateTenant(
              AppTenantUpdateInput(
                id: widget.tenant!.id,
                name: normalizedName,
                backendBaseUrl: normalizedBackend,
                didHost: widget.tenant!.didHost,
              ),
            );
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(widget.tenant!.id);
        return;
      }
      final normalizedDidHost = normalizeTenantDidHost(_didHostController.text);
      final registry = await ref
          .read(appTenantActionsProvider)
          .createTenant(
            AppTenantCreateInput(
              name: normalizedName,
              backendBaseUrl: normalizedBackend,
              didHost: normalizedDidHost,
            ),
          );
      if (!mounted) {
        return;
      }
      final created = registry.visibleTenants.firstWhere(
        (tenant) =>
            tenant.name == normalizedName &&
            tenant.backendBaseUrl == normalizedBackend &&
            tenant.didHost == normalizedDidHost,
      );
      Navigator.of(context).pop(created.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _tenantUiError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _TenantReadOnlyField extends StatelessWidget {
  const _TenantReadOnlyField({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AwikiMeTextStyles.fieldLabel.copyWith(
            color: theme.secondaryText,
            fontSize: responsive.metaSm,
          ),
        ),
        SizedBox(height: responsive.spacing(6)),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: responsive.compactControlHeight,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(14),
            vertical: responsive.spacing(11),
          ),
          decoration: BoxDecoration(
            color: theme.mutedSurface,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SelectionArea(
                  child: Text(
                    value,
                    style: AwikiMeTextStyles.inputText.copyWith(
                      color: theme.body,
                      fontSize: responsive.bodyMd,
                    ),
                  ),
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Icon(
                CupertinoIcons.lock_fill,
                size: responsive.iconSm,
                color: theme.secondaryText,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TenantInlineMessage extends StatelessWidget {
  const _TenantInlineMessage({required this.message, required this.danger});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(10)),
      decoration: BoxDecoration(
        color: danger ? theme.dangerContainer : theme.primarySoft,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: danger
              ? theme.danger.withValues(alpha: 0.22)
              : theme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: SelectionArea(
        child: Text(
          message,
          style: TextStyle(
            color: danger ? theme.danger : theme.secondaryText,
            fontSize: responsive.bodySm,
            height: 1.35,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TenantUiError {
  const _TenantUiError(this.code, {this.detail});

  final String code;
  final String? detail;
}

_TenantUiError _tenantUiError(Object error) {
  if (error is AppTenantValidationException) {
    return _TenantUiError(error.code);
  }
  final raw = error.toString();
  const marker = 'AppTenantValidationException: ';
  if (raw.startsWith(marker)) {
    return _TenantUiError(raw.substring(marker.length).trim());
  }
  final detail = raw.trim();
  return _TenantUiError(
    'tenant_unknown_error',
    detail: detail.isEmpty ? null : detail,
  );
}

String _tenantErrorMessage(AppLocalizations l10n, _TenantUiError error) {
  final message = switch (error.code) {
    'tenant_name_invalid' => l10n.tenantValidationNameInvalid,
    'tenant_backend_invalid' => l10n.tenantValidationBackendInvalid,
    'tenant_did_host_invalid' => l10n.tenantValidationDidHostInvalid,
    'tenant_name_exists' => l10n.tenantValidationNameExists,
    'tenant_endpoint_exists' => l10n.tenantValidationEndpointExists,
    'tenant_has_data' => l10n.tenantValidationHasData,
    'tenant_realm_change_requires_new_scope' => l10n.tenantDidHostImmutable,
    'tenant_default_edit_forbidden' => l10n.tenantCannotEditDefault,
    'tenant_default_delete_forbidden' => l10n.tenantCannotDeleteDefault,
    'tenant_active_delete_forbidden' => l10n.tenantCannotDeleteActive,
    'tenant_not_found' => l10n.tenantNotFound,
    _ => l10n.tenantOperationFailed,
  };
  final detail = error.detail?.trim();
  if (detail == null || detail.isEmpty) {
    return message;
  }
  return '$message\n$detail';
}
