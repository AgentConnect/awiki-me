// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AWiki Me';

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
  String get commonPleaseWait => 'Please wait...';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonError => 'Error';

  @override
  String get realtimeStatusConnecting => 'Connecting to message service...';

  @override
  String get realtimeStatusReconnecting =>
      'Message connection interrupted. Reconnecting...';

  @override
  String get realtimeStatusDisconnected =>
      'Message service is disconnected. Trying to recover.';

  @override
  String get onboardingLogin => 'Log in';

  @override
  String get onboardingRegister => 'Register';

  @override
  String get onboardingImportCredential => 'Import identity credential';

  @override
  String get onboardingRefreshCredentials => 'Rescan local credentials';

  @override
  String get onboardingSendOtp => 'Send verification code';

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
  String get onboardingCompleteRegister => 'Complete registration';

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
  String get secureMessagingClient => 'Secure messaging client';

  @override
  String get conversationsTitle => 'Messages';

  @override
  String get conversationsNoMessagePreview => 'No messages yet';

  @override
  String get conversationsEmptyTitle => 'No messages yet';

  @override
  String get conversationsEmptySubtitle =>
      'Add friends, follow contacts, or join a group chat to get started.';

  @override
  String get friendsTitle => 'Friends';

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
  String get settingsTitle => 'Settings';

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
      'Open GitHub to browse release history';

  @override
  String get settingsUpdateOpenGitHubDownload =>
      'Open GitHub to download the current build';

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
  String get settingsDeleteCredential => 'Delete current credential';

  @override
  String settingsDeleteCurrentCredential(Object credentialName) {
    return 'Delete local credential: $credentialName';
  }

  @override
  String get settingsDeleteCredentialFallback =>
      'Delete current signed-in credential';

  @override
  String get settingsLogoutConfirmTitle => 'Log out';

  @override
  String get settingsLogoutConfirmContent =>
      'Are you sure you want to log out of the current account?';

  @override
  String get settingsDeleteCredentialConfirmTitle =>
      'Delete current credential';

  @override
  String settingsDeleteCredentialConfirmContent(Object credentialName) {
    return 'This will delete the local credential \"$credentialName\" and log you out. Continue?';
  }

  @override
  String get settingsDeleteCredentialConfirmAction => 'Delete credential';

  @override
  String get quickActionsTitle => 'More actions';

  @override
  String get quickActionCreateGroup => 'Start group chat';

  @override
  String get quickActionJoinGroup => 'Join group chat';

  @override
  String get quickActionAddFriend => 'Add friend';

  @override
  String get addFriendTitle => 'Add friend';

  @override
  String get addFriendPlaceholder => 'Enter Handle or DID';

  @override
  String get addFriendAlreadyExists => 'Already added or pending approval';

  @override
  String get addFriendFollowed => 'Followed';

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
  String get groupCreateTitle => 'Create group';

  @override
  String get groupFieldName => 'Name';

  @override
  String get groupFieldNamePlaceholder => 'Group name';

  @override
  String get groupFieldSlug => 'Slug';

  @override
  String get groupFieldSlugPlaceholder => 'Optional, auto-generated if empty';

  @override
  String get groupFieldDescription => 'Description';

  @override
  String get groupFieldDescriptionPlaceholder => 'Group description';

  @override
  String get groupFieldGoal => 'Goal';

  @override
  String get groupFieldGoalPlaceholder => 'Group goal';

  @override
  String get groupFieldRules => 'Rules';

  @override
  String get groupFieldRulesPlaceholder => 'Community rules';

  @override
  String get groupFieldPrompt => 'Prompt';

  @override
  String get groupFieldPromptPlaceholder => 'Message prompt for participation';

  @override
  String get groupCreating => 'Creating group...';

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
  String get relationshipNone => 'none';

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
      'Couldn\'t open the download page. Please use GitHub Releases.';

  @override
  String get updateReadyToInstall => 'Download complete. Ready to install.';

  @override
  String get updatePermissionRequired =>
      'Please allow installs from this source and try again.';

  @override
  String get updateInstallFailed =>
      'Update failed. Please download it from GitHub.';

  @override
  String get requestTimeoutRetry =>
      'The request timed out. Please check your network and try again.';

  @override
  String get operationFailedRetry =>
      'The operation failed. Please try again later.';

  @override
  String get emailNotActivatedClickLink =>
      'The email is not activated yet. Please click the activation link in the email first.';

  @override
  String get sessionExpiredRelogin =>
      'Your sign-in session has expired. Please log in again.';

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
  String get linkOpenFailed => 'Unable to open the link';

  @override
  String linkOpenFailedWithDetail(Object detail) {
    return 'Unable to open the link: $detail';
  }

  @override
  String get groupNameRequired => 'Group name cannot be empty';
}
