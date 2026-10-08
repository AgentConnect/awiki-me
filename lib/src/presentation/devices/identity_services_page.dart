import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/identity_method.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/awiki_glass_controls.dart';
import 'devices_provider.dart';

class IdentityServicesPage extends ConsumerStatefulWidget {
  const IdentityServicesPage({super.key, required this.selector});

  final String selector;

  @override
  ConsumerState<IdentityServicesPage> createState() =>
      _IdentityServicesPageState();
}

class _IdentityServicesPageState extends ConsumerState<IdentityServicesPage> {
  IdentityServicesSnapshot? _snapshot;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool get _canManage {
    final state = ref.read(devicesProvider);
    return state.registry?.did == widget.selector &&
        state.registry?.methodCapabilities?.servicesUpdate == true &&
        state.currentDeviceCanManage;
  }

  Future<void> _load() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await ref.read(devicesProvider.notifier).refreshRegistryOnly();
      final snapshot = await ref
          .read(identityDocumentCorePortProvider)
          .identityServices(widget.selector);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(List<IdentityDocumentService>? services) async {
    if (_busy || !_canManage) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final port = ref.read(identityDocumentCorePortProvider);
    try {
      if (services == null) {
        await port.resumeIdentityServicesUpdate(widget.selector);
      } else {
        await port.updateIdentityServices(widget.selector, services);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      // Re-read Core even after a transport failure: a durable operation may
      // already exist and must be resumed before accepting a new proposal.
      try {
        final snapshot = await port.identityServices(widget.selector);
        if (mounted) setState(() => _snapshot = snapshot);
      } catch (_) {
        if (mounted) {
          setState(() {
            _snapshot = null;
            _failed = true;
          });
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([IdentityDocumentService? original]) async {
    if (_busy ||
        !_canManage ||
        _snapshot == null ||
        _snapshot!.pending ||
        original?.isProtected == true) {
      return;
    }
    final id = TextEditingController(
      text: original?.id ?? '${widget.selector}#',
    );
    final type = TextEditingController(text: original?.type ?? 'Website');
    final endpoint = TextEditingController(text: original?.endpoint ?? '');
    final accepted = await showAwikiGlassAlert<bool>(
      context,
      title: context.l10n.identityServicesTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppTextField(
            key: const Key('identity-service-id'),
            controller: id,
            label: context.l10n.identityServiceId,
            placeholder: context.l10n.identityServiceId,
          ),
          const SizedBox(height: 10),
          AppTextField(
            key: const Key('identity-service-type'),
            controller: type,
            label: context.l10n.identityServiceType,
            placeholder: context.l10n.identityServiceType,
          ),
          const SizedBox(height: 10),
          AppTextField(
            key: const Key('identity-service-endpoint'),
            controller: endpoint,
            label: context.l10n.identityServiceEndpoint,
            placeholder: context.l10n.identityServiceEndpoint,
            keyboardType: TextInputType.url,
          ),
        ],
      ),
      actions: <AwikiAlertAction<bool>>[
        AwikiAlertAction<bool>(label: context.l10n.commonCancel, value: false),
        AwikiAlertAction<bool>(
          key: const Key('identity-service-save'),
          label: context.l10n.commonSave,
          value: true,
          tone: AwikiPillTone.primary,
        ),
      ],
    );
    final proposal = IdentityDocumentService(
      id: id.text.trim(),
      type: type.text.trim(),
      endpoint: endpoint.text.trim(),
      serviceDid: original?.serviceDid,
      profiles: original?.profiles ?? const [],
      securityProfiles: original?.securityProfiles ?? const [],
    );
    id.dispose();
    type.dispose();
    endpoint.dispose();
    if (!mounted ||
        accepted != true ||
        !_canManage ||
        _snapshot?.pending != false) {
      return;
    }
    if (proposal.isProtected) {
      setState(() => _failed = true);
      return;
    }
    await _publish([
      for (final item in _snapshot!.services)
        if (!identical(item, original)) item,
      proposal,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(devicesProvider);
    final snapshot = _snapshot;
    final canEdit =
        _canManage && !_busy && snapshot != null && !snapshot.pending;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.identityServicesTitle),
      ),
      child: SafeArea(
        child: ListView(
          key: const Key('identity-services-page'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(context.l10n.identityServicesHint),
            const SizedBox(height: 16),
            if (_failed)
              Text(
                context.l10n.identityServicesFailed,
                key: const Key('identity-services-error'),
                style: TextStyle(color: context.awikiTheme.danger),
              ),
            if (_busy) const CupertinoActivityIndicator(),
            if (snapshot?.pending == true) ...[
              Text(
                context.l10n.identityServicesPending,
                key: const Key('identity-services-pending'),
              ),
              if (_canManage)
                AppPrimaryButton(
                  key: const Key('identity-services-resume'),
                  label: context.l10n.identityServicesResume,
                  onPressed: _busy ? null : () => _publish(null),
                ),
            ],
            for (final service
                in snapshot?.services ?? <IdentityDocumentService>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.type),
                    Text(
                      service.endpoint,
                      style: TextStyle(color: context.awikiTheme.secondaryText),
                    ),
                    if (!service.isProtected && _canManage)
                      Row(
                        children: [
                          CupertinoButton(
                            key: Key('identity-service-edit-${service.id}'),
                            onPressed: canEdit ? () => _edit(service) : null,
                            child: Text(context.l10n.identityServiceEdit),
                          ),
                          CupertinoButton(
                            key: Key('identity-service-delete-${service.id}'),
                            onPressed: canEdit
                                ? () => _publish(
                                    snapshot.services
                                        .where(
                                          (item) => !identical(item, service),
                                        )
                                        .toList(),
                                  )
                                : null,
                            child: Text(context.l10n.commonDelete),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (_canManage)
              AppPrimaryButton(
                key: const Key('identity-service-add'),
                label: context.l10n.identityServiceAdd,
                onPressed: canEdit ? () => _edit() : null,
              ),
            CupertinoButton(
              key: const Key('identity-services-refresh'),
              onPressed: _busy ? null : _load,
              child: Text(context.l10n.commonRefresh),
            ),
          ],
        ),
      ),
    );
  }
}
