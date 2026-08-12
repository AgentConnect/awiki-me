// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AWikiMe';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSend => 'Send';

  @override
  String get commonJoin => 'Join';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonPrevious => 'Previous';

  @override
  String get commonSave => 'Save';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonMoreActions => 'More actions';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopyDetails => 'Copy details';

  @override
  String get commonReject => 'Reject';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonRevoke => 'Revoke authorization';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonPleaseWait => 'Please wait...';

  @override
  String get startupFailureTitle => 'AWikiMe could not start';

  @override
  String startupFailureDiagnostic(String diagnosticCode) {
    return 'Diagnostic code: $diagnosticCode';
  }

  @override
  String get startupFailureCopyDiagnostics => 'Copy diagnostics';

  @override
  String get startupFailureExit => 'Exit';

  @override
  String get startupRecoveryAction => 'Reset this device and recover';

  @override
  String get startupRecoveryExplanation =>
      'The local credentials on this device cannot be read. You can retry, or reset local AWiki data and then use Device Join or Handle Recovery.';

  @override
  String get startupRecoveryConfirmTitle => 'Reset AWiki on this device?';

  @override
  String get startupRecoveryConfirmMessage =>
      'This removes all AWiki identities, tenants, messages, and settings stored locally on this device.';

  @override
  String get startupRecoveryConfirmHint =>
      'Online identities are not deleted, and other devices are not affected. You will need Device Join or Handle Recovery to use an existing identity here again.';

  @override
  String get startupRecoveryConfirmAction => 'Reset this device';

  @override
  String get startupRecoveryInProgress => 'Resetting local data...';

  @override
  String get startupRecoveryFailed =>
      'Local data could not be reset. You can retry or copy the diagnostic code for support.';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonError => 'Error';

  @override
  String get commonErrorDetails => 'Error details';

  @override
  String displayScaleValue(int percent) {
    return 'Display scale $percent%';
  }

  @override
  String get realtimeStatusConnecting => 'Connecting to message service...';

  @override
  String get realtimeStatusReconnecting =>
      'Message connection interrupted. Reconnecting...';

  @override
  String get realtimeStatusDisconnected =>
      'Message service is disconnected. Trying to recover.';

  @override
  String get onboardingLogin => 'Switch identity';

  @override
  String get localCredentialDeleteAction => 'Remove from this device';

  @override
  String get localCredentialDeleteConfirmTitle =>
      'Remove identity from this device?';

  @override
  String localCredentialDeleteConfirmContent(Object identity) {
    return 'Remove the local identity credential for $identity from this device?';
  }

  @override
  String get localCredentialDeleteConfirmHint =>
      'This removes the credential saved on this device. It does not delete the online identity or affect other devices. To use it here again, you must recover the identity or join the existing account.';

  @override
  String get onboardingRegister => 'Log in or register';

  @override
  String get onboardingImportCredential => 'Import identity credential';

  @override
  String get onboardingRefreshCredentials => 'Rescan local credentials';

  @override
  String get onboardingSendOtp => 'Send verification code';

  @override
  String onboardingResendOtpIn(Object seconds) {
    return 'Resend (${seconds}s)';
  }

  @override
  String get onboardingOtp => 'Verification code';

  @override
  String get onboardingOtpPlaceholder => 'Enter verification code';

  @override
  String get onboardingEmail => 'Email';

  @override
  String get onboardingEmailPlaceholder => 'Enter email address';

  @override
  String get onboardingSendActivationEmail => 'Send activation email';

  @override
  String onboardingResendActivationEmailIn(Object seconds) {
    return 'Resend (${seconds}s)';
  }

  @override
  String get onboardingEmailActivated => 'Email activated';

  @override
  String get onboardingCheckActivationStatus =>
      'I\'ve activated it, check status';

  @override
  String get onboardingHandle => 'Username';

  @override
  String get onboardingHandlePlaceholder => 'Username handle';

  @override
  String get onboardingNickname => 'Nickname';

  @override
  String get onboardingNicknamePlaceholder => 'Enter nickname';

  @override
  String get onboardingCompleteRegister => 'Continue';

  @override
  String get onboardingPhoneLoginOrRegisterAction => 'Log in / Register';

  @override
  String get onboardingCompleteEmailRegister => 'Complete registration';

  @override
  String get onboardingLoginRegisterHint =>
      'Phone automatically logs in to an existing Handle or registers a new one. Email currently only registers new Handles.';

  @override
  String get onboardingAuthMethod => 'Verification';

  @override
  String get onboardingAccountProfile => 'Account profile';

  @override
  String get onboardingPhone => 'Phone';

  @override
  String get onboardingPhonePlaceholder => 'Enter phone number';

  @override
  String get onboardingMissingLocalCredential =>
      'No local credential detected yet. Please rescan first.';

  @override
  String get onboardingLoadingServerInfo =>
      'Reading the sign-in methods supported by this server...';

  @override
  String get onboardingServerInfoLoadFailed =>
      'Could not read the sign-in methods supported by this server. Check the tenant address and try again.';

  @override
  String get onboardingRegistrationUnavailable =>
      'This server does not currently support in-app identity registration.';

  @override
  String get onboardingNoVerificationHint =>
      'This server does not require SMS or email verification. You can create a new identity directly.';

  @override
  String get registrationMethodUnavailable =>
      'This server does not support the selected registration method. Refresh and try again.';

  @override
  String get registrationVerificationInvalid =>
      'The verification code is incorrect. Check the code and try again.';

  @override
  String get registrationVerificationUnavailable =>
      'This verification code has expired or has already been used. Send a new code and try again.';

  @override
  String get tenantSwitcherLabel => 'Manage tenants';

  @override
  String get tenantManagementTitle => 'Tenants';

  @override
  String get tenantManagementSubtitle =>
      'Switch the backend and DID host used by this app.';

  @override
  String get tenantPrimaryAgentNote =>
      'Agent and Daemon features are available on approved AWiki realms.';

  @override
  String get tenantCreate => 'Add tenant configuration';

  @override
  String get tenantEdit => 'Edit tenant';

  @override
  String get tenantUse => 'Use';

  @override
  String get tenantCurrent => 'Current';

  @override
  String get tenantDefaultBadge => 'Default configuration';

  @override
  String get tenantName => 'Tenant name';

  @override
  String get tenantNamePlaceholder => 'Team or service name';

  @override
  String get tenantBackendBaseUrl => 'Backend base URL';

  @override
  String get tenantBackendBaseUrlPlaceholder => 'https://example.com';

  @override
  String get tenantDidHost => 'DID host';

  @override
  String get tenantDidHostPlaceholder => 'example.com';

  @override
  String get tenantCreateTitle => 'Add tenant configuration';

  @override
  String get tenantEditTitle => 'Edit tenant';

  @override
  String get tenantRenameTitle => 'Rename tenant';

  @override
  String get tenantSaveName => 'Save name';

  @override
  String get tenantSaving => 'Saving...';

  @override
  String get tenantDeleteTitle => 'Delete tenant';

  @override
  String tenantDeleteContent(Object tenantName) {
    return 'Delete $tenantName? Local data remains on this device, but this tenant will no longer appear in the switcher.';
  }

  @override
  String get tenantCannotEditDefault =>
      'The default AWiki tenant cannot be edited. Add a tenant configuration for another backend.';

  @override
  String get tenantCannotEditWithData =>
      'This tenant already has local data. You can rename it, but the backend URL and DID host cannot be changed.';

  @override
  String get tenantDidHostImmutable =>
      'The DID host is bound to this tenant\'s local identities and storage scope. It cannot be changed for an existing tenant; add a new tenant configuration instead.';

  @override
  String get tenantDataStateCheckFailed =>
      'The local data state for this tenant could not be confirmed. To protect existing data, only the name can be changed for now. Try again later.';

  @override
  String get tenantCannotDeleteDefault =>
      'The default AWiki tenant cannot be deleted.';

  @override
  String get tenantCannotDeleteActive =>
      'Switch to another tenant before deleting this one.';

  @override
  String get tenantValidationNameInvalid =>
      'Enter 1-40 visible characters for the local display name. Invisible control characters are not allowed.';

  @override
  String get tenantValidationBackendInvalid =>
      'Enter a valid http or https backend URL without query or fragment.';

  @override
  String get tenantValidationDidHostInvalid =>
      'Enter a valid DID host, such as example.com.';

  @override
  String get tenantValidationNameExists =>
      'A tenant with this name already exists.';

  @override
  String get tenantValidationEndpointExists =>
      'A tenant with this backend and DID host already exists.';

  @override
  String get tenantValidationHasData =>
      'This tenant already has local data. Only the name can be changed; add a tenant configuration for a different backend or DID host.';

  @override
  String get tenantNotFound => 'Tenant not found.';

  @override
  String get tenantOperationFailed =>
      'Tenant operation failed. Please try again.';

  @override
  String get onboardingIncompletePhoneTitle => 'Incomplete phone number';

  @override
  String get onboardingIncompletePhoneContent =>
      'Please enter a valid phone number.';

  @override
  String get onboardingMissingOtpTitle => 'Verification code missing';

  @override
  String get onboardingMissingOtpContent =>
      'Enter the verification code before continuing.';

  @override
  String get onboardingMissingEmailTitle => 'Email missing';

  @override
  String get onboardingMissingEmailContent =>
      'Please enter your email address.';

  @override
  String get onboardingNotActivatedTitle => 'Not activated yet';

  @override
  String get onboardingNotActivatedContent =>
      'Please finish email activation and check the status first.';

  @override
  String get onboardingInvalidHandleTitle => 'Invalid handle';

  @override
  String get onboardingInvalidHandleContent =>
      'Only lowercase letters, numbers, and hyphens are allowed, 2-32 characters.';

  @override
  String get onboardingMissingNicknameTitle => 'Nickname missing';

  @override
  String get onboardingMissingNicknameContent => 'Please enter a nickname.';

  @override
  String get onboardingMacHeroPrefix => 'Connect your ';

  @override
  String get onboardingMacHeroHighlight => 'Agent';

  @override
  String get onboardingMacHeroSuffix => ' world';

  @override
  String get onboardingMacSubtitle =>
      'Securely connect people, Agents, and organizations for smarter collaboration and faster decisions.';

  @override
  String get onboardingMacFeatureSecureTitle => 'Secure';

  @override
  String get onboardingMacFeatureSecureSubtitle =>
      'Enterprise-grade protection';

  @override
  String get onboardingMacFeatureCollaborateTitle => 'Collaborative';

  @override
  String get onboardingMacFeatureCollaborateSubtitle =>
      'Human-Agent teamwork with smooth information flow';

  @override
  String get onboardingMacFeatureControlTitle => 'Controlled access';

  @override
  String get onboardingMacFeatureControlSubtitle =>
      'Fine-grained permissions for safer data';

  @override
  String get onboardingMacChipRequirementsAgent => 'Requirements Agent';

  @override
  String get onboardingMacChipRequirementsAgentCompact => 'Requirements';

  @override
  String get onboardingMacChipPlanningAgent => 'Planning Agent';

  @override
  String get onboardingMacChipPlanningAgentCompact => 'Planning';

  @override
  String get onboardingMacChipCodingAgent => 'Coding Agent';

  @override
  String get onboardingMacChipCodingAgentCompact => 'Coding';

  @override
  String get onboardingMacChipUiDesignAgent => 'UI Design Agent';

  @override
  String get onboardingMacChipUiDesignAgentCompact => 'UI Design';

  @override
  String get onboardingMacVerified => 'Verified';

  @override
  String get onboardingMacOnline => 'Online';

  @override
  String get onboardingCredentialsField => 'Identity credentials';

  @override
  String get onboardingNoLocalCredentialSaved =>
      'No saved identity credentials on this device';

  @override
  String get secureMessagingClient => 'Secure messaging client';

  @override
  String get shellNavMessages => 'Messages';

  @override
  String get shellNavAgents => 'Agents';

  @override
  String get shellNavContacts => 'Contacts';

  @override
  String get shellNavTasks => 'Tasks';

  @override
  String get shellNavWorkspace => 'Workspace';

  @override
  String get shellNavSettings => 'Settings';

  @override
  String get shellNavMe => 'Me';

  @override
  String get shellTasksPlaceholderTitle => 'Tasks';

  @override
  String get shellTasksPlaceholderSubtitle =>
      'Task views are coming soon. Current task status is shown in conversations and identity cards.';

  @override
  String get shellWorkspacePlaceholderTitle => 'Workspace';

  @override
  String get shellWorkspacePlaceholderSubtitle =>
      'The workspace module is coming soon.';

  @override
  String get conversationsTitle => 'Messages';

  @override
  String get conversationsNoMessagePreview => 'No messages yet';

  @override
  String get conversationsEmptyTitle => 'No messages yet';

  @override
  String get conversationsEmptySubtitle =>
      'Follow a contact or join a group chat to get started.';

  @override
  String get conversationsRecentTitle => 'Recent conversations';

  @override
  String get conversationsSearchPlaceholder => 'Search conversations';

  @override
  String get conversationsNoResultsTitle => 'No matching conversations';

  @override
  String get conversationsNoResultsSubtitle => 'Try another keyword';

  @override
  String get conversationsDeleteTitle => 'Delete conversation';

  @override
  String get conversationsDeleteContent =>
      'Remove this conversation from recents';

  @override
  String get conversationsDeleteClearHistory => 'Also clear message history';

  @override
  String get conversationsDeleteClearHistoryUnavailable =>
      'Single-conversation history clearing requires Core support';

  @override
  String get conversationsSwipeDelete => 'Delete';

  @override
  String conversationsUnreadTag(Object count) {
    return '$count unread';
  }

  @override
  String get conversationsMentionMeTag => '@me';

  @override
  String get conversationsDraftTag => 'Draft';

  @override
  String conversationsAttachmentPreview(Object name) {
    return 'Attachment: $name';
  }

  @override
  String get conversationsDeletedAgentBadge => 'Agent deleted';

  @override
  String get conversationsNewMessages => 'New messages';

  @override
  String get conversationPeerBadgeGroup => 'Group';

  @override
  String get conversationPeerBadgeAi => 'AI';

  @override
  String get conversationPeerChatBadgeMyAgent => 'My agent';

  @override
  String get conversationPeerChatBadgeAgent => 'Agent';

  @override
  String get conversationPeerTypeGroup => 'Group chat';

  @override
  String get conversationPeerTypeAgent => 'Agent';

  @override
  String get conversationPeerTypeUser => 'User';

  @override
  String get conversationPeerOwnerGroup => 'AWiki group';

  @override
  String get conversationPeerOwnerMyRuntimeAgent => 'Local Runtime Agent';

  @override
  String get conversationPeerOwnerAgent => 'AWiki Agent';

  @override
  String get conversationPeerOwnerUser => 'AWiki user';

  @override
  String get conversationInfoTitle => 'Conversation info';

  @override
  String get conversationIdentityStatus => 'Identity status:';

  @override
  String get conversationIdentityVerified => 'Verified';

  @override
  String get conversationOwnerLabel => 'Owner:';

  @override
  String get conversationTypeLabel => 'Type:';

  @override
  String get conversationCapabilitiesTitle => 'Capabilities';

  @override
  String get conversationCapabilitySendMessage => 'Send messages';

  @override
  String get conversationCapabilityViewProfile => 'View profile';

  @override
  String get conversationCapabilitySecureConnection => 'Secure connection';

  @override
  String get conversationCapabilityHistory => 'Conversation history';

  @override
  String get conversationStatusTitle => 'Conversation status';

  @override
  String get conversationUnreadMessagesLabel => 'Unread:';

  @override
  String conversationUnreadMessagesValue(int count) {
    return '$count unread';
  }

  @override
  String get conversationLatestPreviewLabel => 'Latest preview:';

  @override
  String get conversationConnectionStatusLabel => 'Connection:';

  @override
  String get conversationConnectionEstablished => 'Established';

  @override
  String get conversationBackToChat => 'Back to chat';

  @override
  String get friendsTitle => 'Contacts';

  @override
  String get friendsSearchPlaceholder => 'Search contacts';

  @override
  String get friendsSearchGroupsPlaceholder => 'Search groups';

  @override
  String get friendsTabAll => 'All';

  @override
  String get friendsTabFollowing => 'Following';

  @override
  String get friendsTabFollowers => 'Followers';

  @override
  String get friendsTabGroups => 'Groups';

  @override
  String get friendsAllEmpty => 'No contacts yet.';

  @override
  String get friendsNoResults => 'No matching contacts found.';

  @override
  String get friendsMessage => 'Message';

  @override
  String get friendsFollowBack => 'Follow back';

  @override
  String get friendsGroups => 'Groups';

  @override
  String get friendsGroupsSubtitle => 'All group chats you have joined';

  @override
  String get friendsFollowing => 'Following';

  @override
  String get friendsFollowers => 'Followers';

  @override
  String get friendsViewAll => 'View all';

  @override
  String get friendsFollow => 'Follow';

  @override
  String get friendsUnfollow => 'Unfollow';

  @override
  String get friendsFollowingEmpty => 'You are not following anyone yet.';

  @override
  String get friendsFollowersEmpty => 'No new followers yet.';

  @override
  String get friendsUnfollowTitle => 'Unfollow';

  @override
  String get friendsUnfollowMessage =>
      'After unfollowing, this contact will be removed from Following.';

  @override
  String get profileMeTitle => 'Me';

  @override
  String get profileMyInformationTitle => 'My info';

  @override
  String get profileIdentitySectionTitle => 'Identity';

  @override
  String get profileIdentityCardSubtitle =>
      'Complete details for trusted collaboration';

  @override
  String get profileSettingsSubtitle => 'Account, devices, and app preferences';

  @override
  String get profileFollowers => 'Followers';

  @override
  String get profileFollowing => 'Following';

  @override
  String get profileGroups => 'Groups';

  @override
  String get profileEmpty => 'No profile yet';

  @override
  String get profileEditTitle => 'Edit profile';

  @override
  String get profileBioPlaceholder => 'Bio';

  @override
  String get profileBioHint => 'Introduce yourself';

  @override
  String get profileAvatarLabel => 'Avatar';

  @override
  String get profileAvatarChange => 'Change';

  @override
  String get profileTagsLabel => 'Tags';

  @override
  String get profileTagsLimit => 'Up to 5 tags';

  @override
  String get profileTagsPlaceholder => 'Tags, separated by commas';

  @override
  String get profileTagAdd => 'Add';

  @override
  String get profileTagInputPlaceholder => 'Enter tag';

  @override
  String profileTagRemove(String tag) {
    return 'Remove $tag';
  }

  @override
  String get profileHomepageLabel => 'Homepage';

  @override
  String get profileOpenHomepage => 'Open homepage';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccountDevicesSection => 'Account & devices';

  @override
  String get settingsAppSection => 'App';

  @override
  String get settingsSecuritySection => 'Security';

  @override
  String get settingsDevices => 'Devices';

  @override
  String get settingsDevicesSubtitle =>
      'Review authorized devices and approve new ones';

  @override
  String get devicesTitle => 'Device management';

  @override
  String get devicesAuthorizedTitle => 'Authorized devices';

  @override
  String get devicesPendingTitle => 'Pending approval';

  @override
  String get devicesEmpty => 'No device information';

  @override
  String get devicesPendingEmpty => 'No pending approval requests';

  @override
  String get deviceCurrent => 'Current device';

  @override
  String get deviceRoleMember => 'Member device';

  @override
  String get deviceRoleAdmin => 'Admin device';

  @override
  String get deviceStatusActive => 'Active';

  @override
  String get deviceStatusRevoked => 'Revoked';

  @override
  String get deviceManagementReady => 'Can manage devices';

  @override
  String get deviceManagementPending => 'Waiting for management readiness';

  @override
  String get deviceManagementAwaitingRoot => 'Admin awaiting root key';

  @override
  String get deviceManagementActionDisabled =>
      'A management-ready admin device is required';

  @override
  String get deviceRootTransferGrantManagement =>
      'Continue granting management access';

  @override
  String get deviceRootTransferPreparing => 'Preparing secure transfer…';

  @override
  String get deviceRootTransferConfirm => 'Confirm and send root key';

  @override
  String get deviceRootTransferSending => 'Sending root key…';

  @override
  String deviceRootTransferTarget(
    String deviceId,
    String signingKeyId,
    String e2eeKeyId,
  ) {
    return 'Target device: $deviceId\nSigning key: $signingKeyId\nEnd-to-end encryption key: $e2eeKeyId';
  }

  @override
  String get deviceRootTransferSent => 'Root key sent';

  @override
  String get deviceRootTransferFailed =>
      'The device joined, but it did not receive management access. Please try again later.';

  @override
  String get deviceRootTransferPresenceReason =>
      'Confirm secure root-key transfer';

  @override
  String get deviceRevokeAction => 'Revoke';

  @override
  String get deviceRevokeSubmitting => 'Revoking device…';

  @override
  String get deviceRevokeConfirmingAction => 'Confirm again';

  @override
  String get deviceRevokeSucceeded => 'Device revoked.';

  @override
  String get deviceRevokeSucceededGroupsSyncing =>
      'Device revoked. Affected groups are synchronizing their security state.';

  @override
  String get deviceRevokeOutcomeUnknown =>
      'The revocation result is not confirmed yet. Refresh the device list.';

  @override
  String get deviceRevokeRejected =>
      'The device could not be revoked. Try again later.';

  @override
  String get deviceRevokeConfirmTitle => 'Revoke this device?';

  @override
  String deviceRevokeConfirmDetail(String deviceId) {
    return 'Revoke $deviceId permanently. It will lose future access, but data already obtained cannot be erased. This action cannot be undone.';
  }

  @override
  String get deviceRevokeConfirmAction => 'Revoke permanently';

  @override
  String get deviceRevokePresenceReason =>
      'Confirm permanent device revocation';

  @override
  String get deviceRevokeProtectionHint =>
      'The current device cannot revoke itself, and the final ready management device is always protected.';

  @override
  String get deviceRevokeProtected =>
      'This device is protected or you are not using a ready management device. The current device and final ready management device cannot be revoked.';

  @override
  String get deviceReviewAction => 'Review and verify';

  @override
  String get deviceJoinEntry => 'Add this device to an existing account';

  @override
  String get deviceJoinEntrySubtitle =>
      'An existing admin device must verify the 6-digit code shown on both devices';

  @override
  String get onboardingExistingHandleTitle => 'This Handle already exists';

  @override
  String get onboardingExistingHandleMessage =>
      'Choose whether to add this device to the existing identity or recover the Handle with its bound phone and a dedicated recovery code.';

  @override
  String get onboardingExistingHandleJoinOnlyMessage =>
      'This server does not currently provide Handle Recovery. You can still add this device to the existing identity, or cancel and try again later.';

  @override
  String get deviceJoinTitle => 'Add a new device';

  @override
  String get deviceJoinHandle => 'Existing Handle';

  @override
  String get deviceJoinPhone => 'Linked phone number';

  @override
  String get deviceJoinOtp => 'SMS verification code';

  @override
  String get deviceJoinSendOtp => 'Send code';

  @override
  String deviceJoinResendOtpIn(int seconds) {
    return 'Resend (${seconds}s)';
  }

  @override
  String get deviceJoinStart => 'Start pairing';

  @override
  String get deviceJoinWaiting => 'Waiting for an admin device';

  @override
  String get deviceJoinRefresh => 'Refresh status';

  @override
  String get deviceJoinSasTitle => '6-digit verification code';

  @override
  String get deviceJoinSasHint =>
      'Confirm that both devices independently show exactly the same digits. The code is never relayed by the server.';

  @override
  String get deviceJoinApprovalTitle => 'Confirm new device';

  @override
  String get deviceJoinSasMatches =>
      'I confirmed that both devices show the same 6-digit code';

  @override
  String get deviceJoinRequestReady => 'Ready to start verification';

  @override
  String get deviceJoinStartVerification => 'Start verification';

  @override
  String get deviceJoinClaimedByOther =>
      'Another management device is handling this request';

  @override
  String get deviceJoinReject => 'Reject request';

  @override
  String get deviceJoinRejected => 'Device request rejected';

  @override
  String get deviceJoinSasMismatch => 'Codes do not match';

  @override
  String deviceJoinFingerprint(String fingerprint) {
    return 'Key fingerprint: $fingerprint';
  }

  @override
  String deviceJoinRequestWindow(String issuedAt, String expiresAt) {
    return 'Requested $issuedAt; expires $expiresAt';
  }

  @override
  String get deviceJoinApprove => 'Confirm and authorize';

  @override
  String get deviceJoinCancel => 'Cancel pairing';

  @override
  String get deviceJoinAuthorized => 'Device added';

  @override
  String get deviceJoinCancelled => 'Device pairing cancelled';

  @override
  String get deviceJoinExpired => 'Device pairing expired. Start again.';

  @override
  String get deviceJoinActivating => 'Activating this device...';

  @override
  String get deviceJoinActivationRetry => 'Retry device activation';

  @override
  String get deviceJoinUserPresenceReason =>
      'Confirm authorization of a new device';

  @override
  String get deviceJoinErrorUnavailable =>
      'Multi-device support is not available';

  @override
  String get deviceJoinErrorConflict =>
      'The state changed. Refresh and try again.';

  @override
  String get deviceJoinErrorSas =>
      'The verification code state did not match. Authorization stopped.';

  @override
  String get deviceJoinErrorPresence =>
      'System authentication was not completed. The device was not authorized.';

  @override
  String get deviceJoinErrorNetwork =>
      'Network connection failed. Try again later.';

  @override
  String deviceJoinOtpRateLimited(int seconds) {
    return 'Verification codes are being sent too frequently. Try again in $seconds seconds.';
  }

  @override
  String get deviceJoinErrorFailed =>
      'Device operation failed. Refresh and try again.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow system';

  @override
  String get settingsLanguageSystemSubtitle => 'Use device language';

  @override
  String get settingsLanguageZhHans => '简体中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsDisplayAndWindow => 'Display & window';

  @override
  String get settingsDisplayScale => 'Interface scale';

  @override
  String get settingsDisplayScaleReset => 'Reset to 100%';

  @override
  String get settingsWindowPlacementReset => 'Reset window size and position';

  @override
  String get settingsPushNotification => 'Push notifications';

  @override
  String get settingsCurrentVersion => 'Current version';

  @override
  String settingsCurrentVersionValue(Object version) {
    return 'Current version: $version';
  }

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get settingsViewReleaseNotes => 'View release notes';

  @override
  String get settingsInstallUpdate => 'Install update';

  @override
  String settingsInstallUpdateVersion(Object version) {
    return 'Install version $version';
  }

  @override
  String get settingsDownloadUpdate => 'Download update';

  @override
  String settingsDownloadUpdateVersion(Object version) {
    return 'Download version $version';
  }

  @override
  String settingsUpdateAvailable(Object version) {
    return 'New version available: $version';
  }

  @override
  String get settingsAlreadyLatestVersion => 'You\'re on the latest version';

  @override
  String get settingsUpdateStatusLoading => 'Loading version details...';

  @override
  String get settingsUpdateStatusChecking => 'Checking for updates...';

  @override
  String get settingsUpdateStatusDownloading => 'Downloading update...';

  @override
  String get settingsUpdateStatusInstalling => 'Preparing installation...';

  @override
  String get settingsUpdateStatusFailed =>
      'Update check failed. Please try again later.';

  @override
  String settingsUpdateReleaseNotesVersion(Object version) {
    return 'View release notes for $version';
  }

  @override
  String get settingsUpdateOpenGitHubHistory =>
      'Open the download page to browse release history';

  @override
  String get settingsUpdateOpenGitHubDownload =>
      'Open the download page to get the current build';

  @override
  String get settingsExportCredential => 'Export identity credential';

  @override
  String settingsExportCurrentCredential(Object credentialName) {
    return 'Export current credential: $credentialName';
  }

  @override
  String get settingsNoCredentialToExport =>
      'No signed-in credential available to export';

  @override
  String get messageSyncStatusTitle => 'Message sync';

  @override
  String get messageSyncStatusIdle => 'Up to date';

  @override
  String get messageSyncStatusSyncing => 'Syncing messages…';

  @override
  String get messageSyncStatusRecoveryRequired =>
      'A safe message recovery is required. Retrying automatically…';

  @override
  String get messageSyncStatusRecovering =>
      'Recovering recent messages and current read state…';

  @override
  String get messageSyncStatusRetrying =>
      'The message service is temporarily unavailable. Retrying automatically…';

  @override
  String get messageSyncStatusRetryableFailure =>
      'New messages cannot be synced right now. Check your network and retry.';

  @override
  String get messageSyncStatusProjectionRefreshFailed =>
      'Messages were synced, but the list could not refresh. Retry to reload it.';

  @override
  String get messageSyncStatusAuthRevoked =>
      'Your sign-in expired or this device is no longer authorized. Sign in again.';

  @override
  String get authRevokedDialogTitle => 'Account sign-in expired';

  @override
  String get authRevokedDialogMessage =>
      'This account may have been reset on another device. Sign in again.';

  @override
  String get messageSyncRetryAction => 'Retry';

  @override
  String get messageSyncReloadAction => 'Reload';

  @override
  String get messageSyncReauthenticateAction => 'Sign in again';

  @override
  String get settingsRecoverHandleDid => 'Recover Handle DID';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsLogoutSubtitle =>
      'Clear local sign-in state and return to the sign-in page';

  @override
  String get settingsDeleteCredential => 'Sign out and delete current data';

  @override
  String settingsDeleteCurrentCredential(Object credentialName) {
    return 'Delete current local data: $credentialName';
  }

  @override
  String get settingsDeleteCredentialFallback =>
      'Sign out and delete current account data';

  @override
  String get settingsLogoutConfirmTitle => 'Log out';

  @override
  String get settingsLogoutConfirmContent =>
      'Are you sure you want to log out of the current account?';

  @override
  String get settingsDeleteCredentialConfirmTitle =>
      'Sign out and delete current data';

  @override
  String settingsDeleteCredentialConfirmContent(Object credentialName) {
    return 'Sign out of $credentialName and permanently delete its credentials, messages, groups, agents, drafts, preferences, and end-to-end encryption data saved on this device';
  }

  @override
  String get settingsDeleteCredentialConfirmHint =>
      'This does not delete the online identity or affect other devices. Deleted local history and end-to-end encryption keys cannot be restored by recovery or device join.';

  @override
  String get settingsDeleteCredentialConfirmAction =>
      'Sign out and delete data';

  @override
  String get quickActionsTitle => 'More actions';

  @override
  String get quickActionStartConversation => 'New message';

  @override
  String get quickActionCreateGroup => 'Create group chat';

  @override
  String get quickActionJoinGroup => 'Join group chat';

  @override
  String get quickActionFollowContact => 'Follow contact';

  @override
  String get followContactTitle => 'Follow contact';

  @override
  String get followContactPlaceholder => 'Enter Handle or DID';

  @override
  String get followContactAlreadyFollowing => 'Already following';

  @override
  String get followContactSucceeded => 'Followed';

  @override
  String get identityStartConversationSubtitle =>
      'Enter a handle, DID, or Agent address, then confirm the identity to start a trusted conversation.';

  @override
  String get identityStartConversationAction => 'Start chat';

  @override
  String get identityStartConversationNotice =>
      'Messages will be sent through a verified DID connection. Confirm external identities carefully before first contact.';

  @override
  String get identityFollowContactTitle => 'Follow contact / Agent';

  @override
  String get identityFollowContactSubtitle =>
      'Enter a handle or DID, then confirm the identity to follow it.';

  @override
  String get identityFollowContactAction => 'Follow';

  @override
  String get identityFollowContactNotice =>
      'Confirm the identity to follow this contact or Agent.';

  @override
  String get identityInputSemantics => 'Enter a handle or DID';

  @override
  String get identityInputPlaceholder => 'Enter @handle, DID, or Agent address';

  @override
  String get identitySearchLabel => 'Resolve identity';

  @override
  String get identityResolving => 'Resolving...';

  @override
  String get identitySubmitting => 'Processing...';

  @override
  String get identityQueryRequired => 'Enter a handle or DID.';

  @override
  String get identityResolveFailed =>
      'Identity not found. Check the handle or DID and try again.';

  @override
  String get identityInvalidContact =>
      'This contact identity is invalid and cannot be opened.';

  @override
  String get identityMissingDid => 'Identity resolution returned no DID.';

  @override
  String get identityVerified => 'Verified';

  @override
  String get identityTypeLabel => 'Type';

  @override
  String get identityRelationshipLabel => 'Relation';

  @override
  String get identityBioLabel => 'Bio';

  @override
  String get identityTypeAgent => 'Agent';

  @override
  String get identityTypeUser => 'User';

  @override
  String get identityTypeRuntimeAgent => 'Runtime Agent';

  @override
  String get identityTypeSkillAgent => 'Skill Agent';

  @override
  String get identityTypeDaemon => 'Daemon';

  @override
  String get identityTypeGroup => 'Group';

  @override
  String get identityTypeUnknown => 'Identity';

  @override
  String get identityAddGroupMemberTitle => 'Add group members';

  @override
  String get identityAddGroupMemberSubtitle =>
      'Enter a user or Agent handle / DID, then confirm the identity to add it to the group.';

  @override
  String get identityAddGroupMemberAction => 'Add';

  @override
  String get identityAddGroupMemberNotice =>
      'Confirm this is the identity you want to add to the group.';

  @override
  String get identityClearInput => 'Clear input';

  @override
  String get identitySearchNameHandleDid => 'Search name, handle, or DID';

  @override
  String get groupListTitle => 'Group';

  @override
  String get groupListEmpty =>
      'No groups yet. Create one or join with a Group DID.';

  @override
  String get groupListLoading => 'Loading group data...';

  @override
  String get groupJoinDialogTitle => 'Join with a Group DID';

  @override
  String get groupJoinDialogPlaceholder => 'Enter the group DID';

  @override
  String get groupIdentityModeLabel => 'Join identity';

  @override
  String get groupIdentityHandle => 'Handle';

  @override
  String get groupIdentityDidOnly => 'DID';

  @override
  String groupIdentityCurrentHandle(String handle) {
    return 'Handle: $handle';
  }

  @override
  String get groupNoDescription => 'No group description yet';

  @override
  String groupMemberCount(int count) {
    return '$count members';
  }

  @override
  String groupMemberCountCompact(int count) {
    return '$count members';
  }

  @override
  String groupIdLabel(Object groupId) {
    return 'Group DID: $groupId';
  }

  @override
  String get groupEnterChat => 'Enter group chat';

  @override
  String get groupRefreshSnapshot => 'Refresh group details and members';

  @override
  String get groupMembersTitle => 'Members';

  @override
  String get groupMembersEmpty =>
      'No member snapshot yet. Refresh group details and members first.';

  @override
  String get groupCreateTitle => 'Create group chat';

  @override
  String get groupCreateAction => 'Create';

  @override
  String get groupRecoveryCompleted => 'Group identity restored';

  @override
  String groupRecoveryPending(int count) {
    return 'Identity restored; $count group updates are pending';
  }

  @override
  String groupRecoveryBlocked(int count) {
    return 'Identity restored; $count group updates need attention';
  }

  @override
  String get groupRecoveryStatusUnavailable =>
      'Identity restored; group updates will retry later';

  @override
  String get groupRecoveryMembershipLayer => 'Membership';

  @override
  String get groupRecoveryEncryptionLayer => 'Encryption';

  @override
  String get groupRecoveryPhaseCompleted => 'Completed';

  @override
  String get groupRecoveryPhasePending => 'Pending';

  @override
  String get groupRecoveryPhaseBlocked => 'Blocked';

  @override
  String get groupRecoveryRetry => 'Retry group recovery';

  @override
  String get groupEncryptionPreparingTitle => 'Synchronizing group encryption';

  @override
  String get groupEncryptionPreparingDetail =>
      'This group is synchronizing its security state. Sending is paused until it completes.';

  @override
  String get groupEncryptionNeedsRetryTitle => 'Group encryption needs retry';

  @override
  String get groupEncryptionNeedsRetryDetail =>
      'Retry the repair on a management device that holds the current group security state.';

  @override
  String get groupEncryptionReadyTitle => 'Group encryption ready';

  @override
  String get groupEncryptionReadyDetail =>
      'This device has independent encryption state for this group and can securely receive new messages.';

  @override
  String get groupEncryptionUnavailableTitle => 'Group encryption unavailable';

  @override
  String get groupEncryptionUnavailableDetail =>
      'This environment does not currently provide the group encryption capability required by this device.';

  @override
  String get groupEncryptionRetry => 'Retry';

  @override
  String get groupFieldName => 'Name';

  @override
  String get groupFieldNamePlaceholder => 'Enter group chat name';

  @override
  String get groupCreating => 'Creating group...';

  @override
  String get groupAddMembers => 'Add members';

  @override
  String get groupRefreshMembers => 'Refresh members';

  @override
  String get groupDetails => 'View group details';

  @override
  String get groupRemoveMember => 'Remove member';

  @override
  String get groupInviteDialogSubtitle =>
      'Search local identities, or enter a handle / DID to resolve a new identity.';

  @override
  String get groupInviteShowMore => 'Show more';

  @override
  String get groupInviteAdding => 'Adding...';

  @override
  String get groupInviteAddFailed =>
      'Could not add this identity. Try again later.';

  @override
  String groupInviteConfirmCount(int count) {
    return 'Add ($count)';
  }

  @override
  String get groupInviteCandidates => 'Available identities';

  @override
  String get groupInviteSearchResults => 'Search results';

  @override
  String get groupInviteSelectHint =>
      'Select one or more identities, then confirm once to add them.';

  @override
  String get groupInviteNoLocalCandidates =>
      'No local identities available to invite.';

  @override
  String get groupInviteIdentityUnavailable =>
      'This identity has been deleted or is not currently invitable.';

  @override
  String get groupInviteSkillAgentUnavailable =>
      'Skill Agents cannot join groups yet';

  @override
  String get groupInviteSkillAgentCapabilityMissing =>
      'This Skill Agent version cannot join groups';

  @override
  String get groupInviteAgentKindUnavailable =>
      'This type of agent cannot join groups yet';

  @override
  String get groupInviteNoMatches =>
      'No local identities matched. Try resolving a handle or DID.';

  @override
  String get groupInviteAlreadyInGroup => 'Already in group';

  @override
  String get groupInviteUnnamedAgent => 'Unnamed agent';

  @override
  String get groupInviteSourceMyAgents => 'My agents';

  @override
  String get groupInviteSourceFollowing => 'Following';

  @override
  String get groupInviteSourceFollowers => 'Followers';

  @override
  String get groupInviteSourceRecent => 'Recent conversations';

  @override
  String get groupInviteSourceResolved => 'Resolved identity';

  @override
  String groupRemoveMemberContent(Object memberTitle) {
    return 'After removing $memberTitle, they will no longer be able to send messages in this group.';
  }

  @override
  String get chatUnknownUser => 'Unknown';

  @override
  String get chatConversationUntitled => 'Untitled conversation';

  @override
  String get chatHeaderGroup => 'GROUP';

  @override
  String get chatHeaderOnline => 'ONLINE';

  @override
  String get chatInputPlaceholder => 'Type a message...';

  @override
  String get chatDeletedAgentDisabled =>
      'This agent has been deleted. You can no longer send messages.';

  @override
  String get chatGroupLeftDisabled =>
      'You are no longer in this group and cannot send messages.';

  @override
  String get chatGroupSendDisabled =>
      'This group is temporarily unavailable for sending messages.';

  @override
  String get chatAgentAwaitingReceipt =>
      'Sent. Waiting for the agent to receive it...';

  @override
  String get chatAgentAwaitingOnline =>
      'Sent. Waiting for the agent to come online...';

  @override
  String get chatAgentAwaitingResponse =>
      'Sent. The agent has not responded yet.';

  @override
  String get chatAgentProcessing => 'Agent is processing...';

  @override
  String get chatAgentStillProcessing =>
      'Agent is still processing. Refresh later to check the result.';

  @override
  String get chatAgentExternalServiceWorking =>
      'Agent is using an external service...';

  @override
  String get chatAgentExternalServiceDelayed =>
      'The external service is responding slowly. The agent is still waiting or retrying...';

  @override
  String get chatAgentExternalServiceResumed =>
      'The external service recovered. The agent is continuing...';

  @override
  String chatSubjectProcessing(Object subject) {
    return '$subject is processing...';
  }

  @override
  String chatSubjectAwaitingReceipt(Object subject) {
    return 'Sent. Waiting for $subject to receive it...';
  }

  @override
  String chatSubjectAwaitingOnline(Object subject) {
    return 'Sent. Waiting for $subject to come online...';
  }

  @override
  String chatSubjectAwaitingResponse(Object subject) {
    return 'Sent. $subject has not responded yet.';
  }

  @override
  String chatSubjectExternalServiceWorking(Object subject) {
    return '$subject is using an external service...';
  }

  @override
  String chatSubjectExternalServiceDelayed(Object subject) {
    return 'The external service is responding slowly. $subject is still waiting or retrying...';
  }

  @override
  String chatSubjectExternalServiceResumed(Object subject) {
    return 'The external service recovered. $subject is continuing...';
  }

  @override
  String chatSubjectStillProcessing(Object subject) {
    return '$subject is still processing. Refresh later to check the result.';
  }

  @override
  String get chatAgentSubject => 'Agent';

  @override
  String chatAgentCountSubject(int count) {
    return '$count agents';
  }

  @override
  String get chatAddAttachment => 'Add attachment';

  @override
  String get chatAddEmoji => 'Choose emoji';

  @override
  String get chatCaptureScreenshot => 'Capture screenshot';

  @override
  String get screenshotPermissionRequired =>
      'Screen Recording permission is not active. Allow the current AWiki Me app under Screen & System Audio Recording in System Settings, then quit and reopen it.';

  @override
  String get chatRemoveAttachment => 'Remove attachment';

  @override
  String get chatViewAttachment => 'View attachment';

  @override
  String get chatAttachmentFileFallback => 'File';

  @override
  String get chatLoadingMentionCandidates => 'Loading mention candidates...';

  @override
  String get mentionCandidateBadgeUser => 'User';

  @override
  String get mentionCandidateBadgeAgent => 'Agent';

  @override
  String get mentionCandidateBadgeUnknown => 'Unknown';

  @override
  String get mentionSelectorAllSurface => '@everyone';

  @override
  String get mentionSelectorHumansSurface => '@users';

  @override
  String get mentionSelectorAgentsSurface => '@agents';

  @override
  String get mentionSelectorAllSubtitle => 'Notify everyone in this group';

  @override
  String get mentionSelectorHumansSubtitle => 'Notify group users only';

  @override
  String get mentionSelectorAgentsSubtitle => 'Notify group agents';

  @override
  String get mentionSelectorAllBadge => 'Users + Agents';

  @override
  String get mentionDisabledUnknownMemberType =>
      'This member type cannot be mentioned directly yet';

  @override
  String get mentionDisabledInactiveMember =>
      'This member is not active and cannot be mentioned';

  @override
  String get chatSendFailed => 'Send failed';

  @override
  String get chatRetrySend => 'Retry send';

  @override
  String get chatSending => 'Sending';

  @override
  String get chatViewPeerInfo => 'View user or agent info';

  @override
  String chatOpenPeerInfo(Object type) {
    return 'Open $type info';
  }

  @override
  String get chatCurrentConversationCannotSend =>
      'This conversation cannot send messages right now';

  @override
  String get chatAgentDeletedBadge => 'Agent deleted';

  @override
  String get chatPeerInfoUserTitle => 'User info';

  @override
  String get chatPeerInfoAgentTitle => 'Agent info';

  @override
  String get chatPeerInfoGroupTitle => 'Group info';

  @override
  String get chatPeerInfoGroupSection => 'Group';

  @override
  String get chatPeerInfoIdentityCard => 'Identity card';

  @override
  String get chatPeerInfoClose => 'Close info dialog';

  @override
  String get chatPeerInfoCopyDid => 'Copy DID';

  @override
  String get chatPeerInfoDidCopied => 'DID copied';

  @override
  String get chatPeerInfoProfileLoading => 'Loading profile';

  @override
  String get chatPeerInfoProfileUnavailable => 'Profile unavailable';

  @override
  String get chatPeerInfoAwikiUser => 'AWiki user';

  @override
  String get chatPeerInfoCollapseAgentInbox => 'Hide Agent inbox';

  @override
  String get chatPeerInfoAgentInbox => 'Agent inbox';

  @override
  String get chatPeerInfoUnknownContact => 'Unknown contact';

  @override
  String get chatPeerInfoLoadingProfile => 'Loading profile...';

  @override
  String get chatPeerInfoNoProfile => 'No profile provided yet';

  @override
  String get chatPeerInfoRenameAgent => 'Rename agent';

  @override
  String get chatPeerInfoRenameAgentTooltip => 'Rename';

  @override
  String chatPeerInfoMemberCount(int count) {
    return '$count members';
  }

  @override
  String get peerProfileLoadFailed => 'Unable to load this user\'s profile';

  @override
  String get peerProfileTitle => 'Profile';

  @override
  String get peerProfileSendMessage => 'Send message';

  @override
  String get peerProfileUnfollow => 'Unfollow';

  @override
  String get peerProfileDeleteThread => 'Clear chat history';

  @override
  String get peerProfileDeleteThreadConfirmTitle => 'Clear chat history?';

  @override
  String get peerProfileDeleteThreadConfirmMessage =>
      'This clears the local chat history with this user';

  @override
  String get peerProfileUnfollowed => 'Unfollowed';

  @override
  String get peerProfileThreadDeleted => 'Local chat history deleted';

  @override
  String get agentPageTitle => 'Agents';

  @override
  String get agentMineSection => 'My agents';

  @override
  String get agentInstallDaemonAction => 'Install a new Daemon';

  @override
  String get agentCreateDaemon => 'Create Daemon';

  @override
  String get agentRefreshList => 'Refresh agent list';

  @override
  String get agentEmpty => 'No agents yet';

  @override
  String get agentEmptyWaitingHost =>
      'This account has no available daemon yet. The list can sync automatically after installation, or you can refresh it manually.';

  @override
  String get agentEmptyInstallWaitingHost =>
      'Waiting for daemon installation to finish on the host. It will appear here automatically.';

  @override
  String get agentSelectOne => 'Select an agent';

  @override
  String get agentCreateRuntime => 'Create Agent';

  @override
  String get agentOpenChat => 'Open chat';

  @override
  String get agentRename => 'Rename';

  @override
  String get agentUpgrade => 'Upgrade';

  @override
  String get agentUpgrading => 'Upgrading';

  @override
  String get agentCancelUpgrade => 'Cancel upgrade';

  @override
  String get agentCancelling => 'Cancelling';

  @override
  String get agentDeleteDaemon => 'Delete daemon';

  @override
  String get agentDeleteRuntime => 'Delete agent';

  @override
  String get agentRemoveFromAccount => 'Remove from account';

  @override
  String get agentDeleting => 'Deleting';

  @override
  String get agentRecentRuns => 'Recent runs';

  @override
  String get agentRefreshStatus => 'Refresh status';

  @override
  String get agentDeletingNotice =>
      'Delete request sent. Waiting for daemon sync.';

  @override
  String agentDaemonSubtitle(int count, Object status) {
    return 'Daemon · $count Agents · $status';
  }

  @override
  String agentRuntimeSubtitle(Object runtime, Object status) {
    return '$runtime · $status';
  }

  @override
  String get agentUnnamedDaemon => 'Unnamed daemon';

  @override
  String get agentUnnamedRuntime => 'Unnamed agent';

  @override
  String get agentListDeletingSync => 'Deleting · waiting for sync';

  @override
  String get agentListUpgradeFailed => 'Upgrade failed';

  @override
  String get agentListCancellingUpgrade => 'Cancelling upgrade';

  @override
  String get agentListOrphanGroup => 'Not linked to a daemon';

  @override
  String get agentListNoRuntime => 'No Runtime Agent created yet';

  @override
  String agentListRuntimeCreating(Object runtime) {
    return '$runtime · creating';
  }

  @override
  String agentListRuntimeWaitingStatus(Object runtime) {
    return '$runtime · creation status has not returned yet. Refresh to check.';
  }

  @override
  String get daemonUpgradePreparingDownload => 'Preparing download';

  @override
  String get daemonUpgradeRouteDirect => 'Direct';

  @override
  String get daemonUpgradeRouteEnvironmentProxy => 'Proxy';

  @override
  String daemonUpgradeRouteLocalProxy(Object route) {
    return 'Local proxy $route';
  }

  @override
  String daemonUpgradeDownloaded(Object size) {
    return 'Downloaded $size';
  }

  @override
  String daemonUpgradeRouteIndex(int index, int count) {
    return 'Route $index/$count';
  }

  @override
  String get agentUpgradeTitle => 'Upgrade daemon';

  @override
  String get agentUpgradeMessage =>
      'The daemon will download the latest version and restart the service.';

  @override
  String get daemonUpgradeRequesting => 'Sending upgrade request';

  @override
  String get daemonUpgradeWaitingForDaemon =>
      'Upgrade request sent. Waiting for daemon confirmation.';

  @override
  String get daemonUpgradeFetchingManifest => 'Fetching version information';

  @override
  String get daemonUpgradeSelectingSource => 'Selecting download route';

  @override
  String get daemonUpgradeDownloading => 'Downloading package';

  @override
  String get daemonUpgradeRetryingSource => 'Download interrupted. Retrying';

  @override
  String get daemonUpgradeVerifying => 'Verifying package';

  @override
  String get daemonUpgradeExtracting => 'Extracting package';

  @override
  String get daemonUpgradeInstalling => 'Installing new version';

  @override
  String get daemonUpgradeRestarting => 'Restarting daemon';

  @override
  String get daemonUpgradeInProgress => 'Upgrading';

  @override
  String get agentUpgradeIncomplete =>
      'The upgrade did not complete. Check the network and try again.';

  @override
  String agentUpgradeDownloadFailed(Object summary) {
    return 'Package download failed. Check the network and try again. $summary';
  }

  @override
  String get agentUpgradeNotCancellable =>
      'This upgrade has already reached the restart stage and cannot be cancelled. Refresh status later to confirm the result.';

  @override
  String get agentUpgradeCancelFailed =>
      'Failed to cancel the upgrade. Refresh status and try again.';

  @override
  String get agentUpgradeCancelNoResponse =>
      'Cancel request sent, but the daemon has not responded yet. Refresh status to confirm the upgrade result.';

  @override
  String get agentDeleteDaemonMessage =>
      'Deleting this daemon stops the host service and removes the agents it created. Local data is archived and will no longer be used.';

  @override
  String get agentDeleteRuntimeMessage =>
      'Deleting this agent removes it from the list. Local data is archived and will no longer be used.';

  @override
  String get agentRemoveDaemonFromAccountMessage =>
      'This daemon is not reachable. This will remove the daemon and its agents from this account only. It will not access or clean up files on the host.';

  @override
  String get agentRemoveRuntimeFromAccountMessage =>
      'This agent cannot be deleted through its daemon right now. This will remove it from this account only. It will not access or clean up files on the host.';

  @override
  String get agentInstallTitle => 'Install daemon on host';

  @override
  String get agentInstallSupportedTypes =>
      'Supported Agent types: Hermes, Codex, Claude Code. After installing the host daemon, you can create Runtime Agents under it.';

  @override
  String agentInstallTokenExpiresAt(Object expiresAt) {
    return 'Expires at: $expiresAt';
  }

  @override
  String get agentCopyInstallCommand => 'Copy install command';

  @override
  String get agentSkillCreateInstruction => 'Create Skill Agent instruction';

  @override
  String get agentSkillInstallTitle => 'Connect a Skill Agent';

  @override
  String get agentSkillControllerHandle => 'Your Handle';

  @override
  String get agentSkillAgentHandle => 'Agent Handle';

  @override
  String get agentSkillDisplayName => 'Agent name';

  @override
  String get agentSkillDefaultDisplayName => 'Skill Agent';

  @override
  String get agentSkillDisplayNameHint =>
      'Shown in conversations and the Agent list. Edit it before generating the instruction.';

  @override
  String get agentSkillInvalidDisplayName =>
      'Enter an Agent name between 1 and 40 characters.';

  @override
  String get agentSkillActiveTokenLimit =>
      'Five unclaimed Skill Agent instructions are still active. Use an existing instruction or wait for one to expire.';

  @override
  String get agentSkillRateLimited =>
      'Too many Skill Agent instructions were generated recently. Wait a few minutes before trying again.';

  @override
  String get agentSkillServerUpgradeRequired =>
      'This server does not support editable Agent names yet. Upgrade User Service before generating an instruction.';

  @override
  String get agentSkillReadyToGenerate =>
      'Choose a readable name, then generate the one-time installation instruction.';

  @override
  String get agentSkillGenerate => 'Generate installation instruction';

  @override
  String get agentSkillCopyInstruction => 'Copy installation instruction';

  @override
  String get agentSkillRegenerate => 'Generate a new instruction';

  @override
  String get agentSkillSecretNotice =>
      'Valid for 30 minutes. The copied instruction contains a one-time secret; share it only with the Agent you want to connect.';

  @override
  String get agentSkillExpired =>
      'This instruction has expired or was cleared. Generate a new one.';

  @override
  String get agentCleanupHostTitle => 'Clean up this host only';

  @override
  String get agentCleanupHostToggle =>
      'Need to remove old daemon data from this computer?';

  @override
  String get agentCleanupHostWarning =>
      'This command only stops the daemon and permanently deletes its data from this computer, including its identity, databases, logs, archives, Runtime Profiles, and downloaded binaries. It does not remove the daemon or its agents from your AWiki account. Afterward, return to the Agents page in the app and remove the corresponding offline daemon from your account. This cannot be undone.';

  @override
  String get agentCopyCleanupCommand => 'Copy local cleanup command';

  @override
  String get agentCreateTitle => 'Create Agent';

  @override
  String get agentCreateType => 'Agent type';

  @override
  String get agentCreateWorkspacePolicy => 'Working directory policy';

  @override
  String get agentCreateWorkspaceRouteRoot => 'Per conversation';

  @override
  String get agentCreateWorkspaceRouteRootDescription =>
      'Each contact, group, or thread uses its own context directory.';

  @override
  String get agentCreateWorkspaceSharedRoot => 'Shared directory';

  @override
  String get agentCreateWorkspaceSharedRootDescription =>
      'This identity shares one directory, suitable for manual tasks.';

  @override
  String get agentCreateWorkspaceWorktreePerTask => 'Worktree per task';

  @override
  String get agentCreateWorkspaceWorktreePerTaskDescription =>
      'Each run uses an isolated worktree.';

  @override
  String agentCreateHandlePreview(Object handle) {
    return 'Final Handle: $handle';
  }

  @override
  String get agentCreateHandleAvailabilityChecking =>
      'Checking availability...';

  @override
  String get agentCreateHandleAvailabilityPending =>
      'Availability cannot be checked right now. It will be checked again when creating.';

  @override
  String get agentCreateHandleChecking => 'Checking Handle availability';

  @override
  String get agentCreateHandleAvailable => 'This Handle is available';

  @override
  String get agentCreateHandleUnavailableUsed => 'This Handle is already taken';

  @override
  String get agentCreateHandleUnavailable => 'This Handle is not available';

  @override
  String get agentCreateHandleRequired => 'Enter a Handle';

  @override
  String agentCreateHandleTooLong(Object maxLength) {
    return 'Handle can be at most $maxLength characters';
  }

  @override
  String get agentCreateHandleInvalidPattern =>
      'Use only lowercase letters, numbers, and hyphens. It must start and end with a letter or number.';

  @override
  String get agentCreateHandleNoDoubleHyphen =>
      'Handle cannot contain consecutive hyphens';

  @override
  String agentCreateNeedsRouteWorkspace(Object agentType) {
    return '$agentType requires per-conversation working directories.';
  }

  @override
  String get agentCreateHermesDescription => 'Built-in Hermes Runtime Agent.';

  @override
  String agentCreateNeedsGenericCliCapability(Object agentType) {
    return '$agentType requires generic-cli capability from the daemon.';
  }

  @override
  String agentCreateUnsupportedDriver(Object agentType) {
    return 'The current daemon does not support the $agentType driver.';
  }

  @override
  String agentCreateNeedsRouteSession(Object agentType) {
    return '$agentType requires route session and native resume support.';
  }

  @override
  String agentCreateNeedsHostAccess(Object agentType) {
    return '$agentType requires daemon support for full host access.';
  }

  @override
  String agentCreateRequiresSignedInCli(Object agentType) {
    return 'Requires an installed and signed-in $agentType CLI on the daemon host.';
  }

  @override
  String get agentCreateHostAccessTitle => 'Full host access';

  @override
  String get agentCreateHostAccessDescription =>
      'Can use local files, commands, tools, and network access when the user asks.';

  @override
  String get agentRenameTitle => 'Rename agent';

  @override
  String get agentRenameSubtitle =>
      'The name appears in the agent list, recent conversations, and chat header.';

  @override
  String get agentNameField => 'Name';

  @override
  String get agentNamePlaceholder => 'Display name';

  @override
  String agentNameHelp(int maxLength) {
    return 'Up to $maxLength characters.';
  }

  @override
  String get agentNameRequired => 'Enter an agent name';

  @override
  String agentNameTooLong(int maxLength) {
    return 'Name can be at most $maxLength characters';
  }

  @override
  String get agentStatusProcessing => 'Processing';

  @override
  String get agentStatusReady => 'Ready';

  @override
  String get agentStatusNeedsConfig => 'Needs config';

  @override
  String get agentStatusNeedsUpgrade => 'Needs upgrade';

  @override
  String get agentStatusFailed => 'Failed';

  @override
  String get agentStatusOffline => 'Offline';

  @override
  String get agentStatusDisabled => 'Disabled';

  @override
  String get agentStatusUnknown => 'Unknown';

  @override
  String get agentStatusRefreshNeeded => 'Refresh';

  @override
  String get agentStatusUnsupported => 'Unsupported';

  @override
  String agentStatusSemantic(Object status) {
    return 'Agent status: $status';
  }

  @override
  String get agentTerminalNotificationTitle => 'Agent';

  @override
  String get agentTerminalCompleted => 'Agent task completed';

  @override
  String get agentTerminalActionRequired => 'Agent task needs confirmation';

  @override
  String get agentTerminalRuntimeFailed => 'Agent task failed';

  @override
  String get agentErrorLoginRequired => 'Please log in first.';

  @override
  String get agentErrorHandleUnavailable =>
      'This account has no available Handle, so a daemon install command cannot be created right now.';

  @override
  String get agentSkillUnsupportedTenant =>
      'Skill Agent onboarding is not enabled for this tenant.';

  @override
  String get agentSkillInvalidResponse =>
      'The registration scope returned by the service does not match this account.';

  @override
  String get agentSkillRequestFailed =>
      'The Skill Agent instruction could not be generated. Try again.';

  @override
  String get agentErrorPersonalAgentDisabled =>
      'Personal Agent is not enabled.';

  @override
  String get agentTenantUnsupportedTitle =>
      'Agents are unavailable for this tenant';

  @override
  String get agentTenantUnsupportedSubtitle =>
      'Switch to a tenant on an approved AWiki realm to manage Daemons and Agents.';

  @override
  String get agentErrorTenantUnsupported =>
      'The current tenant does not support Agent features yet.';

  @override
  String get agentErrorSelectDaemon => 'Select a running daemon.';

  @override
  String get agentErrorDaemonBootstrapMissing =>
      'The running daemon has not reported a secure bootstrap public key yet. Refresh status first.';

  @override
  String get agentErrorDaemonUnreachableDelete =>
      'The daemon is currently unreachable and cannot be deleted yet.';

  @override
  String get agentErrorDaemonUnreachableUpgrade =>
      'The daemon is currently unreachable and cannot be upgraded yet. Refresh status or reinstall it first.';

  @override
  String get agentErrorPersonalAgentMissing =>
      'This daemon has not created a Personal Agent yet.';

  @override
  String get agentStatusSyncStillWaiting =>
      'Status sync is still pending. Refresh again later.';

  @override
  String get agentErrorScopeMismatch =>
      'This computer is already bound to a daemon for another Handle. Manage it with that Handle, or clean up AWiki daemon data on the host before installing again.';

  @override
  String get agentErrorControllerHandleMismatch =>
      'The client identity does not match the signed-in Handle. Switch to the correct account and copy a new install command.';

  @override
  String get agentErrorControllerScopeMissing =>
      'The install command is missing account ownership information. Copy the latest daemon install command again.';

  @override
  String get agentErrorInstallCommandUsed =>
      'This install command has already been used. Copy the latest daemon install command again.';

  @override
  String get agentErrorSessionExpired =>
      'Your sign-in session has expired. Log in again to view agents.';

  @override
  String get agentErrorRequestTimeout =>
      'The request timed out. Please try again later.';

  @override
  String get agentErrorNetworkPreserved =>
      'Network connection is temporarily unavailable. Current data has been kept.';

  @override
  String get agentErrorLoadFailed =>
      'Agent information cannot be loaded right now. Please try again later.';

  @override
  String get agentErrorStatusSessionExpired =>
      'Your sign-in session has expired. Log in again before refreshing daemon status.';

  @override
  String get agentErrorStatusTimeout =>
      'Status refresh timed out. Current data has been kept.';

  @override
  String get agentErrorStatusNetworkPreserved =>
      'Network connection is temporarily unavailable. Current data has been kept.';

  @override
  String get agentErrorStatusRefreshFailed =>
      'Status refresh request failed. Please try again later.';

  @override
  String get agentAccessTitle => 'Access control';

  @override
  String get agentAccessSubtitle =>
      'Configure which Handles can control this agent.';

  @override
  String get agentAccessWhitelist => 'Whitelist';

  @override
  String get agentAccessBlacklist => 'Blacklist';

  @override
  String get agentAccessSwitchToWhitelist => 'Switch to whitelist mode';

  @override
  String get agentAccessSwitchToBlacklist => 'Switch to blacklist mode';

  @override
  String get agentAccessCurrentWhitelist => 'Current whitelist mode';

  @override
  String get agentAccessCurrentBlacklist => 'Current blacklist mode';

  @override
  String get agentAccessEnabled => 'Enabled';

  @override
  String get agentAccessDisabled => 'Disabled';

  @override
  String get agentAccessHandlePlaceholder => 'bob or bob.example.com';

  @override
  String get agentAccessAddHandle => 'Add Handle';

  @override
  String get agentAccessNoHandles => 'No Handles yet';

  @override
  String get agentAccessRemoveHandle => 'Remove Handle';

  @override
  String get agentAccessDuplicateWhitelist =>
      'This Handle is already in the whitelist.';

  @override
  String get agentAccessDuplicateBlacklist =>
      'This Handle is already in the blacklist.';

  @override
  String get agentAccessHandleRequired => 'Enter a Handle.';

  @override
  String get agentAccessSingleHandleOnly => 'Add one Handle at a time.';

  @override
  String get agentAccessHandleInvalid => 'Enter a short Handle or full Handle.';

  @override
  String get agentDiagnosticsTitle => 'Diagnostics';

  @override
  String get agentDiagnosticsDaemonSubtitle =>
      'Daemon runtime and identity information';

  @override
  String get agentDiagnosticsAgentSubtitle => 'Agent identity information';

  @override
  String get agentDiagnosticsShowMore => 'Show more';

  @override
  String get agentDiagnosticsCollapse => 'Collapse';

  @override
  String get agentDiagnosticsShowMoreDetails => 'Show more diagnostics';

  @override
  String get agentDiagnosticsCollapseDetails => 'Collapse diagnostics';

  @override
  String get agentDiagnosticCurrentVersion => 'Current version';

  @override
  String get agentDiagnosticPlatform => 'Platform';

  @override
  String get agentDiagnosticLatestVersion => 'Latest version';

  @override
  String get agentDiagnosticMinSupportedVersion => 'Minimum supported version';

  @override
  String get agentDiagnosticService => 'Service';

  @override
  String get agentDiagnosticLastSeen => 'Last seen';

  @override
  String get agentDiagnosticErrorCode => 'Error code';

  @override
  String get agentDiagnosticRunner => 'Runner';

  @override
  String get agentDiagnosticProfileStatus => 'Profile status';

  @override
  String get agentDiagnosticInstallationStatus => 'Installation status';

  @override
  String get agentDiagnosticServiceInstalled => 'Service installed';

  @override
  String get agentDiagnosticConfigSummary => 'Config summary';

  @override
  String get agentDiagnosticHermesProfile => 'Hermes profile';

  @override
  String get agentDiagnosticRunnerStatus => 'Runtime status';

  @override
  String get agentDiagnosticActiveSessionCount => 'Active sessions';

  @override
  String get personalAgentSkipped => 'Personal Agent skipped this message';

  @override
  String get personalAgentFailed => 'Personal Agent failed';

  @override
  String get personalAgentCompleted => 'Personal Agent completed';

  @override
  String get personalAgentProcessing => 'Personal Agent is processing';

  @override
  String get personalAgentReceived => 'Personal Agent received the message';

  @override
  String get personalAgentResultGenerated => 'Result generated';

  @override
  String get personalAgentDraftApplied => 'Draft inserted into the composer';

  @override
  String get personalAgentAppActionCompleted => 'App action completed';

  @override
  String get personalAgentRequestRejected => 'Personal Agent request rejected';

  @override
  String get personalAgentAppActionFailed => 'App action failed';

  @override
  String get personalAgentWaitingConfirmation => 'Waiting for confirmation';

  @override
  String get personalAgentUseDraft => 'Use draft';

  @override
  String get personalAgentActionCreateDraft => 'Personal Agent created a draft';

  @override
  String get personalAgentActionSummarize => 'Personal Agent created a summary';

  @override
  String get personalAgentActionReadContact =>
      'Personal Agent requests contact access';

  @override
  String get personalAgentActionUpdateDisplayName =>
      'Personal Agent requests a contact name change';

  @override
  String get personalAgentActionUpdateNote =>
      'Personal Agent requests a contact note change';

  @override
  String get personalAgentActionGeneric =>
      'Personal Agent requests an app action';

  @override
  String get personalAgentTitle => 'Personal Agent';

  @override
  String personalAgentRuntimeSubtitle(Object provider) {
    return 'Runs a $provider runtime inside the daemon';
  }

  @override
  String get personalAgentExperimentDisabled => 'Experimental feature disabled';

  @override
  String get personalAgentReadyToEnable => 'Ready';

  @override
  String get personalAgentNotReady => 'Not ready';

  @override
  String get personalAgentRunningDaemon => 'Running daemon';

  @override
  String get personalAgentEngine => 'Engine';

  @override
  String get personalAgentScope => 'Scope';

  @override
  String get personalAgentAllProcessableConversations =>
      'All processable conversations';

  @override
  String get personalAgentDaemonVersion => 'Daemon version';

  @override
  String get personalAgentCapabilities => 'Capabilities';

  @override
  String get personalAgentSecureBootstrap => 'Secure bootstrap';

  @override
  String get personalAgentPublicKeyReported => 'Public key reported';

  @override
  String get personalAgentWaitingStatusRefresh => 'Waiting for status refresh';

  @override
  String get personalAgentEnable => 'Enable Personal Agent';

  @override
  String get personalAgentEnabling => 'Enabling';

  @override
  String get personalAgentPause => 'Pause message processing';

  @override
  String get personalAgentDelete => 'Delete Personal Agent';

  @override
  String get personalAgentRevokeAuthorization =>
      'Revoke daemon message authorization';

  @override
  String get personalAgentPermissionSummaryEnabled =>
      'Permission summary: reads regular messages, analyzes and summarizes them, creates drafts, and requests user-confirmed app actions.';

  @override
  String get personalAgentPermissionSummaryDisabled =>
      'Switch to a tenant on an approved AWiki realm to configure Personal Agent.';

  @override
  String get personalAgentPauseTitle => 'Pause message processing';

  @override
  String get personalAgentPauseMessage =>
      'After pausing, the Personal Agent stops reading and processing new messages. The runtime and authorization remain and can be enabled again.';

  @override
  String get personalAgentDeleteTitle => 'Delete Personal Agent';

  @override
  String get personalAgentDeleteMessage =>
      'Deletion pauses message processing first, then archives the runtime. The daemon and authorization are not deleted.';

  @override
  String get personalAgentRevokeTitle => 'Revoke daemon message authorization';

  @override
  String get personalAgentRevokeMessage =>
      'Revocation must remove daemon-key-1 through a signed DID Document update. If the update is not completed, it fails and will not treat pause as a successful revoke.';

  @override
  String get personalAgentSettingsSubtitle =>
      'Configure enablement, pause, and Daemon management';

  @override
  String get personalAgentSettingsDisabledSubtitle =>
      'Personal Agent is disabled and will not send bootstrap or authorization requests.';

  @override
  String get personalAgentNoDaemonSelected => 'No running daemon selected';

  @override
  String personalAgentSelectedDaemon(Object name) {
    return 'Running daemon: $name';
  }

  @override
  String get personalAgentDescription =>
      'Reads regular direct text, organizes it, and prepares drafts for your confirmation.';

  @override
  String get personalAgentDisabledDescription =>
      'This experimental feature is disabled. No bootstrap or authorization request will be sent.';

  @override
  String get personalAgentDaemonStatus => 'Daemon status';

  @override
  String get personalAgentAuthorizationStatus => 'Authorization';

  @override
  String get personalAgentDirectTextScope => 'Regular direct text';

  @override
  String get personalAgentNotSelected => 'Not selected';

  @override
  String get personalAgentNoDaemon => 'No daemon available';

  @override
  String get personalAgentNotBound => 'Not bound';

  @override
  String personalAgentBound(Object name) {
    return 'Bound to $name';
  }

  @override
  String get personalAgentRefreshDaemonStatus => 'Refresh daemon status';

  @override
  String get personalAgentSelectDaemon => 'Select running daemon';

  @override
  String get personalAgentRunsOnSelectedDaemon =>
      'Personal Agent runs inside the selected daemon.';

  @override
  String get personalAgentNoDaemons =>
      'No daemon is available. Create or install one from Agents first.';

  @override
  String personalAgentSelectDaemonSemantic(Object name) {
    return 'Select $name';
  }

  @override
  String get personalAgentReadyWithPublicKey => 'Ready · public key reported';

  @override
  String get personalAgentReadyWaitingPublicKey =>
      'Ready · waiting for bootstrap public key';

  @override
  String personalAgentDaemonNeedsAttention(Object status) {
    return '$status · refresh or inspect the daemon';
  }

  @override
  String get personalAgentFeatureDisabledNotice =>
      'AWIKI_AGENT_IM_ENABLED=false. This entry is read-only and sends no bootstrap, binding, or authorization request.';

  @override
  String get personalAgentNoDaemonNotice =>
      'No daemon is available. Install and start a daemon first.';

  @override
  String get personalAgentDaemonNotReadyNotice =>
      'The selected daemon is not ready. Refresh its status or inspect the daemon.';

  @override
  String get personalAgentBootstrapKeyMissingNotice =>
      'The selected daemon has not reported a secure bootstrap public key. Refresh daemon status first.';

  @override
  String get personalAgentCanEnableNotice => 'Personal Agent can be enabled.';

  @override
  String get personalAgentSafetyTitle => 'Safety boundaries';

  @override
  String get personalAgentSafetyPlainText =>
      'Reads only supported regular direct text and never processes Direct or Group E2EE plaintext.';

  @override
  String get personalAgentSafetyDraftOnly =>
      'Creates drafts and confirmation-required actions; it never sends messages automatically.';

  @override
  String get personalAgentSafetyNoPrimaryKey =>
      'The runtime never holds the primary DID private key or connects directly to message-service.';

  @override
  String get personalAgentSafetyFeatureDisabled =>
      'When disabled, the feature performs no authorization, bootstrap, or delegated-key operation.';

  @override
  String get personalAgentBusy => 'Working';

  @override
  String get personalAgentDaemonNotReady => 'Daemon not ready';

  @override
  String get personalAgentEnabledState => 'Enabled';

  @override
  String get personalAgentCreated => 'Personal Agent created';

  @override
  String get personalAgentConfigure => 'Configure Personal Agent';

  @override
  String get agentInboxTitle => 'Agent inbox';

  @override
  String get agentInboxThreadTitle => 'Inbox thread';

  @override
  String get agentInboxBackToInbox => 'Back to inbox';

  @override
  String get agentInboxBackToConversation => 'Back to conversation';

  @override
  String get agentInboxClose => 'Close Agent inbox';

  @override
  String get agentInboxNotRuntimeConversation =>
      'The current conversation is not a Runtime Agent conversation';

  @override
  String get agentInboxDaemonMissing =>
      'This Runtime Agent is not bound to a daemon yet';

  @override
  String get agentInboxRefresh => 'Refresh Agent inbox';

  @override
  String get agentInboxEmpty => 'This Agent has no inbox messages yet';

  @override
  String get agentInboxLoadMoreThreads => 'Load more conversations';

  @override
  String get agentInboxScopeAll => 'All';

  @override
  String get agentInboxScopeDirect => 'Direct';

  @override
  String get agentInboxScopeGroup => 'Groups';

  @override
  String get agentInboxLatestAttachment => 'Latest: attachment';

  @override
  String get agentInboxLatestNoPreview => 'Latest: no preview';

  @override
  String agentInboxLatestPreview(Object preview) {
    return 'Latest: $preview';
  }

  @override
  String get agentInboxReadOnly => 'Read-only inbox';

  @override
  String get agentInboxRefreshThread => 'Refresh inbox thread';

  @override
  String get agentInboxThreadEmpty => 'This thread has no messages yet';

  @override
  String get agentInboxLoadEarlier => 'Load earlier messages';

  @override
  String get agentInboxContentTruncated => 'Long content truncated';

  @override
  String get agentInboxDaemonNoResponse =>
      'Daemon did not respond yet. Please try again later.';

  @override
  String get agentInboxQueryFailed => 'Inbox query failed';

  @override
  String get agentInboxThreadQueryFailed => 'Thread query failed';

  @override
  String get relationshipNone => 'Not following';

  @override
  String get relationshipFollowing => 'Following';

  @override
  String get relationshipFollower => 'Follows you';

  @override
  String get relationshipFriend => 'Friend';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String exportedTo(Object path) {
    return 'Exported to $path';
  }

  @override
  String get importSuccessSelectCredential =>
      'Import succeeded. Please choose this credential to log in.';

  @override
  String localCredentialsRefreshed(Object count) {
    return 'Found $count local credential(s)';
  }

  @override
  String get noLocalCredentialsFound => 'No local credentials found';

  @override
  String get newMessageArrived => 'You received a new message';

  @override
  String get updateAlreadyLatest => 'You\'re already on the latest version.';

  @override
  String get updateCheckFailed =>
      'Update check failed. Please try again later.';

  @override
  String get updateOpenReleaseNotesFailed =>
      'Couldn\'t open the release notes.';

  @override
  String get updateOpenDownloadFailed =>
      'Couldn\'t open the download page. Please try again later.';

  @override
  String get updateReadyToInstall => 'Download complete. Ready to install.';

  @override
  String get updatePermissionRequired =>
      'Please allow installs from this source and try again.';

  @override
  String get updateInstallFailed =>
      'Update failed. Please install it from the download page.';

  @override
  String get daemonUpgradeStarted => 'Daemon upgrade started.';

  @override
  String get requestTimeoutRetry =>
      'The request timed out. Please check your network and try again.';

  @override
  String get networkUnavailableRetry =>
      'Network connection is temporarily unavailable. Please check your network and try again.';

  @override
  String get operationFailedRetry =>
      'The operation failed. Please try again later.';

  @override
  String get featureNotImplemented => 'This feature is not available yet.';

  @override
  String get otpSent => 'Verification code sent. Please check your messages.';

  @override
  String get activationEmailSent =>
      'Activation email sent. Please check your inbox.';

  @override
  String get emailNotActivatedClickLink =>
      'The email is not activated yet. Please click the activation link in the email first.';

  @override
  String get sessionExpiredRelogin =>
      'Your sign-in session has expired. Please log in again.';

  @override
  String get didNotFoundOrRevoked =>
      'This DID does not exist or has been revoked. Check the DID and try again, or switch to a valid identity.';

  @override
  String localCredentialNotFound(Object credentialName) {
    return 'Local credential not found: $credentialName';
  }

  @override
  String get setupIdentityScriptMissing =>
      'Legacy script credentials are no longer supported. Create or import a new e1 DID credential.';

  @override
  String deleteCredentialFailed(Object credentialName) {
    return 'Failed to delete credential: $credentialName';
  }

  @override
  String get noCredentialToExport =>
      'There is no signed-in credential available to export.';

  @override
  String get credentialPackFailed =>
      'Failed to package the credential. Please try again later.';

  @override
  String get localCredentialDirectoryMissing =>
      'Unable to locate the local credential directory.';

  @override
  String get exportUnsupportedOnPlatform =>
      'Exporting identity credentials is not supported on this platform yet.';

  @override
  String get importUnsupportedOnPlatform =>
      'Importing identity credentials is not supported on this platform yet.';

  @override
  String get currentCredentialIndexMissing =>
      'Unable to find the local index info for the current credential.';

  @override
  String get currentCredentialDidInvalid =>
      'The DID document for the current credential is invalid.';

  @override
  String get zipMissingMetadata =>
      'The ZIP package is missing required credential metadata.';

  @override
  String get zipCredentialIncomplete =>
      'The credential content inside the ZIP package is incomplete.';

  @override
  String invalidFileFormat(Object path) {
    return 'Invalid file format: $path';
  }

  @override
  String get phoneInvalidIntlExample =>
      'Invalid phone number format. Use a number with country code, for example +8613800138000.';

  @override
  String get phoneInvalidIntlOrCn =>
      'Invalid phone number format. Use international format or an 11-digit mainland China number.';

  @override
  String get handleInvalidPattern =>
      'Handle may only contain lowercase letters, numbers, and hyphens, 2-32 characters, with no underscores.';

  @override
  String didRegistrationPluginMissing(Object authHint) {
    return 'AWiki Me cannot create a DID right now ($authHint registration). Check that the Dart ANP SDK initialized successfully.';
  }

  @override
  String get didRegistrationRefreshUnsupported =>
      'AWiki Me does not currently include a DID registration plugin, so token refresh is unavailable.';

  @override
  String get e2eePluginMissing =>
      'AWiki Me does not currently have E2EE enabled. Please integrate the native plugin.';

  @override
  String get documentPickerFailed =>
      'File selection failed. Please try again later.';

  @override
  String get documentSaveFailed => 'File save failed. Please try again later.';

  @override
  String get attachmentDownloadEmpty => 'Attachment download returned no file.';

  @override
  String get attachmentDownloading => 'Downloading';

  @override
  String attachmentDownloadingProgress(String progress) {
    return 'Downloading · $progress';
  }

  @override
  String get attachmentDownloadPaused => 'Download paused';

  @override
  String attachmentDownloadPausedProgress(String progress) {
    return 'Download paused · $progress';
  }

  @override
  String get attachmentDownloadCancelFailed =>
      'Unable to pause the download. Please try again.';

  @override
  String get attachmentDownloadInterrupted =>
      'The download was interrupted. Your progress has been kept; try again to resume.';

  @override
  String get chatImageActionsTitle => 'Image';

  @override
  String get chatCopyImage => 'Copy Image';

  @override
  String get chatSaveImageAs => 'Save Image As...';

  @override
  String get chatImageCopied => 'Image copied';

  @override
  String get chatImageSaved => 'Image saved';

  @override
  String get chatImageCopyFailed =>
      'Couldn\'t copy the image. Please try again.';

  @override
  String get conversationRemovedFromRecents =>
      'Conversation removed from recents.';

  @override
  String get attachmentUnavailable =>
      'The attachment has expired or is not cached on this device. Ask the sender to send it again.';

  @override
  String get attachmentOpenFailed =>
      'The attachment cannot be opened. Try again later or save it before opening.';

  @override
  String get linkOpenFailed => 'Unable to open the link';

  @override
  String linkOpenFailedWithDetail(Object detail) {
    return 'Unable to open the link: $detail';
  }

  @override
  String get groupNameRequired => 'Group name cannot be empty';

  @override
  String chatGroupMemberAddedByYou(Object member) {
    return 'You invited $member to the group';
  }

  @override
  String chatGroupMemberAddedBy(Object actor, Object member) {
    return '$actor invited $member to the group';
  }

  @override
  String chatGroupMemberJoined(Object member) {
    return '$member joined the group';
  }

  @override
  String chatGroupMemberRemovedByYou(Object member) {
    return 'You removed $member from the group';
  }

  @override
  String chatGroupMemberRemovedBy(Object actor, Object member) {
    return '$actor removed $member from the group';
  }

  @override
  String chatGroupMemberLeft(Object member) {
    return '$member left the group';
  }

  @override
  String get chatGroupProfileUpdated => 'Group info updated';

  @override
  String get chatInformationTitle => 'Chat Info';

  @override
  String get chatOpenInformation => 'Open chat information';

  @override
  String get chatSearchHistory => 'Search Chat History';

  @override
  String get chatSearchHistoryPlaceholder => 'Search chat history';

  @override
  String get chatSearchHistoryEmpty => 'No matching chat history';

  @override
  String get chatMuteNotifications => 'Mute Notifications';

  @override
  String get chatPinConversation => 'Pin Chat';

  @override
  String get chatRemoveConversation => 'Remove from Messages';

  @override
  String get chatRemoveConversationConfirmTitle => 'Remove from Messages?';

  @override
  String get chatRemoveConversationConfirmMessage =>
      'This only removes the conversation from Messages. Its history is preserved and the conversation will return when reopened or when a new message arrives.';

  @override
  String get handleRecoveryUnavailable =>
      'Handle Recovery is not supported in this version. No identity state was changed.';

  @override
  String get handleRecoveryTitle => 'Recover Handle';

  @override
  String get handleRecoveryIntro =>
      'Recover this Handle with its bound phone number. Old identity private keys are not recovered.';

  @override
  String get handleRecoveryHandle => 'Full Handle';

  @override
  String get handleRecoveryPhone => 'Bound phone number';

  @override
  String get handleRecoveryOtp => 'SMS code';

  @override
  String get handleRecoverySendOtp => 'Send code';

  @override
  String get handleRecoveryVerify => 'Verify recovery';

  @override
  String get handleRecoveryIrreversible => 'This recovery is irreversible.';

  @override
  String get handleRecoveryHandlePreserved =>
      'Your Handle is preserved, but the identity moves to a new DID.';

  @override
  String get handleRecoveryOtherDevicesRejoin =>
      'All old devices are invalidated immediately and can return only through ordinary Device Join.';

  @override
  String get handleRecoveryLocalOrdinaryMigration =>
      'Only ordinary local data is migrated on this device.';

  @override
  String get handleRecoveryOldE2eeUnavailable =>
      'Old P5 PreKeys, Ratchet, MLS, and other E2EE keys are not migrated.';

  @override
  String get handleRecoverySingletonRisk =>
      'Until a second ready admin device exists, recovered A′ is the only approver.';

  @override
  String get handleRecoveryDidOnlyUnsupported =>
      'This version does not automatically restore any E2EE or DID-only group.';

  @override
  String get handleRecoveryRiskConfirm => 'I understand these effects';

  @override
  String get handleRecoveryActivate => 'Confirm and recover';

  @override
  String get handleRecoveryResume => 'Resume recovery';

  @override
  String get handleRecoveryPresenceReason => 'Confirm Handle identity recovery';

  @override
  String get handleRecoveryRiskRequired =>
      'Confirm that you understand the recovery effects first.';

  @override
  String get handleRecoveryFailed => 'Recovery failed. Try again later.';

  @override
  String get handleRecoveryOtpRequested =>
      'The recovery operation is saved in Core. Enter the SMS code to continue.';

  @override
  String get handleRecoveryStillConfirming =>
      'The remote result is still being confirmed. Keep this operation and resume it; do not start over or discard its key.';

  @override
  String get handleRecoveryKeyUnavailable =>
      'The recovery key is no longer available on this device. Quarantine this operation before starting a new recovery.';

  @override
  String get handleRecoveryQuarantine => 'Quarantine unavailable operation';

  @override
  String get handleRecoveryQuarantineReason =>
      'Confirm that this recovery key is permanently unavailable';

  @override
  String get handleRecoveryQuarantined =>
      'The unavailable operation is quarantined and retained in Core for audit. You may now start a new recovery.';

  @override
  String get handleRecoveryStartNew => 'Start a new recovery';

  @override
  String get handleRecoveryMigrationUnsupported =>
      'This local identity cannot be migrated safely in V4.0. No remote commit was attempted; use a fresh start or ordinary Device Join.';

  @override
  String get handleRecoveryErrorNotPrepared =>
      'Recovery was not prepared. This flow is terminated; start again.';

  @override
  String get handleRecoveryErrorUserPresenceRequired =>
      'Complete the local system confirmation again before continuing.';

  @override
  String get handleRecoveryErrorTransitionMismatch =>
      'The recovery context does not match. This flow is terminated for safety.';

  @override
  String get handleRecoveryErrorTransitionChainUnsupported =>
      'This identity transition chain is unsupported. This flow is terminated.';

  @override
  String get handleRecoveryErrorRemoteStateChanged =>
      'Remote state changed. Continue status or resume only with the current recovery reference.';

  @override
  String get handleRecoveryErrorOutcomeUnknown =>
      'The submission outcome is unknown. Continue with the same recovery reference; do not create a new operation.';

  @override
  String get handleRecoveryErrorLocalStateUnavailable =>
      'The local recovery reference is unavailable. Continuing is blocked on this device.';

  @override
  String get handleRecoveryErrorBlocked =>
      'Recovery is blocked by a safety policy. Retain the current recovery reference for audit.';

  @override
  String get handleRecoveryPrepared =>
      'Recovery was verified. Review the effects before continuing.';

  @override
  String get handleRecoveryRemotePending =>
      'Submitting the remote recovery result.';

  @override
  String get handleRecoveryRemoteCommitted =>
      'The remote recovery result is confirmed.';

  @override
  String get handleRecoveryIdentityPending => 'Migrating local identity data.';

  @override
  String get handleRecoveryIdentitySwitched =>
      'The local identity switched. Finishing recovery.';

  @override
  String get handleRecoveryCompleted => 'Identity recovery is complete.';

  @override
  String get handleRecoveryBlocked =>
      'Recovery is blocked. Check its status and try again.';

  @override
  String handleRecoveryJoinRestored(Object handle) {
    return 'Identity recovery is complete for $handle.';
  }

  @override
  String get handleRecoveryJoinLocalMigration =>
      'Local data on this device will be migrated.';

  @override
  String get handleRecoveryJoinE2eeUnsupported =>
      'Encrypted groups do not support identity recovery yet. Old E2EE private keys do not migrate.';

  @override
  String get handleRecoveryJoinDidOnlyUnsupported =>
      'DID-only contacts and groups do not migrate.';

  @override
  String get legacyIdentityUpgradeFailed =>
      'The legacy identity upgrade failed. Please try again.';
}
