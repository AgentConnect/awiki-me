// [INPUT]: Secret-free device roles, authorization, Join, root-import, and revoke presentation states.
// [OUTPUT]: Localized labels and stable generic error copy.
// [POS]: Presentation-only mapping; no Core error body or control JSON is rendered.

import 'package:awiki_me/l10n/app_localizations.dart';

import '../../domain/entities/device_management.dart';
import 'devices_provider.dart';

String deviceRoleLabel(AppLocalizations l10n, DeviceRole role) =>
    switch (role) {
      DeviceRole.member => l10n.deviceRoleMember,
      DeviceRole.admin => l10n.deviceRoleAdmin,
    };

String deviceStatusLabel(AppLocalizations l10n, DeviceStatus status) =>
    switch (status) {
      DeviceStatus.active => l10n.deviceStatusActive,
      DeviceStatus.revoked => l10n.deviceStatusRevoked,
    };

String deviceManagementReadinessLabel(
  AppLocalizations l10n,
  DeviceManagementReadiness readiness,
) => switch (readiness) {
  DeviceManagementReadiness.adminAwaitingRoot =>
    l10n.deviceManagementAwaitingRoot,
  DeviceManagementReadiness.importing => l10n.deviceManagementImporting,
  DeviceManagementReadiness.ready => l10n.deviceManagementReady,
  DeviceManagementReadiness.failed => l10n.deviceManagementFailed,
};

String deviceJoinPhaseLabel(
  AppLocalizations l10n,
  DeviceJoinProgress progress,
) => switch (progress.phase) {
  DeviceJoinPhase.authorized => l10n.deviceJoinAuthorized,
  DeviceJoinPhase.cancelled => l10n.deviceJoinCancelled,
  DeviceJoinPhase.expired => l10n.deviceJoinExpired,
  DeviceJoinPhase.responsePrepared ||
  DeviceJoinPhase.responseVerified ||
  DeviceJoinPhase.approvalPrepared => l10n.deviceJoinSasTitle,
  _ => l10n.deviceJoinWaiting,
};

String deviceManagementErrorLabel(
  AppLocalizations l10n,
  DeviceManagementErrorKind error,
) => switch (error) {
  DeviceManagementErrorKind.unavailable => l10n.deviceJoinErrorUnavailable,
  DeviceManagementErrorKind.expired => l10n.deviceJoinExpired,
  DeviceManagementErrorKind.conflict => l10n.deviceJoinErrorConflict,
  DeviceManagementErrorKind.sasMismatch => l10n.deviceJoinErrorSas,
  DeviceManagementErrorKind.userPresenceDenied => l10n.deviceJoinErrorPresence,
  DeviceManagementErrorKind.sessionEstablishmentPending =>
    l10n.deviceRootTransferSessionPending,
  DeviceManagementErrorKind.protectedDevice => l10n.deviceRevokeProtected,
  DeviceManagementErrorKind.network => l10n.deviceJoinErrorNetwork,
  DeviceManagementErrorKind.failed => l10n.deviceJoinErrorFailed,
};
