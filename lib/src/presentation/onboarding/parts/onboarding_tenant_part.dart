part of '../onboarding_page.dart';

class _OnboardingUtilityBar extends StatelessWidget {
  const _OnboardingUtilityBar({
    required this.tenant,
    required this.localeMode,
    required this.onLanguagePressed,
    required this.onPressed,
    this.fillAvailableWidth = false,
  });

  final AppTenantProfile tenant;
  final AppLocaleMode localeMode;
  final VoidCallback onLanguagePressed;
  final VoidCallback onPressed;
  final bool fillAvailableWidth;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final languageButton = _LanguageSwitcherButton(
      localeMode: localeMode,
      onPressed: onLanguagePressed,
    );
    final tenantButton = _TenantSwitcherButton(
      key: const Key('onboarding-tenant-switcher-button'),
      tenant: tenant,
      onPressed: onPressed,
    );
    if (!fillAvailableWidth) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          languageButton,
          SizedBox(width: responsive.spacing(8)),
          tenantButton,
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        languageButton,
        SizedBox(width: responsive.spacing(8)),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: tenantButton),
        ),
      ],
    );
  }
}

class _LanguageSwitcherButton extends StatelessWidget {
  const _LanguageSwitcherButton({
    required this.localeMode,
    required this.onPressed,
  });

  final AppLocaleMode localeMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final label = compactAppLocaleModeLabel(context, localeMode);
    final fullLabel = appLocaleModeLabel(context, localeMode);
    return AppPressable(
      key: const Key('onboarding-language-switcher-button'),
      onTap: onPressed,
      semanticLabel: '${context.l10n.settingsLanguage}: $fullLabel',
      tooltip: context.l10n.settingsLanguage,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      child: Container(
        constraints: BoxConstraints(minWidth: responsive.displayScaled(58)),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(7),
        ),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(responsive.radius(10)),
          border: Border.all(color: const Color(0xFFDCE5F2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              CupertinoIcons.textformat,
              size: responsive.displayScaled(15),
              color: theme.secondaryText,
            ),
            SizedBox(width: responsive.spacing(5)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TenantSwitcherButton extends StatelessWidget {
  const _TenantSwitcherButton({
    super.key,
    required this.tenant,
    required this.onPressed,
  });

  final AppTenantProfile tenant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: context.l10n.tenantSwitcherLabel,
      tooltip: context.l10n.tenantSwitcherLabel,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      child: Container(
        constraints: BoxConstraints(maxWidth: responsive.displayScaled(260)),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(7),
        ),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(responsive.radius(10)),
          border: Border.all(color: const Color(0xFFDCE5F2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              CupertinoIcons.globe,
              size: responsive.displayScaled(14),
              color: theme.secondaryText,
            ),
            SizedBox(width: responsive.spacing(6)),
            Flexible(
              child: Text(
                tenant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: responsive.metaSm,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(width: responsive.spacing(4)),
            Icon(
              CupertinoIcons.chevron_down,
              size: responsive.displayScaled(12),
              color: theme.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _TenantManagementDialog extends ConsumerStatefulWidget {
  const _TenantManagementDialog();

  @override
  ConsumerState<_TenantManagementDialog> createState() =>
      _TenantManagementDialogState();
}

class _TenantManagementDialogState
    extends ConsumerState<_TenantManagementDialog> {
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
                  color: AwikiMePalette.actionBlueSoft,
                  borderRadius: BorderRadius.circular(responsive.radius(10)),
                ),
                child: Icon(
                  CupertinoIcons.globe,
                  color: AwikiMePalette.actionBlue,
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
                  SizedBox(height: responsive.spacing(10)),
              itemBuilder: (context, index) {
                final tenant = tenants[index];
                return _TenantListTile(
                  tenant: tenant,
                  active: tenant.id == activeTenant.id,
                  busy: _busyTenantIds.contains(tenant.id),
                  onUse: () => _useTenant(tenant),
                  onEdit: tenant.id == defaultTenantId || tenant.isPrimaryTenant
                      ? null
                      : () => _openForm(tenant: tenant),
                  onDelete:
                      tenant.id == defaultTenantId ||
                          tenant.isPrimaryTenant ||
                          tenant.id == activeTenant.id
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
            child: Row(
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
                  width: responsive.displayScaled(132),
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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: Text(context.l10n.tenantDeleteTitle),
        content: Text(context.l10n.tenantDeleteContent(tenant.name)),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _runTenantAction(
      tenant.id,
      () => ref.read(appTenantActionsProvider).deleteTenant(tenant.id),
    );
  }

  Future<void> _openForm({AppTenantProfile? tenant}) async {
    final createdTenantId = await showCupertinoDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TenantFormDialog(tenant: tenant),
    );
    if (createdTenantId == null || !mounted || tenant != null) {
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
      // Tenant switching rebuilds the app shell, so the old dialog context can
      // disappear after a successful switch. That is not a tenant operation
      // failure and should not surface as one.
    }
  }
}

class _TenantListTile extends StatelessWidget {
  const _TenantListTile({
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(12),
        responsive.spacing(12),
        responsive.spacing(10),
        responsive.spacing(12),
      ),
      decoration: BoxDecoration(
        color: active ? AwikiMePalette.actionBlueSoft : theme.subtleSurface,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: active
              ? AwikiMePalette.actionBlueBorder
              : const Color(0xFFE5EAF2),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: responsive.displayScaled(36),
            height: responsive.displayScaled(36),
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(responsive.radius(9)),
              border: Border.all(color: const Color(0xFFE0E7F2)),
            ),
            child: Center(
              child: Icon(
                tenant.isPrimaryTenant
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.square_stack_3d_up,
                color: tenant.isPrimaryTenant
                    ? AwikiMePalette.actionBlue
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (active) ...<Widget>[
                      SizedBox(width: responsive.spacing(8)),
                      _TenantStatusPill(label: context.l10n.tenantCurrent),
                    ],
                  ],
                ),
                SizedBox(height: responsive.spacing(4)),
                Text(
                  '${tenant.backendBaseUrl} · ${tenant.didHost}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: responsive.metaSm,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          if (busy)
            CupertinoActivityIndicator(radius: responsive.displayScaled(8))
          else
            Wrap(
              spacing: responsive.spacing(4),
              children: <Widget>[
                AppIconButton(
                  onPressed: active ? null : onUse,
                  semanticLabel: context.l10n.tenantUse,
                  tooltip: context.l10n.tenantUse,
                  size: responsive.displayScaled(32),
                  backgroundColor: CupertinoColors.white,
                  borderColor: const Color(0xFFE0E7F2),
                  child: Icon(
                    CupertinoIcons.arrow_right_circle,
                    size: responsive.iconSm,
                    color: active ? theme.tertiaryText : theme.primary,
                  ),
                ),
                AppIconButton(
                  onPressed: onEdit,
                  semanticLabel: context.l10n.tenantEdit,
                  tooltip: onEdit == null
                      ? context.l10n.tenantCannotEditDefault
                      : context.l10n.tenantEdit,
                  size: responsive.displayScaled(32),
                  backgroundColor: CupertinoColors.white,
                  borderColor: const Color(0xFFE0E7F2),
                  child: Icon(
                    CupertinoIcons.pencil,
                    size: responsive.iconSm,
                    color: onEdit == null
                        ? theme.tertiaryText
                        : theme.secondaryText,
                  ),
                ),
                AppIconButton(
                  onPressed: onDelete,
                  semanticLabel: context.l10n.commonDelete,
                  tooltip: _deleteTooltip(context, tenant, active),
                  size: responsive.displayScaled(32),
                  backgroundColor: CupertinoColors.white,
                  borderColor: const Color(0xFFE0E7F2),
                  child: Icon(
                    CupertinoIcons.trash,
                    size: responsive.iconSm,
                    color: onDelete == null
                        ? theme.tertiaryText
                        : AwikiMePalette.error,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _deleteTooltip(
    BuildContext context,
    AppTenantProfile tenant,
    bool active,
  ) {
    if (tenant.id == defaultTenantId || tenant.isPrimaryTenant) {
      return context.l10n.tenantCannotDeleteDefault;
    }
    if (active) {
      return context.l10n.tenantCannotDeleteActive;
    }
    return context.l10n.commonDelete;
  }
}

class _TenantStatusPill extends StatelessWidget {
  const _TenantStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(7),
        vertical: responsive.spacing(3),
      ),
      decoration: BoxDecoration(
        color: AwikiMePalette.actionBlue,
        borderRadius: BorderRadius.circular(responsive.radius(999)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: responsive.displayScaled(11),
          fontWeight: FontWeight.w700,
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
        _checkingData = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasData = true;
        _checkingData = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppDialogScaffold(
      maxWidth: 520,
      maxHeightFraction: 0.92,
      avoidViewInsets: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(18),
          responsive.spacing(18),
          responsive.spacing(18),
          responsive.spacing(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppDialogHeader(
              title: _editing
                  ? context.l10n.tenantEditTitle
                  : context.l10n.tenantCreateTitle,
              onClose: _submitting ? null : () => Navigator.of(context).pop(),
              isCloseEnabled: !_submitting,
            ),
            SizedBox(height: responsive.spacing(18)),
            if (_checkingData)
              const Center(child: CupertinoActivityIndicator())
            else ...<Widget>[
              if (_editing && _hasData) ...<Widget>[
                _TenantInlineMessage(
                  message: context.l10n.tenantCannotEditWithData,
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
              AppTextField(
                key: const Key('tenant-backend-field'),
                controller: _backendController,
                label: context.l10n.tenantBackendBaseUrl,
                placeholder: context.l10n.tenantBackendBaseUrlPlaceholder,
                keyboardType: TextInputType.url,
                enabled: !_submitting && !_hasData,
              ),
              SizedBox(height: responsive.spacing(12)),
              AppTextField(
                key: const Key('tenant-did-host-field'),
                controller: _didHostController,
                label: context.l10n.tenantDidHost,
                placeholder: context.l10n.tenantDidHostPlaceholder,
                keyboardType: TextInputType.url,
                enabled: !_submitting && !_hasData,
              ),
              if (_error != null) ...<Widget>[
                SizedBox(height: responsive.spacing(12)),
                _TenantInlineMessage(
                  message: _tenantErrorMessage(context.l10n, _error!),
                  danger: true,
                ),
              ],
              SizedBox(height: responsive.spacing(18)),
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
                      label: _submitting
                          ? context.l10n.tenantSaving
                          : (_editing
                                ? context.l10n.commonSave
                                : context.l10n.tenantCreate),
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

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_editing) {
        final normalizedName = normalizeTenantName(_nameController.text);
        final normalizedBackend = normalizeTenantBackendBaseUrl(
          _backendController.text,
        );
        final normalizedDidHost = normalizeTenantDidHost(
          _didHostController.text,
        );
        await ref
            .read(appTenantActionsProvider)
            .updateTenant(
              AppTenantUpdateInput(
                id: widget.tenant!.id,
                name: normalizedName,
                backendBaseUrl: normalizedBackend,
                didHost: normalizedDidHost,
              ),
            );
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
        return;
      }
      final normalizedName = normalizeTenantName(_nameController.text);
      final normalizedBackend = normalizeTenantBackendBaseUrl(
        _backendController.text,
      );
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
        color: danger ? theme.dangerContainer : AwikiMePalette.actionBlueSoft,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: danger
              ? theme.danger.withValues(alpha: 0.22)
              : AwikiMePalette.actionBlueBorder,
        ),
      ),
      child: SelectionArea(
        child: Text(
          message,
          style: TextStyle(
            color: danger ? theme.danger : theme.secondaryText,
            fontSize: responsive.bodySm,
            height: 1.35,
            fontWeight: FontWeight.w600,
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
