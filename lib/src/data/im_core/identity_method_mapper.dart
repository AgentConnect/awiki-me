import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../domain/entities/identity_method.dart';

IdentityMethodCapabilities identityMethodCapabilitiesFromCore(
  core.IdentityMethodCapabilities value,
) => IdentityMethodCapabilities(
  method: switch (value.method) {
    core.DidMethod.wba => IdentityDidMethod.wba,
    core.DidMethod.web => IdentityDidMethod.web,
  },
  handleRecovery: value.handleRecovery,
  rootImport: value.rootImport,
  rootTransfer: value.rootTransfer,
  servicesUpdate: value.servicesUpdate,
);
