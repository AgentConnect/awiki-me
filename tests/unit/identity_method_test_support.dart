import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/domain/entities/identity_method.dart';

export 'package:awiki_me/src/domain/entities/identity_method.dart';

const wbaMethodCapabilities = IdentityMethodCapabilities(
  method: IdentityDidMethod.wba,
  handleRecovery: true,
  rootImport: true,
  rootTransfer: true,
  servicesUpdate: false,
);
const webMethodCapabilities = IdentityMethodCapabilities(
  method: IdentityDidMethod.web,
  handleRecovery: false,
  rootImport: false,
  rootTransfer: false,
  servicesUpdate: true,
);
const coreWbaMethodCapabilities = core.IdentityMethodCapabilities(
  method: core.DidMethod.wba,
  handleRecovery: true,
  rootImport: true,
  rootTransfer: true,
  servicesUpdate: false,
);
const coreWebMethodCapabilities = core.IdentityMethodCapabilities(
  method: core.DidMethod.web,
  handleRecovery: false,
  rootImport: false,
  rootTransfer: false,
  servicesUpdate: true,
);
