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
  String get commonLoading => 'Loading...';

  @override
  String get commonError => 'Error';

  @override
  String get commonErrorDetails => 'Error details';

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
  String get handleAlreadyRegisteredImportCredential =>
      'This handle already exists. This server cannot recover it without verification. Import its identity credential or contact the server administrator.';

  @override
  String get registrationMethodUnavailable =>
      'This server does not support the selected registration method. Refresh and try again.';

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
  String get shellNavFriends => 'Friends';

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
      'This conversation will be removed from recents, but message history will be kept. It will appear again when you reopen it or receive a new message.';

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
  String get friendsTitle => 'Friends';

  @override
  String get friendsGroups => 'Groups';

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
  String get profileTagsPlaceholder => 'Tags, separated by commas';

  @override
  String get profileOpenHomepage => 'Open homepage';

  @override
  String get settingsTitle => 'Settings';

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
  String get devicesLocalJoinsTitle => 'Unfinished device joins';

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
  String get deviceReviewAction => 'Review and verify';

  @override
  String get deviceResumeAction => 'Continue';

  @override
  String get deviceJoinEntry => 'Add this device to an existing account';

  @override
  String get deviceJoinEntrySubtitle =>
      'An existing admin device must verify the 6-digit code shown on both devices';

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
  String get deviceJoinAllowAdmin =>
      'Allow this device to manage other devices';

  @override
  String get deviceJoinAllowAdminHint =>
      'Off by default. Root-key import must still finish before this device can manage devices.';

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
  String get deviceJoinErrorFailed =>
      'Device operation failed. Refresh and try again.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow system';

  @override
  String get settingsLanguageZhHans => '简体中文';

  @override
  String get settingsLanguageEnglish => 'English';

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
  String get settingsLogout => 'Log out';

  @override
  String get settingsLogoutSubtitle =>
      'Clear local sign-in state and return to the sign-in page';

  @override
  String get settingsDeleteCredential =>
      'Sign out and delete current credential';

  @override
  String settingsDeleteCurrentCredential(Object credentialName) {
    return 'Delete local credential: $credentialName';
  }

  @override
  String get settingsDeleteCredentialFallback =>
      'Sign out and delete current signed-in credential';

  @override
  String get settingsLogoutConfirmTitle => 'Log out';

  @override
  String get settingsLogoutConfirmContent =>
      'Are you sure you want to log out of the current account?';

  @override
  String get settingsDeleteCredentialConfirmTitle =>
      'Sign out and delete current credential';

  @override
  String settingsDeleteCredentialConfirmContent(Object credentialName) {
    return 'This will sign you out and delete the local credential \"$credentialName\". To use it again, you will need to import or recover the identity. Continue?';
  }

  @override
  String get settingsDeleteCredentialConfirmAction => 'Sign out and delete';

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
  String get groupListTitle => 'Group chats';

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
  String get chatSafeCollaboration => 'Secure collaboration';

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
  String get peerProfileDeleteThread => 'Delete local chat history';

  @override
  String get peerProfileUnfollowed => 'Unfollowed';

  @override
  String get peerProfileThreadDeleted => 'Local chat history deleted';

  @override
  String get agentPageTitle => 'Agents';

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
  String get agentCleanupHostTitle => 'Clean up host';

  @override
  String get agentCleanupHostToggle =>
      'Need to clean up an old daemon on the host?';

  @override
  String get agentCleanupHostWarning =>
      'This stops the AWiki daemon on the host and permanently deletes all daemon data on that host, including identity, databases, logs, archives, Runtime Profiles, and downloaded daemon binaries. This cannot be undone.';

  @override
  String get agentCopyCleanupCommand => 'Copy cleanup command';

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
  String get agentErrorLoginRequired => 'Please log in first.';

  @override
  String get agentErrorHandleUnavailable =>
      'This account has no available Handle, so a daemon install command cannot be created right now.';

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
      'Configure enablement, pause, and daemon message authorization.';

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
  String get relationshipFollowing => 'following';

  @override
  String get relationshipFollower => 'follower';

  @override
  String get relationshipFriend => 'friend';

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
  String get emailLoginUnsupportedForRegisteredHandle =>
      'This handle is already registered. Email currently supports new registration only. Use phone verification or import an identity credential to log in.';

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
}
