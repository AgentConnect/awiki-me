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
  String get quickActionsTitle => 'Quick actions';

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
      'No groups yet. Create one or join with a 6-digit join code.';

  @override
  String get groupListLoading => 'Loading group data...';

  @override
  String get groupJoinDialogTitle => 'Join with a join code';

  @override
  String get groupJoinDialogPlaceholder => 'Enter a 6-digit join code';

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
  String groupJoinCodeLabel(Object code) {
    return 'Join code: $code';
  }

  @override
  String groupIdLabel(Object groupId) {
    return 'Group ID: $groupId';
  }

  @override
  String get groupEnterChat => 'Enter group chat';

  @override
  String get groupGetJoinCode => 'Get current join code';

  @override
  String get groupRefreshJoinCode => 'Refresh join code';

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
  String get groupModeTitle => 'Group mode';

  @override
  String get groupModeChat => 'Chat';

  @override
  String get groupModeDiscovery => 'Discovery';

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
      'This repository does not include setup_identity.py. Configure AWIKI_SETUP_IDENTITY_SCRIPT explicitly before deleting the credential.';

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
  String get localCredentialIndexInvalid =>
      'The local credential index format is invalid.';

  @override
  String get localCredentialIndexMissingCredentials =>
      'The local credential index is missing the credentials field.';

  @override
  String credentialIndexEntryInvalid(Object key) {
    return 'The credential index entry format is invalid: $key';
  }

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
    return 'AWiki Me does not currently include a DID registration plugin ($authHint registration). Please register with the Python script and import the session first, or add the native plugin to complete registration in the app.';
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
