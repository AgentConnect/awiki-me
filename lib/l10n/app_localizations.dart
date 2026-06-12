import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'AWiki Me'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @commonDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get commonDone;

  /// No description provided for @commonSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get commonSend;

  /// No description provided for @commonJoin.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get commonJoin;

  /// No description provided for @commonBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get commonNext;

  /// No description provided for @commonPrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get commonPrevious;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonGotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get commonGotIt;

  /// No description provided for @commonPleaseWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍候...'**
  String get commonPleaseWait;

  /// No description provided for @commonLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get commonLoading;

  /// No description provided for @commonError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get commonError;

  /// No description provided for @realtimeStatusConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接消息服务...'**
  String get realtimeStatusConnecting;

  /// No description provided for @realtimeStatusReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'消息连接中断，正在重连...'**
  String get realtimeStatusReconnecting;

  /// No description provided for @realtimeStatusDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'消息服务已断开，正在尝试恢复'**
  String get realtimeStatusDisconnected;

  /// No description provided for @onboardingLogin.
  ///
  /// In zh, this message translates to:
  /// **'切换身份'**
  String get onboardingLogin;

  /// No description provided for @onboardingRegister.
  ///
  /// In zh, this message translates to:
  /// **'登录或注册'**
  String get onboardingRegister;

  /// No description provided for @onboardingImportCredential.
  ///
  /// In zh, this message translates to:
  /// **'导入身份凭证'**
  String get onboardingImportCredential;

  /// No description provided for @onboardingRefreshCredentials.
  ///
  /// In zh, this message translates to:
  /// **'重新识别本地凭证'**
  String get onboardingRefreshCredentials;

  /// No description provided for @onboardingSendOtp.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码'**
  String get onboardingSendOtp;

  /// No description provided for @onboardingResendOtpIn.
  ///
  /// In zh, this message translates to:
  /// **'重新发送（{seconds}s）'**
  String onboardingResendOtpIn(Object seconds);

  /// No description provided for @onboardingOtp.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get onboardingOtp;

  /// No description provided for @onboardingOtpPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入验证码'**
  String get onboardingOtpPlaceholder;

  /// No description provided for @onboardingEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get onboardingEmail;

  /// No description provided for @onboardingEmailPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入邮箱地址'**
  String get onboardingEmailPlaceholder;

  /// No description provided for @onboardingSendActivationEmail.
  ///
  /// In zh, this message translates to:
  /// **'发送激活邮件'**
  String get onboardingSendActivationEmail;

  /// No description provided for @onboardingResendActivationEmailIn.
  ///
  /// In zh, this message translates to:
  /// **'重新发送（{seconds}s）'**
  String onboardingResendActivationEmailIn(Object seconds);

  /// No description provided for @onboardingEmailActivated.
  ///
  /// In zh, this message translates to:
  /// **'邮箱已激活'**
  String get onboardingEmailActivated;

  /// No description provided for @onboardingCheckActivationStatus.
  ///
  /// In zh, this message translates to:
  /// **'我已激活，检查状态'**
  String get onboardingCheckActivationStatus;

  /// No description provided for @onboardingHandle.
  ///
  /// In zh, this message translates to:
  /// **'账号用户名'**
  String get onboardingHandle;

  /// No description provided for @onboardingHandlePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'用户名 handle'**
  String get onboardingHandlePlaceholder;

  /// No description provided for @onboardingNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get onboardingNickname;

  /// No description provided for @onboardingNicknamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入昵称'**
  String get onboardingNicknamePlaceholder;

  /// No description provided for @onboardingCompleteRegister.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get onboardingCompleteRegister;

  /// No description provided for @onboardingCompleteEmailRegister.
  ///
  /// In zh, this message translates to:
  /// **'完成注册'**
  String get onboardingCompleteEmailRegister;

  /// No description provided for @onboardingLoginRegisterHint.
  ///
  /// In zh, this message translates to:
  /// **'手机号会自动判断登录已有 Handle 或注册新 Handle；邮箱暂时仅支持注册新 Handle。'**
  String get onboardingLoginRegisterHint;

  /// No description provided for @onboardingAuthMethod.
  ///
  /// In zh, this message translates to:
  /// **'验证方式'**
  String get onboardingAuthMethod;

  /// No description provided for @onboardingAccountProfile.
  ///
  /// In zh, this message translates to:
  /// **'账号资料'**
  String get onboardingAccountProfile;

  /// No description provided for @onboardingPhone.
  ///
  /// In zh, this message translates to:
  /// **'手机号'**
  String get onboardingPhone;

  /// No description provided for @onboardingPhonePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入手机号'**
  String get onboardingPhonePlaceholder;

  /// No description provided for @onboardingMissingLocalCredential.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到本地凭证，请先重新识别。'**
  String get onboardingMissingLocalCredential;

  /// No description provided for @onboardingIncompletePhoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'手机号不完整'**
  String get onboardingIncompletePhoneTitle;

  /// No description provided for @onboardingIncompletePhoneContent.
  ///
  /// In zh, this message translates to:
  /// **'请输入正确的手机号。'**
  String get onboardingIncompletePhoneContent;

  /// No description provided for @onboardingMissingOtpTitle.
  ///
  /// In zh, this message translates to:
  /// **'缺少验证码'**
  String get onboardingMissingOtpTitle;

  /// No description provided for @onboardingMissingOtpContent.
  ///
  /// In zh, this message translates to:
  /// **'请输入收到的验证码后再继续。'**
  String get onboardingMissingOtpContent;

  /// No description provided for @onboardingMissingEmailTitle.
  ///
  /// In zh, this message translates to:
  /// **'缺少邮箱'**
  String get onboardingMissingEmailTitle;

  /// No description provided for @onboardingMissingEmailContent.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱地址。'**
  String get onboardingMissingEmailContent;

  /// No description provided for @onboardingNotActivatedTitle.
  ///
  /// In zh, this message translates to:
  /// **'尚未激活'**
  String get onboardingNotActivatedTitle;

  /// No description provided for @onboardingNotActivatedContent.
  ///
  /// In zh, this message translates to:
  /// **'请先完成邮箱激活并检查状态。'**
  String get onboardingNotActivatedContent;

  /// No description provided for @onboardingInvalidHandleTitle.
  ///
  /// In zh, this message translates to:
  /// **'handle 不合法'**
  String get onboardingInvalidHandleTitle;

  /// No description provided for @onboardingInvalidHandleContent.
  ///
  /// In zh, this message translates to:
  /// **'仅支持小写字母、数字、中划线，长度 2-32。'**
  String get onboardingInvalidHandleContent;

  /// No description provided for @onboardingMissingNicknameTitle.
  ///
  /// In zh, this message translates to:
  /// **'缺少昵称'**
  String get onboardingMissingNicknameTitle;

  /// No description provided for @onboardingMissingNicknameContent.
  ///
  /// In zh, this message translates to:
  /// **'请输入昵称。'**
  String get onboardingMissingNicknameContent;

  /// No description provided for @secureMessagingClient.
  ///
  /// In zh, this message translates to:
  /// **'Secure messaging client'**
  String get secureMessagingClient;

  /// No description provided for @shellNavMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get shellNavMessages;

  /// No description provided for @shellNavFriends.
  ///
  /// In zh, this message translates to:
  /// **'朋友'**
  String get shellNavFriends;

  /// No description provided for @shellNavMe.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get shellNavMe;

  /// No description provided for @conversationsTitle.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get conversationsTitle;

  /// No description provided for @conversationsNoMessagePreview.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get conversationsNoMessagePreview;

  /// No description provided for @conversationsEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有消息'**
  String get conversationsEmptyTitle;

  /// No description provided for @conversationsEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'去添加好友、关注联系人，或者先加入一个群聊吧。'**
  String get conversationsEmptySubtitle;

  /// No description provided for @friendsTitle.
  ///
  /// In zh, this message translates to:
  /// **'朋友'**
  String get friendsTitle;

  /// No description provided for @profileMeTitle.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get profileMeTitle;

  /// No description provided for @profileFollowers.
  ///
  /// In zh, this message translates to:
  /// **'粉丝'**
  String get profileFollowers;

  /// No description provided for @profileFollowing.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get profileFollowing;

  /// No description provided for @profileGroups.
  ///
  /// In zh, this message translates to:
  /// **'群组'**
  String get profileGroups;

  /// No description provided for @profileEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无 profile'**
  String get profileEmpty;

  /// No description provided for @profileEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑个人资料'**
  String get profileEditTitle;

  /// No description provided for @profileBioPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'个人简介'**
  String get profileBioPlaceholder;

  /// No description provided for @profileTagsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'标签，使用英文逗号分隔'**
  String get profileTagsPlaceholder;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZhHans.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZhHans;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsPushNotification.
  ///
  /// In zh, this message translates to:
  /// **'消息推送通知'**
  String get settingsPushNotification;

  /// No description provided for @settingsCurrentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本'**
  String get settingsCurrentVersion;

  /// No description provided for @settingsCurrentVersionValue.
  ///
  /// In zh, this message translates to:
  /// **'当前版本：{version}'**
  String settingsCurrentVersionValue(Object version);

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsViewReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'查看更新日志'**
  String get settingsViewReleaseNotes;

  /// No description provided for @settingsInstallUpdate.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get settingsInstallUpdate;

  /// No description provided for @settingsInstallUpdateVersion.
  ///
  /// In zh, this message translates to:
  /// **'安装新版本：{version}'**
  String settingsInstallUpdateVersion(Object version);

  /// No description provided for @settingsDownloadUpdate.
  ///
  /// In zh, this message translates to:
  /// **'下载更新'**
  String get settingsDownloadUpdate;

  /// No description provided for @settingsDownloadUpdateVersion.
  ///
  /// In zh, this message translates to:
  /// **'下载新版本：{version}'**
  String settingsDownloadUpdateVersion(Object version);

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本：{version}'**
  String settingsUpdateAvailable(Object version);

  /// No description provided for @settingsAlreadyLatestVersion.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get settingsAlreadyLatestVersion;

  /// No description provided for @settingsUpdateStatusLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取版本信息...'**
  String get settingsUpdateStatusLoading;

  /// No description provided for @settingsUpdateStatusChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新...'**
  String get settingsUpdateStatusChecking;

  /// No description provided for @settingsUpdateStatusDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载更新...'**
  String get settingsUpdateStatusDownloading;

  /// No description provided for @settingsUpdateStatusInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在准备安装更新...'**
  String get settingsUpdateStatusInstalling;

  /// No description provided for @settingsUpdateStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请稍后重试'**
  String get settingsUpdateStatusFailed;

  /// No description provided for @settingsUpdateReleaseNotesVersion.
  ///
  /// In zh, this message translates to:
  /// **'查看版本 {version} 的更新日志'**
  String settingsUpdateReleaseNotesVersion(Object version);

  /// No description provided for @settingsUpdateOpenGitHubHistory.
  ///
  /// In zh, this message translates to:
  /// **'前往 GitHub 查阅历史版本'**
  String get settingsUpdateOpenGitHubHistory;

  /// No description provided for @settingsUpdateOpenGitHubDownload.
  ///
  /// In zh, this message translates to:
  /// **'前往 GitHub 下载当前版本'**
  String get settingsUpdateOpenGitHubDownload;

  /// No description provided for @settingsExportCredential.
  ///
  /// In zh, this message translates to:
  /// **'导出身份凭证'**
  String get settingsExportCredential;

  /// No description provided for @settingsExportCurrentCredential.
  ///
  /// In zh, this message translates to:
  /// **'导出当前凭证：{credentialName}'**
  String settingsExportCurrentCredential(Object credentialName);

  /// No description provided for @settingsNoCredentialToExport.
  ///
  /// In zh, this message translates to:
  /// **'当前暂无可导出的登录凭证'**
  String get settingsNoCredentialToExport;

  /// No description provided for @settingsLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get settingsLogout;

  /// No description provided for @settingsLogoutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'清除本地登录状态并返回登录页'**
  String get settingsLogoutSubtitle;

  /// No description provided for @settingsDeleteCredential.
  ///
  /// In zh, this message translates to:
  /// **'退出并删除当前凭证'**
  String get settingsDeleteCredential;

  /// No description provided for @settingsDeleteCurrentCredential.
  ///
  /// In zh, this message translates to:
  /// **'删除本地凭证：{credentialName}'**
  String settingsDeleteCurrentCredential(Object credentialName);

  /// No description provided for @settingsDeleteCredentialFallback.
  ///
  /// In zh, this message translates to:
  /// **'退出并删除当前登录凭证'**
  String get settingsDeleteCredentialFallback;

  /// No description provided for @settingsLogoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get settingsLogoutConfirmTitle;

  /// No description provided for @settingsLogoutConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要退出当前账号吗？'**
  String get settingsLogoutConfirmContent;

  /// No description provided for @settingsDeleteCredentialConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出并删除当前凭证'**
  String get settingsDeleteCredentialConfirmTitle;

  /// No description provided for @settingsDeleteCredentialConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'将退出当前登录，并删除本地凭证 \"{credentialName}\"。删除后需要重新导入或恢复身份才能再次使用该凭证。确定继续吗？'**
  String settingsDeleteCredentialConfirmContent(Object credentialName);

  /// No description provided for @settingsDeleteCredentialConfirmAction.
  ///
  /// In zh, this message translates to:
  /// **'退出并删除'**
  String get settingsDeleteCredentialConfirmAction;

  /// No description provided for @quickActionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get quickActionsTitle;

  /// No description provided for @quickActionCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'发起群聊'**
  String get quickActionCreateGroup;

  /// No description provided for @quickActionJoinGroup.
  ///
  /// In zh, this message translates to:
  /// **'加入群聊'**
  String get quickActionJoinGroup;

  /// No description provided for @quickActionAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'添加朋友'**
  String get quickActionAddFriend;

  /// No description provided for @addFriendTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加朋友'**
  String get addFriendTitle;

  /// No description provided for @addFriendPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入 Handle 或 DID'**
  String get addFriendPlaceholder;

  /// No description provided for @addFriendAlreadyExists.
  ///
  /// In zh, this message translates to:
  /// **'已经添加或正在申请中'**
  String get addFriendAlreadyExists;

  /// No description provided for @addFriendFollowed.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get addFriendFollowed;

  /// No description provided for @groupListTitle.
  ///
  /// In zh, this message translates to:
  /// **'群聊列表'**
  String get groupListTitle;

  /// No description provided for @groupListEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有群组。先创建一个群，或使用 Group DID 加入。'**
  String get groupListEmpty;

  /// No description provided for @groupListLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载群数据...'**
  String get groupListLoading;

  /// No description provided for @groupJoinDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'通过 Group DID 入群'**
  String get groupJoinDialogTitle;

  /// No description provided for @groupJoinDialogPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入群组 Group DID'**
  String get groupJoinDialogPlaceholder;

  /// No description provided for @groupNoDescription.
  ///
  /// In zh, this message translates to:
  /// **'暂无群描述'**
  String get groupNoDescription;

  /// No description provided for @groupMemberCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 人'**
  String groupMemberCount(int count);

  /// No description provided for @groupMemberCountCompact.
  ///
  /// In zh, this message translates to:
  /// **'{count}人'**
  String groupMemberCountCompact(int count);

  /// No description provided for @groupIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'Group DID: {groupId}'**
  String groupIdLabel(Object groupId);

  /// No description provided for @groupEnterChat.
  ///
  /// In zh, this message translates to:
  /// **'进入群聊'**
  String get groupEnterChat;

  /// No description provided for @groupRefreshSnapshot.
  ///
  /// In zh, this message translates to:
  /// **'刷新群详情与成员'**
  String get groupRefreshSnapshot;

  /// No description provided for @groupMembersTitle.
  ///
  /// In zh, this message translates to:
  /// **'群成员'**
  String get groupMembersTitle;

  /// No description provided for @groupMembersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无成员快照，先执行一次刷新群详情与成员。'**
  String get groupMembersEmpty;

  /// No description provided for @groupCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建群组'**
  String get groupCreateTitle;

  /// No description provided for @groupFieldName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get groupFieldName;

  /// No description provided for @groupFieldNamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'群组名称'**
  String get groupFieldNamePlaceholder;

  /// No description provided for @groupFieldSlug.
  ///
  /// In zh, this message translates to:
  /// **'短链接'**
  String get groupFieldSlug;

  /// No description provided for @groupFieldSlugPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'可选，不填则自动生成'**
  String get groupFieldSlugPlaceholder;

  /// No description provided for @groupFieldDescription.
  ///
  /// In zh, this message translates to:
  /// **'介绍'**
  String get groupFieldDescription;

  /// No description provided for @groupFieldDescriptionPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'群资料介绍'**
  String get groupFieldDescriptionPlaceholder;

  /// No description provided for @groupFieldGoal.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get groupFieldGoal;

  /// No description provided for @groupFieldGoalPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'建群目标'**
  String get groupFieldGoalPlaceholder;

  /// No description provided for @groupFieldRules.
  ///
  /// In zh, this message translates to:
  /// **'规则'**
  String get groupFieldRules;

  /// No description provided for @groupFieldRulesPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'社群规则'**
  String get groupFieldRulesPlaceholder;

  /// No description provided for @groupFieldPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示'**
  String get groupFieldPrompt;

  /// No description provided for @groupFieldPromptPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'发声引导 Message Prompt'**
  String get groupFieldPromptPlaceholder;

  /// No description provided for @groupCreating.
  ///
  /// In zh, this message translates to:
  /// **'正在创建群组...'**
  String get groupCreating;

  /// No description provided for @chatUnknownUser.
  ///
  /// In zh, this message translates to:
  /// **'Unknown'**
  String get chatUnknownUser;

  /// No description provided for @chatConversationUntitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名会话'**
  String get chatConversationUntitled;

  /// No description provided for @chatHeaderGroup.
  ///
  /// In zh, this message translates to:
  /// **'GROUP'**
  String get chatHeaderGroup;

  /// No description provided for @chatHeaderOnline.
  ///
  /// In zh, this message translates to:
  /// **'ONLINE'**
  String get chatHeaderOnline;

  /// No description provided for @chatInputPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'Type a message...'**
  String get chatInputPlaceholder;

  /// No description provided for @peerProfileLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法加载该用户的信息'**
  String get peerProfileLoadFailed;

  /// No description provided for @peerProfileTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get peerProfileTitle;

  /// No description provided for @peerProfileSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'发消息'**
  String get peerProfileSendMessage;

  /// No description provided for @peerProfileUnfollow.
  ///
  /// In zh, this message translates to:
  /// **'取消关注'**
  String get peerProfileUnfollow;

  /// No description provided for @peerProfileDeleteThread.
  ///
  /// In zh, this message translates to:
  /// **'删除本地聊天记录'**
  String get peerProfileDeleteThread;

  /// No description provided for @peerProfileUnfollowed.
  ///
  /// In zh, this message translates to:
  /// **'已取消关注'**
  String get peerProfileUnfollowed;

  /// No description provided for @peerProfileThreadDeleted.
  ///
  /// In zh, this message translates to:
  /// **'本地聊天记录已删除'**
  String get peerProfileThreadDeleted;

  /// No description provided for @relationshipNone.
  ///
  /// In zh, this message translates to:
  /// **'none'**
  String get relationshipNone;

  /// No description provided for @relationshipFollowing.
  ///
  /// In zh, this message translates to:
  /// **'following'**
  String get relationshipFollowing;

  /// No description provided for @relationshipFollower.
  ///
  /// In zh, this message translates to:
  /// **'follower'**
  String get relationshipFollower;

  /// No description provided for @relationshipFriend.
  ///
  /// In zh, this message translates to:
  /// **'friend'**
  String get relationshipFriend;

  /// No description provided for @profileUpdated.
  ///
  /// In zh, this message translates to:
  /// **'个人资料已更新'**
  String get profileUpdated;

  /// No description provided for @exportedTo.
  ///
  /// In zh, this message translates to:
  /// **'已导出到 {path}'**
  String exportedTo(Object path);

  /// No description provided for @importSuccessSelectCredential.
  ///
  /// In zh, this message translates to:
  /// **'导入成功，请选择该凭证登录'**
  String get importSuccessSelectCredential;

  /// No description provided for @localCredentialsRefreshed.
  ///
  /// In zh, this message translates to:
  /// **'已重新识别到 {count} 个本地凭证'**
  String localCredentialsRefreshed(Object count);

  /// No description provided for @noLocalCredentialsFound.
  ///
  /// In zh, this message translates to:
  /// **'未识别到本地凭证'**
  String get noLocalCredentialsFound;

  /// No description provided for @newMessageArrived.
  ///
  /// In zh, this message translates to:
  /// **'你收到了新消息'**
  String get newMessageArrived;

  /// No description provided for @updateAlreadyLatest.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get updateAlreadyLatest;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请稍后重试。'**
  String get updateCheckFailed;

  /// No description provided for @updateOpenReleaseNotesFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开更新日志，请稍后重试。'**
  String get updateOpenReleaseNotesFailed;

  /// No description provided for @updateOpenDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开下载页面，请前往 GitHub Release。'**
  String get updateOpenDownloadFailed;

  /// No description provided for @updateReadyToInstall.
  ///
  /// In zh, this message translates to:
  /// **'下载完成，准备安装。'**
  String get updateReadyToInstall;

  /// No description provided for @updatePermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'请允许安装未知应用后重试。'**
  String get updatePermissionRequired;

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败，请前往 GitHub 下载。'**
  String get updateInstallFailed;

  /// No description provided for @requestTimeoutRetry.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请检查网络后重试。'**
  String get requestTimeoutRetry;

  /// No description provided for @networkUnavailableRetry.
  ///
  /// In zh, this message translates to:
  /// **'网络连接暂时不可用，请检查网络后重试。'**
  String get networkUnavailableRetry;

  /// No description provided for @operationFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请稍后重试。'**
  String get operationFailedRetry;

  /// No description provided for @featureNotImplemented.
  ///
  /// In zh, this message translates to:
  /// **'功能暂未实现，请等待后续版本。'**
  String get featureNotImplemented;

  /// No description provided for @otpSent.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送，请留意短信。'**
  String get otpSent;

  /// No description provided for @activationEmailSent.
  ///
  /// In zh, this message translates to:
  /// **'激活邮件已发送，请查收邮箱。'**
  String get activationEmailSent;

  /// No description provided for @emailLoginUnsupportedForRegisteredHandle.
  ///
  /// In zh, this message translates to:
  /// **'该 handle 已注册。邮箱当前仅支持新注册，请使用手机号验证码登录或导入身份凭证。'**
  String get emailLoginUnsupportedForRegisteredHandle;

  /// No description provided for @emailNotActivatedClickLink.
  ///
  /// In zh, this message translates to:
  /// **'邮箱尚未激活，请先点击邮件中的激活链接。'**
  String get emailNotActivatedClickLink;

  /// No description provided for @sessionExpiredRelogin.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效，请重新登录。'**
  String get sessionExpiredRelogin;

  /// No description provided for @didNotFoundOrRevoked.
  ///
  /// In zh, this message translates to:
  /// **'未找到这个身份，或它已经被撤销。请检查 DID 是否正确，或切换到可用身份后重试。'**
  String get didNotFoundOrRevoked;

  /// No description provided for @localCredentialNotFound.
  ///
  /// In zh, this message translates to:
  /// **'本地未找到凭证：{credentialName}'**
  String localCredentialNotFound(Object credentialName);

  /// No description provided for @setupIdentityScriptMissing.
  ///
  /// In zh, this message translates to:
  /// **'当前版本不再支持旧版脚本凭证，请重新创建或导入新版 e1 DID 凭证。'**
  String get setupIdentityScriptMissing;

  /// No description provided for @deleteCredentialFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除凭证失败：{credentialName}'**
  String deleteCredentialFailed(Object credentialName);

  /// No description provided for @noCredentialToExport.
  ///
  /// In zh, this message translates to:
  /// **'当前没有已登录凭证可导出。'**
  String get noCredentialToExport;

  /// No description provided for @credentialPackFailed.
  ///
  /// In zh, this message translates to:
  /// **'凭证打包失败，请稍后重试。'**
  String get credentialPackFailed;

  /// No description provided for @localCredentialDirectoryMissing.
  ///
  /// In zh, this message translates to:
  /// **'无法定位本地凭证目录。'**
  String get localCredentialDirectoryMissing;

  /// No description provided for @exportUnsupportedOnPlatform.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持导出身份凭证。'**
  String get exportUnsupportedOnPlatform;

  /// No description provided for @importUnsupportedOnPlatform.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持导入身份凭证。'**
  String get importUnsupportedOnPlatform;

  /// No description provided for @currentCredentialIndexMissing.
  ///
  /// In zh, this message translates to:
  /// **'未找到当前凭证的本地索引信息。'**
  String get currentCredentialIndexMissing;

  /// No description provided for @currentCredentialDidInvalid.
  ///
  /// In zh, this message translates to:
  /// **'当前凭证的 DID 文档格式不正确。'**
  String get currentCredentialDidInvalid;

  /// No description provided for @zipMissingMetadata.
  ///
  /// In zh, this message translates to:
  /// **'ZIP 包缺少必要的凭证元信息。'**
  String get zipMissingMetadata;

  /// No description provided for @zipCredentialIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'ZIP 包中的凭证内容不完整。'**
  String get zipCredentialIncomplete;

  /// No description provided for @invalidFileFormat.
  ///
  /// In zh, this message translates to:
  /// **'文件格式不正确：{path}'**
  String invalidFileFormat(Object path);

  /// No description provided for @phoneInvalidIntlExample.
  ///
  /// In zh, this message translates to:
  /// **'手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000'**
  String get phoneInvalidIntlExample;

  /// No description provided for @phoneInvalidIntlOrCn.
  ///
  /// In zh, this message translates to:
  /// **'手机号格式不正确，请输入国际格式或中国大陆 11 位手机号'**
  String get phoneInvalidIntlOrCn;

  /// No description provided for @handleInvalidPattern.
  ///
  /// In zh, this message translates to:
  /// **'handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线'**
  String get handleInvalidPattern;

  /// No description provided for @didRegistrationPluginMissing.
  ///
  /// In zh, this message translates to:
  /// **'AWiki Me 当前无法创建 DID（{authHint}注册）。请确认 Dart ANP SDK 初始化成功。'**
  String didRegistrationPluginMissing(Object authHint);

  /// No description provided for @didRegistrationRefreshUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'AWiki Me 当前未接入 DID 注册插件，无法自动刷新 token。'**
  String get didRegistrationRefreshUnsupported;

  /// No description provided for @e2eePluginMissing.
  ///
  /// In zh, this message translates to:
  /// **'AWiki Me 当前未启用 E2EE，请接入原生插件实现'**
  String get e2eePluginMissing;

  /// No description provided for @documentPickerFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件选择失败，请稍后重试。'**
  String get documentPickerFailed;

  /// No description provided for @linkOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开链接'**
  String get linkOpenFailed;

  /// No description provided for @linkOpenFailedWithDetail.
  ///
  /// In zh, this message translates to:
  /// **'无法打开链接: {detail}'**
  String linkOpenFailedWithDetail(Object detail);

  /// No description provided for @groupNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'群名称不能为空'**
  String get groupNameRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
