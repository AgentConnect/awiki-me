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
  /// **'AWikiMe'**
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

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonDetails.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get commonDetails;

  /// No description provided for @commonMoreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get commonMoreActions;

  /// No description provided for @commonSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get commonSearch;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get commonCopied;

  /// No description provided for @commonCopyDetails.
  ///
  /// In zh, this message translates to:
  /// **'复制详情'**
  String get commonCopyDetails;

  /// No description provided for @commonReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get commonReject;

  /// No description provided for @commonRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get commonRemove;

  /// No description provided for @commonPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get commonPause;

  /// No description provided for @commonRevoke.
  ///
  /// In zh, this message translates to:
  /// **'撤销授权'**
  String get commonRevoke;

  /// No description provided for @commonUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get commonUnknown;

  /// No description provided for @commonLoadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get commonLoadMore;

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

  /// No description provided for @commonErrorDetails.
  ///
  /// In zh, this message translates to:
  /// **'错误详情'**
  String get commonErrorDetails;

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

  /// No description provided for @onboardingLoadingServerInfo.
  ///
  /// In zh, this message translates to:
  /// **'正在读取当前服务器支持的登录方式...'**
  String get onboardingLoadingServerInfo;

  /// No description provided for @onboardingServerInfoLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取当前服务器支持的登录方式。请检查租户地址后重试。'**
  String get onboardingServerInfoLoadFailed;

  /// No description provided for @onboardingRegistrationUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器暂不支持在 APP 内注册身份。'**
  String get onboardingRegistrationUnavailable;

  /// No description provided for @onboardingNoVerificationHint.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器不需要短信或邮箱验证码，可直接创建新身份。'**
  String get onboardingNoVerificationHint;

  /// No description provided for @handleAlreadyRegisteredImportCredential.
  ///
  /// In zh, this message translates to:
  /// **'这个 handle 已经存在。当前服务器不支持无验证码恢复，请导入已有身份凭证或联系服务器管理员。'**
  String get handleAlreadyRegisteredImportCredential;

  /// No description provided for @registrationMethodUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器不支持所选注册方式，请刷新后重试。'**
  String get registrationMethodUnavailable;

  /// No description provided for @tenantSwitcherLabel.
  ///
  /// In zh, this message translates to:
  /// **'管理租户'**
  String get tenantSwitcherLabel;

  /// No description provided for @tenantManagementTitle.
  ///
  /// In zh, this message translates to:
  /// **'租户'**
  String get tenantManagementTitle;

  /// No description provided for @tenantManagementSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换这个 App 使用的后端和 DID Host。'**
  String get tenantManagementSubtitle;

  /// No description provided for @tenantPrimaryAgentNote.
  ///
  /// In zh, this message translates to:
  /// **'Agent 和 Daemon 功能支持已批准的 AWiki 租户域名。'**
  String get tenantPrimaryAgentNote;

  /// No description provided for @tenantCreate.
  ///
  /// In zh, this message translates to:
  /// **'添加租户配置'**
  String get tenantCreate;

  /// No description provided for @tenantEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑租户'**
  String get tenantEdit;

  /// No description provided for @tenantUse.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get tenantUse;

  /// No description provided for @tenantCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get tenantCurrent;

  /// No description provided for @tenantName.
  ///
  /// In zh, this message translates to:
  /// **'租户名称'**
  String get tenantName;

  /// No description provided for @tenantNamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'团队或服务名称'**
  String get tenantNamePlaceholder;

  /// No description provided for @tenantBackendBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'后端地址'**
  String get tenantBackendBaseUrl;

  /// No description provided for @tenantBackendBaseUrlPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com'**
  String get tenantBackendBaseUrlPlaceholder;

  /// No description provided for @tenantDidHost.
  ///
  /// In zh, this message translates to:
  /// **'DID Host'**
  String get tenantDidHost;

  /// No description provided for @tenantDidHostPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'example.com'**
  String get tenantDidHostPlaceholder;

  /// No description provided for @tenantCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加租户配置'**
  String get tenantCreateTitle;

  /// No description provided for @tenantEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑租户'**
  String get tenantEditTitle;

  /// No description provided for @tenantSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中...'**
  String get tenantSaving;

  /// No description provided for @tenantDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除租户'**
  String get tenantDeleteTitle;

  /// No description provided for @tenantDeleteContent.
  ///
  /// In zh, this message translates to:
  /// **'删除 {tenantName}？本机数据会保留，但这个租户不会再出现在切换列表中。'**
  String tenantDeleteContent(Object tenantName);

  /// No description provided for @tenantCannotEditDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认 AWiki 租户不能编辑。接入其他后端请添加租户配置。'**
  String get tenantCannotEditDefault;

  /// No description provided for @tenantCannotEditWithData.
  ///
  /// In zh, this message translates to:
  /// **'这个租户已经有本地数据，只能修改名称，不能修改后端地址或 DID Host。'**
  String get tenantCannotEditWithData;

  /// No description provided for @tenantCannotDeleteDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认 AWiki 租户不能删除。'**
  String get tenantCannotDeleteDefault;

  /// No description provided for @tenantCannotDeleteActive.
  ///
  /// In zh, this message translates to:
  /// **'请先切换到其他租户，再删除当前租户。'**
  String get tenantCannotDeleteActive;

  /// No description provided for @tenantValidationNameInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 1-40 个可见字符作为本地显示名称，不能包含不可见控制字符。'**
  String get tenantValidationNameInvalid;

  /// No description provided for @tenantValidationBackendInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 http 或 https 后端地址，不能包含 query 或 fragment。'**
  String get tenantValidationBackendInvalid;

  /// No description provided for @tenantValidationDidHostInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 DID Host，例如 example.com。'**
  String get tenantValidationDidHostInvalid;

  /// No description provided for @tenantValidationNameExists.
  ///
  /// In zh, this message translates to:
  /// **'已经存在同名租户。'**
  String get tenantValidationNameExists;

  /// No description provided for @tenantValidationEndpointExists.
  ///
  /// In zh, this message translates to:
  /// **'已经存在相同后端和 DID Host 的租户。'**
  String get tenantValidationEndpointExists;

  /// No description provided for @tenantValidationHasData.
  ///
  /// In zh, this message translates to:
  /// **'这个租户已经有本地数据，只能修改名称；如需更换后端或 DID Host，请添加租户配置。'**
  String get tenantValidationHasData;

  /// No description provided for @tenantNotFound.
  ///
  /// In zh, this message translates to:
  /// **'租户不存在。'**
  String get tenantNotFound;

  /// No description provided for @tenantOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'租户操作失败，请稍后重试。'**
  String get tenantOperationFailed;

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

  /// No description provided for @onboardingMacHeroPrefix.
  ///
  /// In zh, this message translates to:
  /// **'连接你的 '**
  String get onboardingMacHeroPrefix;

  /// No description provided for @onboardingMacHeroHighlight.
  ///
  /// In zh, this message translates to:
  /// **'Agent'**
  String get onboardingMacHeroHighlight;

  /// No description provided for @onboardingMacHeroSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 世界'**
  String get onboardingMacHeroSuffix;

  /// No description provided for @onboardingMacSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'安全连接人、Agent 与组织，协作更智能，决策更高效。'**
  String get onboardingMacSubtitle;

  /// No description provided for @onboardingMacFeatureSecureTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全可靠'**
  String get onboardingMacFeatureSecureTitle;

  /// No description provided for @onboardingMacFeatureSecureSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'企业级安全防护体系'**
  String get onboardingMacFeatureSecureSubtitle;

  /// No description provided for @onboardingMacFeatureCollaborateTitle.
  ///
  /// In zh, this message translates to:
  /// **'高效协作'**
  String get onboardingMacFeatureCollaborateTitle;

  /// No description provided for @onboardingMacFeatureCollaborateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'人机协同，信息无缝流转'**
  String get onboardingMacFeatureCollaborateSubtitle;

  /// No description provided for @onboardingMacFeatureControlTitle.
  ///
  /// In zh, this message translates to:
  /// **'权限可控'**
  String get onboardingMacFeatureControlTitle;

  /// No description provided for @onboardingMacFeatureControlSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'精细化权限，数据更安心'**
  String get onboardingMacFeatureControlSubtitle;

  /// No description provided for @onboardingMacChipRequirementsAgent.
  ///
  /// In zh, this message translates to:
  /// **'需求调研 Agent'**
  String get onboardingMacChipRequirementsAgent;

  /// No description provided for @onboardingMacChipRequirementsAgentCompact.
  ///
  /// In zh, this message translates to:
  /// **'需求调研'**
  String get onboardingMacChipRequirementsAgentCompact;

  /// No description provided for @onboardingMacChipPlanningAgent.
  ///
  /// In zh, this message translates to:
  /// **'任务拆分 Agent'**
  String get onboardingMacChipPlanningAgent;

  /// No description provided for @onboardingMacChipPlanningAgentCompact.
  ///
  /// In zh, this message translates to:
  /// **'任务拆分'**
  String get onboardingMacChipPlanningAgentCompact;

  /// No description provided for @onboardingMacChipCodingAgent.
  ///
  /// In zh, this message translates to:
  /// **'编码实现 Agent'**
  String get onboardingMacChipCodingAgent;

  /// No description provided for @onboardingMacChipCodingAgentCompact.
  ///
  /// In zh, this message translates to:
  /// **'编码实现'**
  String get onboardingMacChipCodingAgentCompact;

  /// No description provided for @onboardingMacChipUiDesignAgent.
  ///
  /// In zh, this message translates to:
  /// **'UI 设计 Agent'**
  String get onboardingMacChipUiDesignAgent;

  /// No description provided for @onboardingMacChipUiDesignAgentCompact.
  ///
  /// In zh, this message translates to:
  /// **'UI 设计'**
  String get onboardingMacChipUiDesignAgentCompact;

  /// No description provided for @onboardingMacVerified.
  ///
  /// In zh, this message translates to:
  /// **'已认证'**
  String get onboardingMacVerified;

  /// No description provided for @onboardingMacOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get onboardingMacOnline;

  /// No description provided for @onboardingCredentialsField.
  ///
  /// In zh, this message translates to:
  /// **'身份凭证'**
  String get onboardingCredentialsField;

  /// No description provided for @onboardingNoLocalCredentialSaved.
  ///
  /// In zh, this message translates to:
  /// **'本机暂无已保存身份凭证'**
  String get onboardingNoLocalCredentialSaved;

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

  /// No description provided for @shellNavAgents.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get shellNavAgents;

  /// No description provided for @shellNavFriends.
  ///
  /// In zh, this message translates to:
  /// **'朋友'**
  String get shellNavFriends;

  /// No description provided for @shellNavContacts.
  ///
  /// In zh, this message translates to:
  /// **'联系人'**
  String get shellNavContacts;

  /// No description provided for @shellNavTasks.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get shellNavTasks;

  /// No description provided for @shellNavWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'工作台'**
  String get shellNavWorkspace;

  /// No description provided for @shellNavSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get shellNavSettings;

  /// No description provided for @shellNavMe.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get shellNavMe;

  /// No description provided for @shellTasksPlaceholderTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get shellTasksPlaceholderTitle;

  /// No description provided for @shellTasksPlaceholderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'任务视图即将接入。当前任务状态会在会话与身份卡中展示。'**
  String get shellTasksPlaceholderSubtitle;

  /// No description provided for @shellWorkspacePlaceholderTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作台'**
  String get shellWorkspacePlaceholderTitle;

  /// No description provided for @shellWorkspacePlaceholderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'工作台模块即将接入。'**
  String get shellWorkspacePlaceholderSubtitle;

  /// No description provided for @conversationsTitle.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
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
  /// **'去关注联系人，或者先加入一个群聊吧。'**
  String get conversationsEmptySubtitle;

  /// No description provided for @conversationsRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近会话'**
  String get conversationsRecentTitle;

  /// No description provided for @conversationsSearchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'搜索会话'**
  String get conversationsSearchPlaceholder;

  /// No description provided for @conversationsNoResultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关会话'**
  String get conversationsNoResultsTitle;

  /// No description provided for @conversationsNoResultsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词试试'**
  String get conversationsNoResultsSubtitle;

  /// No description provided for @conversationsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除会话'**
  String get conversationsDeleteTitle;

  /// No description provided for @conversationsDeleteContent.
  ///
  /// In zh, this message translates to:
  /// **'会话将从最近列表移除，历史消息仍会保留。重新打开或收到新消息后，会话会再次出现在列表中。'**
  String get conversationsDeleteContent;

  /// No description provided for @conversationsUnreadTag.
  ///
  /// In zh, this message translates to:
  /// **'未读 {count}'**
  String conversationsUnreadTag(Object count);

  /// No description provided for @conversationsMentionMeTag.
  ///
  /// In zh, this message translates to:
  /// **'@我'**
  String get conversationsMentionMeTag;

  /// No description provided for @conversationsDraftTag.
  ///
  /// In zh, this message translates to:
  /// **'草稿'**
  String get conversationsDraftTag;

  /// No description provided for @conversationsAttachmentPreview.
  ///
  /// In zh, this message translates to:
  /// **'附件：{name}'**
  String conversationsAttachmentPreview(Object name);

  /// No description provided for @conversationsDeletedAgentBadge.
  ///
  /// In zh, this message translates to:
  /// **'智能体已删除'**
  String get conversationsDeletedAgentBadge;

  /// No description provided for @conversationsNewMessages.
  ///
  /// In zh, this message translates to:
  /// **'有新消息'**
  String get conversationsNewMessages;

  /// No description provided for @conversationPeerBadgeGroup.
  ///
  /// In zh, this message translates to:
  /// **'群'**
  String get conversationPeerBadgeGroup;

  /// No description provided for @conversationPeerBadgeAi.
  ///
  /// In zh, this message translates to:
  /// **'AI'**
  String get conversationPeerBadgeAi;

  /// No description provided for @conversationPeerChatBadgeMyAgent.
  ///
  /// In zh, this message translates to:
  /// **'我的智能体'**
  String get conversationPeerChatBadgeMyAgent;

  /// No description provided for @conversationPeerChatBadgeAgent.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get conversationPeerChatBadgeAgent;

  /// No description provided for @conversationPeerTypeGroup.
  ///
  /// In zh, this message translates to:
  /// **'群聊'**
  String get conversationPeerTypeGroup;

  /// No description provided for @conversationPeerTypeAgent.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get conversationPeerTypeAgent;

  /// No description provided for @conversationPeerTypeUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get conversationPeerTypeUser;

  /// No description provided for @conversationPeerOwnerGroup.
  ///
  /// In zh, this message translates to:
  /// **'AWiki 群组'**
  String get conversationPeerOwnerGroup;

  /// No description provided for @conversationPeerOwnerMyRuntimeAgent.
  ///
  /// In zh, this message translates to:
  /// **'本机 Runtime Agent'**
  String get conversationPeerOwnerMyRuntimeAgent;

  /// No description provided for @conversationPeerOwnerAgent.
  ///
  /// In zh, this message translates to:
  /// **'AWiki 智能体'**
  String get conversationPeerOwnerAgent;

  /// No description provided for @conversationPeerOwnerUser.
  ///
  /// In zh, this message translates to:
  /// **'AWiki 用户'**
  String get conversationPeerOwnerUser;

  /// No description provided for @conversationInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'会话信息'**
  String get conversationInfoTitle;

  /// No description provided for @conversationIdentityStatus.
  ///
  /// In zh, this message translates to:
  /// **'身份状态:'**
  String get conversationIdentityStatus;

  /// No description provided for @conversationIdentityVerified.
  ///
  /// In zh, this message translates to:
  /// **'已验证'**
  String get conversationIdentityVerified;

  /// No description provided for @conversationOwnerLabel.
  ///
  /// In zh, this message translates to:
  /// **'所属:'**
  String get conversationOwnerLabel;

  /// No description provided for @conversationTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'类型:'**
  String get conversationTypeLabel;

  /// No description provided for @conversationCapabilitiesTitle.
  ///
  /// In zh, this message translates to:
  /// **'会话能力'**
  String get conversationCapabilitiesTitle;

  /// No description provided for @conversationCapabilitySendMessage.
  ///
  /// In zh, this message translates to:
  /// **'发送消息'**
  String get conversationCapabilitySendMessage;

  /// No description provided for @conversationCapabilityViewProfile.
  ///
  /// In zh, this message translates to:
  /// **'查看资料'**
  String get conversationCapabilityViewProfile;

  /// No description provided for @conversationCapabilitySecureConnection.
  ///
  /// In zh, this message translates to:
  /// **'安全连接'**
  String get conversationCapabilitySecureConnection;

  /// No description provided for @conversationCapabilityHistory.
  ///
  /// In zh, this message translates to:
  /// **'会话记录'**
  String get conversationCapabilityHistory;

  /// No description provided for @conversationStatusTitle.
  ///
  /// In zh, this message translates to:
  /// **'会话状态'**
  String get conversationStatusTitle;

  /// No description provided for @conversationUnreadMessagesLabel.
  ///
  /// In zh, this message translates to:
  /// **'未读消息:'**
  String get conversationUnreadMessagesLabel;

  /// No description provided for @conversationUnreadMessagesValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String conversationUnreadMessagesValue(int count);

  /// No description provided for @conversationLatestPreviewLabel.
  ///
  /// In zh, this message translates to:
  /// **'最近预览:'**
  String get conversationLatestPreviewLabel;

  /// No description provided for @conversationConnectionStatusLabel.
  ///
  /// In zh, this message translates to:
  /// **'连接状态:'**
  String get conversationConnectionStatusLabel;

  /// No description provided for @conversationConnectionEstablished.
  ///
  /// In zh, this message translates to:
  /// **'已建立'**
  String get conversationConnectionEstablished;

  /// No description provided for @conversationBackToChat.
  ///
  /// In zh, this message translates to:
  /// **'返回会话'**
  String get conversationBackToChat;

  /// No description provided for @friendsTitle.
  ///
  /// In zh, this message translates to:
  /// **'朋友'**
  String get friendsTitle;

  /// No description provided for @friendsGroups.
  ///
  /// In zh, this message translates to:
  /// **'群组'**
  String get friendsGroups;

  /// No description provided for @friendsFollowing.
  ///
  /// In zh, this message translates to:
  /// **'我关注的'**
  String get friendsFollowing;

  /// No description provided for @friendsFollowers.
  ///
  /// In zh, this message translates to:
  /// **'关注我的'**
  String get friendsFollowers;

  /// No description provided for @friendsViewAll.
  ///
  /// In zh, this message translates to:
  /// **'查看全部'**
  String get friendsViewAll;

  /// No description provided for @friendsFollow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get friendsFollow;

  /// No description provided for @friendsUnfollow.
  ///
  /// In zh, this message translates to:
  /// **'取消关注'**
  String get friendsUnfollow;

  /// No description provided for @friendsFollowingEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有关注任何人。'**
  String get friendsFollowingEmpty;

  /// No description provided for @friendsFollowersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有新的关注者。'**
  String get friendsFollowersEmpty;

  /// No description provided for @friendsUnfollowTitle.
  ///
  /// In zh, this message translates to:
  /// **'取消关注'**
  String get friendsUnfollowTitle;

  /// No description provided for @friendsUnfollowMessage.
  ///
  /// In zh, this message translates to:
  /// **'取消关注后，对方会从“我关注的”列表中移除。'**
  String get friendsUnfollowMessage;

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

  /// No description provided for @profileOpenHomepage.
  ///
  /// In zh, this message translates to:
  /// **'打开主页'**
  String get profileOpenHomepage;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsDevices.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get settingsDevices;

  /// No description provided for @settingsDevicesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看已授权设备并审批新设备'**
  String get settingsDevicesSubtitle;

  /// No description provided for @devicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'设备管理'**
  String get devicesTitle;

  /// No description provided for @devicesAuthorizedTitle.
  ///
  /// In zh, this message translates to:
  /// **'已授权设备'**
  String get devicesAuthorizedTitle;

  /// No description provided for @devicesPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'待审批'**
  String get devicesPendingTitle;

  /// No description provided for @devicesLocalJoinsTitle.
  ///
  /// In zh, this message translates to:
  /// **'未完成的设备关联'**
  String get devicesLocalJoinsTitle;

  /// No description provided for @devicesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无设备信息'**
  String get devicesEmpty;

  /// No description provided for @devicesPendingEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前没有待审批请求'**
  String get devicesPendingEmpty;

  /// No description provided for @deviceCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前设备'**
  String get deviceCurrent;

  /// No description provided for @deviceRoleMember.
  ///
  /// In zh, this message translates to:
  /// **'普通设备'**
  String get deviceRoleMember;

  /// No description provided for @deviceRoleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理设备'**
  String get deviceRoleAdmin;

  /// No description provided for @deviceStatusActive.
  ///
  /// In zh, this message translates to:
  /// **'有效'**
  String get deviceStatusActive;

  /// No description provided for @deviceStatusRevoked.
  ///
  /// In zh, this message translates to:
  /// **'已撤销'**
  String get deviceStatusRevoked;

  /// No description provided for @deviceManagementReady.
  ///
  /// In zh, this message translates to:
  /// **'可管理其他设备'**
  String get deviceManagementReady;

  /// No description provided for @deviceManagementPending.
  ///
  /// In zh, this message translates to:
  /// **'等待管理能力就绪'**
  String get deviceManagementPending;

  /// No description provided for @deviceReviewAction.
  ///
  /// In zh, this message translates to:
  /// **'查看并验证'**
  String get deviceReviewAction;

  /// No description provided for @deviceResumeAction.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get deviceResumeAction;

  /// No description provided for @deviceJoinEntry.
  ///
  /// In zh, this message translates to:
  /// **'将此设备加入已有账户'**
  String get deviceJoinEntry;

  /// No description provided for @deviceJoinEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'需要已有管理设备确认两端的 6 位验证码'**
  String get deviceJoinEntrySubtitle;

  /// No description provided for @deviceJoinTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加新设备'**
  String get deviceJoinTitle;

  /// No description provided for @deviceJoinHandle.
  ///
  /// In zh, this message translates to:
  /// **'已有 Handle'**
  String get deviceJoinHandle;

  /// No description provided for @deviceJoinPhone.
  ///
  /// In zh, this message translates to:
  /// **'已绑定手机号'**
  String get deviceJoinPhone;

  /// No description provided for @deviceJoinOtp.
  ///
  /// In zh, this message translates to:
  /// **'短信验证码'**
  String get deviceJoinOtp;

  /// No description provided for @deviceJoinSendOtp.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码'**
  String get deviceJoinSendOtp;

  /// No description provided for @deviceJoinStart.
  ///
  /// In zh, this message translates to:
  /// **'开始关联'**
  String get deviceJoinStart;

  /// No description provided for @deviceJoinWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待管理设备响应'**
  String get deviceJoinWaiting;

  /// No description provided for @deviceJoinRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get deviceJoinRefresh;

  /// No description provided for @deviceJoinSasTitle.
  ///
  /// In zh, this message translates to:
  /// **'6 位验证码'**
  String get deviceJoinSasTitle;

  /// No description provided for @deviceJoinSasHint.
  ///
  /// In zh, this message translates to:
  /// **'请确认两台设备独立显示的数字完全一致。验证码不会通过服务器传输。'**
  String get deviceJoinSasHint;

  /// No description provided for @deviceJoinApprovalTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认新设备'**
  String get deviceJoinApprovalTitle;

  /// No description provided for @deviceJoinSasMatches.
  ///
  /// In zh, this message translates to:
  /// **'我已确认两台设备的 6 位验证码一致'**
  String get deviceJoinSasMatches;

  /// No description provided for @deviceJoinAllowAdmin.
  ///
  /// In zh, this message translates to:
  /// **'允许此设备管理其他设备'**
  String get deviceJoinAllowAdmin;

  /// No description provided for @deviceJoinAllowAdminHint.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭。开启后仍需完成根密钥安全导入才能管理设备。'**
  String get deviceJoinAllowAdminHint;

  /// No description provided for @deviceJoinApprove.
  ///
  /// In zh, this message translates to:
  /// **'确认并授权'**
  String get deviceJoinApprove;

  /// No description provided for @deviceJoinCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消关联'**
  String get deviceJoinCancel;

  /// No description provided for @deviceJoinAuthorized.
  ///
  /// In zh, this message translates to:
  /// **'设备已加入'**
  String get deviceJoinAuthorized;

  /// No description provided for @deviceJoinCancelled.
  ///
  /// In zh, this message translates to:
  /// **'设备关联已取消'**
  String get deviceJoinCancelled;

  /// No description provided for @deviceJoinExpired.
  ///
  /// In zh, this message translates to:
  /// **'设备关联已过期，请重新发起'**
  String get deviceJoinExpired;

  /// No description provided for @deviceJoinUserPresenceReason.
  ///
  /// In zh, this message translates to:
  /// **'确认授权新设备'**
  String get deviceJoinUserPresenceReason;

  /// No description provided for @deviceJoinErrorUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'多设备功能当前未开放'**
  String get deviceJoinErrorUnavailable;

  /// No description provided for @deviceJoinErrorConflict.
  ///
  /// In zh, this message translates to:
  /// **'状态已发生变化，请刷新后重试'**
  String get deviceJoinErrorConflict;

  /// No description provided for @deviceJoinErrorSas.
  ///
  /// In zh, this message translates to:
  /// **'验证码状态不一致，已停止授权'**
  String get deviceJoinErrorSas;

  /// No description provided for @deviceJoinErrorPresence.
  ///
  /// In zh, this message translates to:
  /// **'未完成系统身份确认，设备未获授权'**
  String get deviceJoinErrorPresence;

  /// No description provided for @deviceJoinErrorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络连接失败，请稍后重试'**
  String get deviceJoinErrorNetwork;

  /// No description provided for @deviceJoinErrorFailed.
  ///
  /// In zh, this message translates to:
  /// **'设备操作失败，请刷新后重试'**
  String get deviceJoinErrorFailed;

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
  /// **'打开下载页查阅历史版本'**
  String get settingsUpdateOpenGitHubHistory;

  /// No description provided for @settingsUpdateOpenGitHubDownload.
  ///
  /// In zh, this message translates to:
  /// **'打开下载页下载当前版本'**
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

  /// No description provided for @quickActionStartConversation.
  ///
  /// In zh, this message translates to:
  /// **'发起新消息'**
  String get quickActionStartConversation;

  /// No description provided for @quickActionCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'创建群聊'**
  String get quickActionCreateGroup;

  /// No description provided for @quickActionJoinGroup.
  ///
  /// In zh, this message translates to:
  /// **'加入群聊'**
  String get quickActionJoinGroup;

  /// No description provided for @quickActionFollowContact.
  ///
  /// In zh, this message translates to:
  /// **'关注联系人'**
  String get quickActionFollowContact;

  /// No description provided for @followContactTitle.
  ///
  /// In zh, this message translates to:
  /// **'关注联系人'**
  String get followContactTitle;

  /// No description provided for @followContactPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入 Handle 或 DID'**
  String get followContactPlaceholder;

  /// No description provided for @followContactAlreadyFollowing.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get followContactAlreadyFollowing;

  /// No description provided for @followContactSucceeded.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get followContactSucceeded;

  /// No description provided for @identityStartConversationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入 handle、DID 或 Agent 地址，确认身份后开始可信会话。'**
  String get identityStartConversationSubtitle;

  /// No description provided for @identityStartConversationAction.
  ///
  /// In zh, this message translates to:
  /// **'开始聊天'**
  String get identityStartConversationAction;

  /// No description provided for @identityStartConversationNotice.
  ///
  /// In zh, this message translates to:
  /// **'消息将通过已验证 DID 连接发送；首次联系外部身份请谨慎确认。'**
  String get identityStartConversationNotice;

  /// No description provided for @identityFollowContactTitle.
  ///
  /// In zh, this message translates to:
  /// **'关注联系人 / Agent'**
  String get identityFollowContactTitle;

  /// No description provided for @identityFollowContactSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入 handle 或 DID，确认身份后关注该身份。'**
  String get identityFollowContactSubtitle;

  /// No description provided for @identityFollowContactAction.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get identityFollowContactAction;

  /// No description provided for @identityFollowContactNotice.
  ///
  /// In zh, this message translates to:
  /// **'确认身份后会关注该联系人或 Agent。'**
  String get identityFollowContactNotice;

  /// No description provided for @identityInputSemantics.
  ///
  /// In zh, this message translates to:
  /// **'输入 handle 或 DID'**
  String get identityInputSemantics;

  /// No description provided for @identityInputPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入 @handle / DID / Agent 地址'**
  String get identityInputPlaceholder;

  /// No description provided for @identitySearchLabel.
  ///
  /// In zh, this message translates to:
  /// **'匹配身份'**
  String get identitySearchLabel;

  /// No description provided for @identityResolving.
  ///
  /// In zh, this message translates to:
  /// **'匹配中...'**
  String get identityResolving;

  /// No description provided for @identitySubmitting.
  ///
  /// In zh, this message translates to:
  /// **'处理中...'**
  String get identitySubmitting;

  /// No description provided for @identityQueryRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 handle 或 DID。'**
  String get identityQueryRequired;

  /// No description provided for @identityResolveFailed.
  ///
  /// In zh, this message translates to:
  /// **'未找到该身份，请检查 handle / DID 是否正确。'**
  String get identityResolveFailed;

  /// No description provided for @identityInvalidContact.
  ///
  /// In zh, this message translates to:
  /// **'联系人身份无效，无法打开会话。'**
  String get identityInvalidContact;

  /// No description provided for @identityMissingDid.
  ///
  /// In zh, this message translates to:
  /// **'身份解析结果缺少 DID。'**
  String get identityMissingDid;

  /// No description provided for @identityVerified.
  ///
  /// In zh, this message translates to:
  /// **'已验证'**
  String get identityVerified;

  /// No description provided for @identityTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get identityTypeLabel;

  /// No description provided for @identityRelationshipLabel.
  ///
  /// In zh, this message translates to:
  /// **'关系'**
  String get identityRelationshipLabel;

  /// No description provided for @identityBioLabel.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get identityBioLabel;

  /// No description provided for @identityTypeAgent.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get identityTypeAgent;

  /// No description provided for @identityTypeUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get identityTypeUser;

  /// No description provided for @identityAddGroupMemberTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加群成员'**
  String get identityAddGroupMemberTitle;

  /// No description provided for @identityAddGroupMemberSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入普通用户或 Agent 的 handle / DID，确认身份后加入群聊。'**
  String get identityAddGroupMemberSubtitle;

  /// No description provided for @identityAddGroupMemberAction.
  ///
  /// In zh, this message translates to:
  /// **'确认添加'**
  String get identityAddGroupMemberAction;

  /// No description provided for @identityAddGroupMemberNotice.
  ///
  /// In zh, this message translates to:
  /// **'请确认这是要加入群聊的身份。'**
  String get identityAddGroupMemberNotice;

  /// No description provided for @identityClearInput.
  ///
  /// In zh, this message translates to:
  /// **'清空输入'**
  String get identityClearInput;

  /// No description provided for @identitySearchNameHandleDid.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称、handle、DID'**
  String get identitySearchNameHandleDid;

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

  /// No description provided for @groupIdentityModeLabel.
  ///
  /// In zh, this message translates to:
  /// **'入群身份'**
  String get groupIdentityModeLabel;

  /// No description provided for @groupIdentityHandle.
  ///
  /// In zh, this message translates to:
  /// **'Handle'**
  String get groupIdentityHandle;

  /// No description provided for @groupIdentityDidOnly.
  ///
  /// In zh, this message translates to:
  /// **'DID'**
  String get groupIdentityDidOnly;

  /// No description provided for @groupIdentityCurrentHandle.
  ///
  /// In zh, this message translates to:
  /// **'Handle：{handle}'**
  String groupIdentityCurrentHandle(String handle);

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
  /// **'创建群聊'**
  String get groupCreateTitle;

  /// No description provided for @groupCreateAction.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get groupCreateAction;

  /// No description provided for @groupRecoveryCompleted.
  ///
  /// In zh, this message translates to:
  /// **'群身份已恢复'**
  String get groupRecoveryCompleted;

  /// No description provided for @groupRecoveryPending.
  ///
  /// In zh, this message translates to:
  /// **'身份已恢复，仍有 {count} 个群等待更新'**
  String groupRecoveryPending(int count);

  /// No description provided for @groupRecoveryBlocked.
  ///
  /// In zh, this message translates to:
  /// **'身份已恢复，有 {count} 个群需要处理'**
  String groupRecoveryBlocked(int count);

  /// No description provided for @groupRecoveryStatusUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'身份已恢复，群更新将在稍后重试'**
  String get groupRecoveryStatusUnavailable;

  /// No description provided for @groupRecoveryMembershipLayer.
  ///
  /// In zh, this message translates to:
  /// **'成员关系'**
  String get groupRecoveryMembershipLayer;

  /// No description provided for @groupRecoveryEncryptionLayer.
  ///
  /// In zh, this message translates to:
  /// **'群加密'**
  String get groupRecoveryEncryptionLayer;

  /// No description provided for @groupRecoveryPhaseCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get groupRecoveryPhaseCompleted;

  /// No description provided for @groupRecoveryPhasePending.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get groupRecoveryPhasePending;

  /// No description provided for @groupRecoveryPhaseBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已阻塞'**
  String get groupRecoveryPhaseBlocked;

  /// No description provided for @groupRecoveryRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试群身份恢复'**
  String get groupRecoveryRetry;

  /// No description provided for @groupFieldName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get groupFieldName;

  /// No description provided for @groupFieldNamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入群聊名称'**
  String get groupFieldNamePlaceholder;

  /// No description provided for @groupCreating.
  ///
  /// In zh, this message translates to:
  /// **'正在创建群组...'**
  String get groupCreating;

  /// No description provided for @groupAddMembers.
  ///
  /// In zh, this message translates to:
  /// **'添加成员'**
  String get groupAddMembers;

  /// No description provided for @groupRefreshMembers.
  ///
  /// In zh, this message translates to:
  /// **'刷新成员'**
  String get groupRefreshMembers;

  /// No description provided for @groupDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看群详情'**
  String get groupDetails;

  /// No description provided for @groupRemoveMember.
  ///
  /// In zh, this message translates to:
  /// **'移除成员'**
  String get groupRemoveMember;

  /// No description provided for @groupInviteDialogSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索本地身份，或输入 handle / DID 匹配新身份。'**
  String get groupInviteDialogSubtitle;

  /// No description provided for @groupInviteShowMore.
  ///
  /// In zh, this message translates to:
  /// **'查看更多'**
  String get groupInviteShowMore;

  /// No description provided for @groupInviteAdding.
  ///
  /// In zh, this message translates to:
  /// **'添加中...'**
  String get groupInviteAdding;

  /// No description provided for @groupInviteConfirmCount.
  ///
  /// In zh, this message translates to:
  /// **'确认添加 ({count})'**
  String groupInviteConfirmCount(int count);

  /// No description provided for @groupInviteCandidates.
  ///
  /// In zh, this message translates to:
  /// **'可邀请的身份'**
  String get groupInviteCandidates;

  /// No description provided for @groupInviteSearchResults.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果'**
  String get groupInviteSearchResults;

  /// No description provided for @groupInviteSelectHint.
  ///
  /// In zh, this message translates to:
  /// **'选择一个或多个身份后，统一确认添加。'**
  String get groupInviteSelectHint;

  /// No description provided for @groupInviteNoLocalCandidates.
  ///
  /// In zh, this message translates to:
  /// **'暂无可邀请的本地身份。'**
  String get groupInviteNoLocalCandidates;

  /// No description provided for @groupInviteIdentityUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'该身份已被删除或当前不可邀请。'**
  String get groupInviteIdentityUnavailable;

  /// No description provided for @groupInviteNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的本地身份，可以尝试匹配 handle / DID。'**
  String get groupInviteNoMatches;

  /// No description provided for @groupInviteAlreadyInGroup.
  ///
  /// In zh, this message translates to:
  /// **'已在群中'**
  String get groupInviteAlreadyInGroup;

  /// No description provided for @groupInviteUnnamedAgent.
  ///
  /// In zh, this message translates to:
  /// **'未命名智能体'**
  String get groupInviteUnnamedAgent;

  /// No description provided for @groupInviteSourceMyAgents.
  ///
  /// In zh, this message translates to:
  /// **'我的智能体'**
  String get groupInviteSourceMyAgents;

  /// No description provided for @groupInviteSourceFollowing.
  ///
  /// In zh, this message translates to:
  /// **'我关注的'**
  String get groupInviteSourceFollowing;

  /// No description provided for @groupInviteSourceFollowers.
  ///
  /// In zh, this message translates to:
  /// **'关注我的'**
  String get groupInviteSourceFollowers;

  /// No description provided for @groupInviteSourceRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近会话'**
  String get groupInviteSourceRecent;

  /// No description provided for @groupInviteSourceResolved.
  ///
  /// In zh, this message translates to:
  /// **'匹配结果'**
  String get groupInviteSourceResolved;

  /// No description provided for @groupRemoveMemberContent.
  ///
  /// In zh, this message translates to:
  /// **'移除 {memberTitle} 后，对方将不能继续在这个群里发送消息。'**
  String groupRemoveMemberContent(Object memberTitle);

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
  /// **'输入消息...'**
  String get chatInputPlaceholder;

  /// No description provided for @chatDeletedAgentDisabled.
  ///
  /// In zh, this message translates to:
  /// **'智能体已删除，无法继续发送消息'**
  String get chatDeletedAgentDisabled;

  /// No description provided for @chatGroupLeftDisabled.
  ///
  /// In zh, this message translates to:
  /// **'你已不在这个群聊中，不能继续发送消息'**
  String get chatGroupLeftDisabled;

  /// No description provided for @chatGroupSendDisabled.
  ///
  /// In zh, this message translates to:
  /// **'当前群聊暂时不能发送消息'**
  String get chatGroupSendDisabled;

  /// No description provided for @chatAgentProcessing.
  ///
  /// In zh, this message translates to:
  /// **'智能体正在处理...'**
  String get chatAgentProcessing;

  /// No description provided for @chatAgentStillProcessing.
  ///
  /// In zh, this message translates to:
  /// **'智能体仍在处理，稍后可刷新查看'**
  String get chatAgentStillProcessing;

  /// No description provided for @chatAgentExternalServiceWorking.
  ///
  /// In zh, this message translates to:
  /// **'智能体正在访问外部服务...'**
  String get chatAgentExternalServiceWorking;

  /// No description provided for @chatAgentExternalServiceDelayed.
  ///
  /// In zh, this message translates to:
  /// **'外部服务响应较慢，智能体仍在等待或重试...'**
  String get chatAgentExternalServiceDelayed;

  /// No description provided for @chatAgentExternalServiceResumed.
  ///
  /// In zh, this message translates to:
  /// **'外部服务已恢复，智能体正在继续处理...'**
  String get chatAgentExternalServiceResumed;

  /// No description provided for @chatSubjectProcessing.
  ///
  /// In zh, this message translates to:
  /// **'{subject} 正在处理...'**
  String chatSubjectProcessing(Object subject);

  /// No description provided for @chatSubjectExternalServiceWorking.
  ///
  /// In zh, this message translates to:
  /// **'{subject} 正在访问外部服务...'**
  String chatSubjectExternalServiceWorking(Object subject);

  /// No description provided for @chatSubjectExternalServiceDelayed.
  ///
  /// In zh, this message translates to:
  /// **'外部服务响应较慢，{subject} 仍在等待或重试...'**
  String chatSubjectExternalServiceDelayed(Object subject);

  /// No description provided for @chatSubjectExternalServiceResumed.
  ///
  /// In zh, this message translates to:
  /// **'外部服务已恢复，{subject} 正在继续处理...'**
  String chatSubjectExternalServiceResumed(Object subject);

  /// No description provided for @chatSubjectStillProcessing.
  ///
  /// In zh, this message translates to:
  /// **'{subject} 仍在处理，稍后可刷新查看'**
  String chatSubjectStillProcessing(Object subject);

  /// No description provided for @chatAgentSubject.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get chatAgentSubject;

  /// No description provided for @chatAgentCountSubject.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个智能体'**
  String chatAgentCountSubject(int count);

  /// No description provided for @chatSafeCollaboration.
  ///
  /// In zh, this message translates to:
  /// **'安全协作中'**
  String get chatSafeCollaboration;

  /// No description provided for @chatAddAttachment.
  ///
  /// In zh, this message translates to:
  /// **'添加附件'**
  String get chatAddAttachment;

  /// No description provided for @chatAddEmoji.
  ///
  /// In zh, this message translates to:
  /// **'选择表情'**
  String get chatAddEmoji;

  /// No description provided for @chatCaptureScreenshot.
  ///
  /// In zh, this message translates to:
  /// **'截图'**
  String get chatCaptureScreenshot;

  /// No description provided for @screenshotPermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'录屏权限尚未生效。请在系统设置的“录屏与系统录音”中允许当前 AWiki Me 应用，然后完全退出并重新打开。'**
  String get screenshotPermissionRequired;

  /// No description provided for @chatRemoveAttachment.
  ///
  /// In zh, this message translates to:
  /// **'移除附件'**
  String get chatRemoveAttachment;

  /// No description provided for @chatViewAttachment.
  ///
  /// In zh, this message translates to:
  /// **'查看附件'**
  String get chatViewAttachment;

  /// No description provided for @chatAttachmentFileFallback.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get chatAttachmentFileFallback;

  /// No description provided for @chatLoadingMentionCandidates.
  ///
  /// In zh, this message translates to:
  /// **'正在加载 mention 候选…'**
  String get chatLoadingMentionCandidates;

  /// No description provided for @mentionCandidateBadgeUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get mentionCandidateBadgeUser;

  /// No description provided for @mentionCandidateBadgeAgent.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get mentionCandidateBadgeAgent;

  /// No description provided for @mentionCandidateBadgeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'类型未知'**
  String get mentionCandidateBadgeUnknown;

  /// No description provided for @mentionSelectorAllSurface.
  ///
  /// In zh, this message translates to:
  /// **'@所有人'**
  String get mentionSelectorAllSurface;

  /// No description provided for @mentionSelectorHumansSurface.
  ///
  /// In zh, this message translates to:
  /// **'@所有用户'**
  String get mentionSelectorHumansSurface;

  /// No description provided for @mentionSelectorAgentsSurface.
  ///
  /// In zh, this message translates to:
  /// **'@所有智能体'**
  String get mentionSelectorAgentsSurface;

  /// No description provided for @mentionSelectorAllSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒群内所有成员'**
  String get mentionSelectorAllSubtitle;

  /// No description provided for @mentionSelectorHumansSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'只提醒群内用户'**
  String get mentionSelectorHumansSubtitle;

  /// No description provided for @mentionSelectorAgentsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒群内智能体'**
  String get mentionSelectorAgentsSubtitle;

  /// No description provided for @mentionSelectorAllBadge.
  ///
  /// In zh, this message translates to:
  /// **'用户 + 智能体'**
  String get mentionSelectorAllBadge;

  /// No description provided for @mentionDisabledUnknownMemberType.
  ///
  /// In zh, this message translates to:
  /// **'成员类型未知，暂不能作为单人 mention 目标'**
  String get mentionDisabledUnknownMemberType;

  /// No description provided for @mentionDisabledInactiveMember.
  ///
  /// In zh, this message translates to:
  /// **'成员状态不是 active，暂不能 mention'**
  String get mentionDisabledInactiveMember;

  /// No description provided for @chatSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get chatSendFailed;

  /// No description provided for @chatRetrySend.
  ///
  /// In zh, this message translates to:
  /// **'重试发送'**
  String get chatRetrySend;

  /// No description provided for @chatSending.
  ///
  /// In zh, this message translates to:
  /// **'发送中'**
  String get chatSending;

  /// No description provided for @chatViewPeerInfo.
  ///
  /// In zh, this message translates to:
  /// **'查看用户或智能体信息'**
  String get chatViewPeerInfo;

  /// No description provided for @chatOpenPeerInfo.
  ///
  /// In zh, this message translates to:
  /// **'打开{type}信息'**
  String chatOpenPeerInfo(Object type);

  /// No description provided for @chatCurrentConversationCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'当前会话无法继续发送消息'**
  String get chatCurrentConversationCannotSend;

  /// No description provided for @chatAgentDeletedBadge.
  ///
  /// In zh, this message translates to:
  /// **'智能体已删除'**
  String get chatAgentDeletedBadge;

  /// No description provided for @chatPeerInfoUserTitle.
  ///
  /// In zh, this message translates to:
  /// **'用户信息'**
  String get chatPeerInfoUserTitle;

  /// No description provided for @chatPeerInfoAgentTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能体信息'**
  String get chatPeerInfoAgentTitle;

  /// No description provided for @chatPeerInfoGroupTitle.
  ///
  /// In zh, this message translates to:
  /// **'群聊信息'**
  String get chatPeerInfoGroupTitle;

  /// No description provided for @chatPeerInfoGroupSection.
  ///
  /// In zh, this message translates to:
  /// **'群聊'**
  String get chatPeerInfoGroupSection;

  /// No description provided for @chatPeerInfoIdentityCard.
  ///
  /// In zh, this message translates to:
  /// **'身份卡'**
  String get chatPeerInfoIdentityCard;

  /// No description provided for @chatPeerInfoClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭信息弹窗'**
  String get chatPeerInfoClose;

  /// No description provided for @chatPeerInfoCopyDid.
  ///
  /// In zh, this message translates to:
  /// **'复制 DID'**
  String get chatPeerInfoCopyDid;

  /// No description provided for @chatPeerInfoDidCopied.
  ///
  /// In zh, this message translates to:
  /// **'DID 已复制'**
  String get chatPeerInfoDidCopied;

  /// No description provided for @chatPeerInfoProfileLoading.
  ///
  /// In zh, this message translates to:
  /// **'资料加载中'**
  String get chatPeerInfoProfileLoading;

  /// No description provided for @chatPeerInfoProfileUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'资料暂不可用'**
  String get chatPeerInfoProfileUnavailable;

  /// No description provided for @chatPeerInfoAwikiUser.
  ///
  /// In zh, this message translates to:
  /// **'AWiki 用户'**
  String get chatPeerInfoAwikiUser;

  /// No description provided for @chatPeerInfoCollapseAgentInbox.
  ///
  /// In zh, this message translates to:
  /// **'收起 Agent 收件箱'**
  String get chatPeerInfoCollapseAgentInbox;

  /// No description provided for @chatPeerInfoAgentInbox.
  ///
  /// In zh, this message translates to:
  /// **'Agent 收件箱'**
  String get chatPeerInfoAgentInbox;

  /// No description provided for @chatPeerInfoUnknownContact.
  ///
  /// In zh, this message translates to:
  /// **'未知联系人'**
  String get chatPeerInfoUnknownContact;

  /// No description provided for @chatPeerInfoLoadingProfile.
  ///
  /// In zh, this message translates to:
  /// **'正在加载资料…'**
  String get chatPeerInfoLoadingProfile;

  /// No description provided for @chatPeerInfoNoProfile.
  ///
  /// In zh, this message translates to:
  /// **'暂未填写资料'**
  String get chatPeerInfoNoProfile;

  /// No description provided for @chatPeerInfoRenameAgent.
  ///
  /// In zh, this message translates to:
  /// **'修改智能体名称'**
  String get chatPeerInfoRenameAgent;

  /// No description provided for @chatPeerInfoRenameAgentTooltip.
  ///
  /// In zh, this message translates to:
  /// **'修改名称'**
  String get chatPeerInfoRenameAgentTooltip;

  /// No description provided for @chatPeerInfoMemberCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 位成员'**
  String chatPeerInfoMemberCount(int count);

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

  /// No description provided for @agentPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能体'**
  String get agentPageTitle;

  /// No description provided for @agentCreateDaemon.
  ///
  /// In zh, this message translates to:
  /// **'创建 Daemon'**
  String get agentCreateDaemon;

  /// No description provided for @agentRefreshList.
  ///
  /// In zh, this message translates to:
  /// **'刷新智能体列表'**
  String get agentRefreshList;

  /// No description provided for @agentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无代理'**
  String get agentEmpty;

  /// No description provided for @agentEmptyWaitingHost.
  ///
  /// In zh, this message translates to:
  /// **'当前账号还没有可用的 Daemon。安装完成后可自动同步，也可以手动刷新。'**
  String get agentEmptyWaitingHost;

  /// No description provided for @agentEmptyInstallWaitingHost.
  ///
  /// In zh, this message translates to:
  /// **'正在等待宿主机完成 Daemon 安装，完成后会自动出现。'**
  String get agentEmptyInstallWaitingHost;

  /// No description provided for @agentSelectOne.
  ///
  /// In zh, this message translates to:
  /// **'选择一个代理'**
  String get agentSelectOne;

  /// No description provided for @agentCreateRuntime.
  ///
  /// In zh, this message translates to:
  /// **'创建 Agent'**
  String get agentCreateRuntime;

  /// No description provided for @agentOpenChat.
  ///
  /// In zh, this message translates to:
  /// **'打开聊天'**
  String get agentOpenChat;

  /// No description provided for @agentRename.
  ///
  /// In zh, this message translates to:
  /// **'改名'**
  String get agentRename;

  /// No description provided for @agentUpgrade.
  ///
  /// In zh, this message translates to:
  /// **'升级'**
  String get agentUpgrade;

  /// No description provided for @agentUpgrading.
  ///
  /// In zh, this message translates to:
  /// **'升级中'**
  String get agentUpgrading;

  /// No description provided for @agentCancelUpgrade.
  ///
  /// In zh, this message translates to:
  /// **'取消升级'**
  String get agentCancelUpgrade;

  /// No description provided for @agentCancelling.
  ///
  /// In zh, this message translates to:
  /// **'取消中'**
  String get agentCancelling;

  /// No description provided for @agentDeleteDaemon.
  ///
  /// In zh, this message translates to:
  /// **'删除代理'**
  String get agentDeleteDaemon;

  /// No description provided for @agentDeleteRuntime.
  ///
  /// In zh, this message translates to:
  /// **'删除智能体'**
  String get agentDeleteRuntime;

  /// No description provided for @agentRemoveFromAccount.
  ///
  /// In zh, this message translates to:
  /// **'从账号移除'**
  String get agentRemoveFromAccount;

  /// No description provided for @agentDeleting.
  ///
  /// In zh, this message translates to:
  /// **'删除中'**
  String get agentDeleting;

  /// No description provided for @agentRecentRuns.
  ///
  /// In zh, this message translates to:
  /// **'最近 Run'**
  String get agentRecentRuns;

  /// No description provided for @agentRefreshStatus.
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get agentRefreshStatus;

  /// No description provided for @agentDeletingNotice.
  ///
  /// In zh, this message translates to:
  /// **'删除请求已发送，正在等待代理同步。'**
  String get agentDeletingNotice;

  /// No description provided for @agentDaemonSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'Daemon · {count} 个 Agent · {status}'**
  String agentDaemonSubtitle(int count, Object status);

  /// No description provided for @agentRuntimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{runtime} · {status}'**
  String agentRuntimeSubtitle(Object runtime, Object status);

  /// No description provided for @agentUnnamedDaemon.
  ///
  /// In zh, this message translates to:
  /// **'未命名 Daemon'**
  String get agentUnnamedDaemon;

  /// No description provided for @agentUnnamedRuntime.
  ///
  /// In zh, this message translates to:
  /// **'未命名智能体'**
  String get agentUnnamedRuntime;

  /// No description provided for @agentListDeletingSync.
  ///
  /// In zh, this message translates to:
  /// **'删除中 · 等待同步'**
  String get agentListDeletingSync;

  /// No description provided for @agentListUpgradeFailed.
  ///
  /// In zh, this message translates to:
  /// **'升级失败'**
  String get agentListUpgradeFailed;

  /// No description provided for @agentListCancellingUpgrade.
  ///
  /// In zh, this message translates to:
  /// **'正在取消升级'**
  String get agentListCancellingUpgrade;

  /// No description provided for @agentListOrphanGroup.
  ///
  /// In zh, this message translates to:
  /// **'未关联 Daemon'**
  String get agentListOrphanGroup;

  /// No description provided for @agentListNoRuntime.
  ///
  /// In zh, this message translates to:
  /// **'尚未创建 Runtime Agent'**
  String get agentListNoRuntime;

  /// No description provided for @agentListRuntimeCreating.
  ///
  /// In zh, this message translates to:
  /// **'{runtime} · 创建中'**
  String agentListRuntimeCreating(Object runtime);

  /// No description provided for @agentListRuntimeWaitingStatus.
  ///
  /// In zh, this message translates to:
  /// **'{runtime} · 创建状态暂未返回，可刷新查看'**
  String agentListRuntimeWaitingStatus(Object runtime);

  /// No description provided for @daemonUpgradePreparingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在准备下载'**
  String get daemonUpgradePreparingDownload;

  /// No description provided for @daemonUpgradeRouteDirect.
  ///
  /// In zh, this message translates to:
  /// **'直连'**
  String get daemonUpgradeRouteDirect;

  /// No description provided for @daemonUpgradeRouteEnvironmentProxy.
  ///
  /// In zh, this message translates to:
  /// **'代理'**
  String get daemonUpgradeRouteEnvironmentProxy;

  /// No description provided for @daemonUpgradeRouteLocalProxy.
  ///
  /// In zh, this message translates to:
  /// **'本机代理 {route}'**
  String daemonUpgradeRouteLocalProxy(Object route);

  /// No description provided for @daemonUpgradeDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size}'**
  String daemonUpgradeDownloaded(Object size);

  /// No description provided for @daemonUpgradeRouteIndex.
  ///
  /// In zh, this message translates to:
  /// **'线路 {index}/{count}'**
  String daemonUpgradeRouteIndex(int index, int count);

  /// No description provided for @agentUpgradeTitle.
  ///
  /// In zh, this message translates to:
  /// **'升级代理'**
  String get agentUpgradeTitle;

  /// No description provided for @agentUpgradeMessage.
  ///
  /// In zh, this message translates to:
  /// **'代理会下载 latest 版本并重启服务。'**
  String get agentUpgradeMessage;

  /// No description provided for @daemonUpgradeRequesting.
  ///
  /// In zh, this message translates to:
  /// **'正在发送升级请求'**
  String get daemonUpgradeRequesting;

  /// No description provided for @daemonUpgradeWaitingForDaemon.
  ///
  /// In zh, this message translates to:
  /// **'升级请求已发送，正在等待 Daemon 确认'**
  String get daemonUpgradeWaitingForDaemon;

  /// No description provided for @daemonUpgradeFetchingManifest.
  ///
  /// In zh, this message translates to:
  /// **'正在获取版本信息'**
  String get daemonUpgradeFetchingManifest;

  /// No description provided for @daemonUpgradeSelectingSource.
  ///
  /// In zh, this message translates to:
  /// **'正在选择下载线路'**
  String get daemonUpgradeSelectingSource;

  /// No description provided for @daemonUpgradeDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载安装包'**
  String get daemonUpgradeDownloading;

  /// No description provided for @daemonUpgradeRetryingSource.
  ///
  /// In zh, this message translates to:
  /// **'下载中断，正在重试'**
  String get daemonUpgradeRetryingSource;

  /// No description provided for @daemonUpgradeVerifying.
  ///
  /// In zh, this message translates to:
  /// **'正在校验安装包'**
  String get daemonUpgradeVerifying;

  /// No description provided for @daemonUpgradeExtracting.
  ///
  /// In zh, this message translates to:
  /// **'正在解压安装包'**
  String get daemonUpgradeExtracting;

  /// No description provided for @daemonUpgradeInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装新版本'**
  String get daemonUpgradeInstalling;

  /// No description provided for @daemonUpgradeRestarting.
  ///
  /// In zh, this message translates to:
  /// **'正在重启 Daemon'**
  String get daemonUpgradeRestarting;

  /// No description provided for @daemonUpgradeInProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在升级'**
  String get daemonUpgradeInProgress;

  /// No description provided for @agentUpgradeIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'升级没有完成，请检查网络后重试。'**
  String get agentUpgradeIncomplete;

  /// No description provided for @agentUpgradeDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装包下载失败，请检查网络后重试。{summary}'**
  String agentUpgradeDownloadFailed(Object summary);

  /// No description provided for @agentUpgradeNotCancellable.
  ///
  /// In zh, this message translates to:
  /// **'当前升级已经进入重启阶段，无法取消。请稍后刷新状态确认结果。'**
  String get agentUpgradeNotCancellable;

  /// No description provided for @agentUpgradeCancelFailed.
  ///
  /// In zh, this message translates to:
  /// **'取消升级失败，请刷新状态后重试。'**
  String get agentUpgradeCancelFailed;

  /// No description provided for @agentUpgradeCancelNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'取消请求已发送，但 Daemon 暂未响应。请刷新状态确认升级结果。'**
  String get agentUpgradeCancelNoResponse;

  /// No description provided for @agentDeleteDaemonMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除后会停止宿主机上的代理服务，并移除它创建的智能体。本地数据会归档保留，不会继续使用。'**
  String get agentDeleteDaemonMessage;

  /// No description provided for @agentDeleteRuntimeMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除后该智能体会从列表中移除。本地数据会归档保留，不会继续使用。'**
  String get agentDeleteRuntimeMessage;

  /// No description provided for @agentRemoveDaemonFromAccountMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前 Daemon 不可连接。此操作只会从当前账号移除这个 Daemon 以及它创建的智能体，不会访问或清理宿主机上的本地文件。'**
  String get agentRemoveDaemonFromAccountMessage;

  /// No description provided for @agentRemoveRuntimeFromAccountMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前无法通过所属 Daemon 删除这个智能体。此操作只会把它从当前账号移除，不会访问或清理宿主机上的本地文件。'**
  String get agentRemoveRuntimeFromAccountMessage;

  /// No description provided for @agentInstallTitle.
  ///
  /// In zh, this message translates to:
  /// **'到宿主机安装代理'**
  String get agentInstallTitle;

  /// No description provided for @agentInstallSupportedTypes.
  ///
  /// In zh, this message translates to:
  /// **'支持的 Agent 类型：Hermes、Codex、Claude Code。安装宿主代理后，可在 Daemon 下创建 Runtime Agent。'**
  String get agentInstallSupportedTypes;

  /// No description provided for @agentInstallTokenExpiresAt.
  ///
  /// In zh, this message translates to:
  /// **'有效期至: {expiresAt}'**
  String agentInstallTokenExpiresAt(Object expiresAt);

  /// No description provided for @agentCopyInstallCommand.
  ///
  /// In zh, this message translates to:
  /// **'复制安装命令'**
  String get agentCopyInstallCommand;

  /// No description provided for @agentCleanupHostTitle.
  ///
  /// In zh, this message translates to:
  /// **'清理宿主机'**
  String get agentCleanupHostTitle;

  /// No description provided for @agentCleanupHostToggle.
  ///
  /// In zh, this message translates to:
  /// **'需要清理宿主机上的旧 Daemon？'**
  String get agentCleanupHostToggle;

  /// No description provided for @agentCleanupHostWarning.
  ///
  /// In zh, this message translates to:
  /// **'这会停止宿主机上的 AWiki Daemon，并永久删除该宿主机上的所有 Daemon 数据，包括身份、数据库、日志、归档、Runtime Profile 和已下载的 Daemon 二进制。此操作不可恢复。'**
  String get agentCleanupHostWarning;

  /// No description provided for @agentCopyCleanupCommand.
  ///
  /// In zh, this message translates to:
  /// **'复制清理命令'**
  String get agentCopyCleanupCommand;

  /// No description provided for @agentCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建 Agent'**
  String get agentCreateTitle;

  /// No description provided for @agentCreateType.
  ///
  /// In zh, this message translates to:
  /// **'Agent 类型'**
  String get agentCreateType;

  /// No description provided for @agentCreateWorkspacePolicy.
  ///
  /// In zh, this message translates to:
  /// **'工作目录策略'**
  String get agentCreateWorkspacePolicy;

  /// No description provided for @agentCreateWorkspaceRouteRoot.
  ///
  /// In zh, this message translates to:
  /// **'按会话目录'**
  String get agentCreateWorkspaceRouteRoot;

  /// No description provided for @agentCreateWorkspaceRouteRootDescription.
  ///
  /// In zh, this message translates to:
  /// **'每个联系人、群组或线程使用独立上下文目录。'**
  String get agentCreateWorkspaceRouteRootDescription;

  /// No description provided for @agentCreateWorkspaceSharedRoot.
  ///
  /// In zh, this message translates to:
  /// **'共享目录'**
  String get agentCreateWorkspaceSharedRoot;

  /// No description provided for @agentCreateWorkspaceSharedRootDescription.
  ///
  /// In zh, this message translates to:
  /// **'该身份共用一个目录，适合手工任务。'**
  String get agentCreateWorkspaceSharedRootDescription;

  /// No description provided for @agentCreateWorkspaceWorktreePerTask.
  ///
  /// In zh, this message translates to:
  /// **'每次任务 worktree'**
  String get agentCreateWorkspaceWorktreePerTask;

  /// No description provided for @agentCreateWorkspaceWorktreePerTaskDescription.
  ///
  /// In zh, this message translates to:
  /// **'每次运行使用独立工作树。'**
  String get agentCreateWorkspaceWorktreePerTaskDescription;

  /// No description provided for @agentCreateHandlePreview.
  ///
  /// In zh, this message translates to:
  /// **'最终 Handle：{handle}'**
  String agentCreateHandlePreview(Object handle);

  /// No description provided for @agentCreateHandleAvailabilityChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在校验可用性...'**
  String get agentCreateHandleAvailabilityChecking;

  /// No description provided for @agentCreateHandleAvailabilityPending.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法校验可用性，创建时会再次确认'**
  String get agentCreateHandleAvailabilityPending;

  /// No description provided for @agentCreateHandleChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在校验 Handle 可用性'**
  String get agentCreateHandleChecking;

  /// No description provided for @agentCreateHandleAvailable.
  ///
  /// In zh, this message translates to:
  /// **'这个 Handle 可以使用'**
  String get agentCreateHandleAvailable;

  /// No description provided for @agentCreateHandleUnavailableUsed.
  ///
  /// In zh, this message translates to:
  /// **'这个 Handle 已被使用'**
  String get agentCreateHandleUnavailableUsed;

  /// No description provided for @agentCreateHandleUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这个 Handle 不可使用'**
  String get agentCreateHandleUnavailable;

  /// No description provided for @agentCreateHandleRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 Handle'**
  String get agentCreateHandleRequired;

  /// No description provided for @agentCreateHandleTooLong.
  ///
  /// In zh, this message translates to:
  /// **'Handle 最多 {maxLength} 个字符'**
  String agentCreateHandleTooLong(Object maxLength);

  /// No description provided for @agentCreateHandleInvalidPattern.
  ///
  /// In zh, this message translates to:
  /// **'仅支持小写字母、数字和连字符，且首尾必须是字母或数字'**
  String get agentCreateHandleInvalidPattern;

  /// No description provided for @agentCreateHandleNoDoubleHyphen.
  ///
  /// In zh, this message translates to:
  /// **'Handle 不能包含连续连字符'**
  String get agentCreateHandleNoDoubleHyphen;

  /// No description provided for @agentCreateNeedsRouteWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'{agentType} 需要按会话目录工作模式。'**
  String agentCreateNeedsRouteWorkspace(Object agentType);

  /// No description provided for @agentCreateHermesDescription.
  ///
  /// In zh, this message translates to:
  /// **'内置 Hermes Runtime Agent。'**
  String get agentCreateHermesDescription;

  /// No description provided for @agentCreateNeedsGenericCliCapability.
  ///
  /// In zh, this message translates to:
  /// **'{agentType} 需要 Daemon 提供 generic-cli capability。'**
  String agentCreateNeedsGenericCliCapability(Object agentType);

  /// No description provided for @agentCreateUnsupportedDriver.
  ///
  /// In zh, this message translates to:
  /// **'当前 Daemon 不支持 {agentType} driver。'**
  String agentCreateUnsupportedDriver(Object agentType);

  /// No description provided for @agentCreateNeedsRouteSession.
  ///
  /// In zh, this message translates to:
  /// **'{agentType} 需要 route session 和 native resume 支持。'**
  String agentCreateNeedsRouteSession(Object agentType);

  /// No description provided for @agentCreateNeedsHostAccess.
  ///
  /// In zh, this message translates to:
  /// **'{agentType} 需要 Daemon 支持宿主机全权限模式。'**
  String agentCreateNeedsHostAccess(Object agentType);

  /// No description provided for @agentCreateRequiresSignedInCli.
  ///
  /// In zh, this message translates to:
  /// **'需要 Daemon 上已安装并登录的 {agentType} CLI。'**
  String agentCreateRequiresSignedInCli(Object agentType);

  /// No description provided for @agentCreateHostAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'宿主机全权限'**
  String get agentCreateHostAccessTitle;

  /// No description provided for @agentCreateHostAccessDescription.
  ///
  /// In zh, this message translates to:
  /// **'可按用户指令使用本机文件、命令、工具和网络。'**
  String get agentCreateHostAccessDescription;

  /// No description provided for @agentRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'修改智能体名称'**
  String get agentRenameTitle;

  /// No description provided for @agentRenameSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'名称会显示在智能体列表、最近会话和对话窗口中。'**
  String get agentRenameSubtitle;

  /// No description provided for @agentNameField.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get agentNameField;

  /// No description provided for @agentNamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'显示名称'**
  String get agentNamePlaceholder;

  /// No description provided for @agentNameHelp.
  ///
  /// In zh, this message translates to:
  /// **'最多 {maxLength} 个字符。'**
  String agentNameHelp(int maxLength);

  /// No description provided for @agentNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入智能体名称'**
  String get agentNameRequired;

  /// No description provided for @agentNameTooLong.
  ///
  /// In zh, this message translates to:
  /// **'名称最多 {maxLength} 个字符'**
  String agentNameTooLong(int maxLength);

  /// No description provided for @agentStatusProcessing.
  ///
  /// In zh, this message translates to:
  /// **'正在处理'**
  String get agentStatusProcessing;

  /// No description provided for @agentStatusReady.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get agentStatusReady;

  /// No description provided for @agentStatusNeedsConfig.
  ///
  /// In zh, this message translates to:
  /// **'需要配置'**
  String get agentStatusNeedsConfig;

  /// No description provided for @agentStatusNeedsUpgrade.
  ///
  /// In zh, this message translates to:
  /// **'需要升级'**
  String get agentStatusNeedsUpgrade;

  /// No description provided for @agentStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'异常'**
  String get agentStatusFailed;

  /// No description provided for @agentStatusOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get agentStatusOffline;

  /// No description provided for @agentStatusDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get agentStatusDisabled;

  /// No description provided for @agentStatusUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get agentStatusUnknown;

  /// No description provided for @agentStatusRefreshNeeded.
  ///
  /// In zh, this message translates to:
  /// **'需刷新'**
  String get agentStatusRefreshNeeded;

  /// No description provided for @agentStatusUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'未支持'**
  String get agentStatusUnsupported;

  /// No description provided for @agentStatusSemantic.
  ///
  /// In zh, this message translates to:
  /// **'智能体状态：{status}'**
  String agentStatusSemantic(Object status);

  /// No description provided for @agentErrorLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录。'**
  String get agentErrorLoginRequired;

  /// No description provided for @agentErrorHandleUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前账号没有可用 Handle，暂时不能生成 Daemon 安装命令。'**
  String get agentErrorHandleUnavailable;

  /// No description provided for @agentErrorPersonalAgentDisabled.
  ///
  /// In zh, this message translates to:
  /// **'个人助理功能未开启。'**
  String get agentErrorPersonalAgentDisabled;

  /// No description provided for @agentTenantUnsupportedTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前租户暂不支持智能体'**
  String get agentTenantUnsupportedTitle;

  /// No description provided for @agentTenantUnsupportedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'请回到登录页切换到已批准 AWiki 域名的租户后，再管理 Daemon 和智能体。'**
  String get agentTenantUnsupportedSubtitle;

  /// No description provided for @agentErrorTenantUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前租户暂不支持智能体功能。'**
  String get agentErrorTenantUnsupported;

  /// No description provided for @agentErrorSelectDaemon.
  ///
  /// In zh, this message translates to:
  /// **'请选择运行 Daemon。'**
  String get agentErrorSelectDaemon;

  /// No description provided for @agentErrorDaemonBootstrapMissing.
  ///
  /// In zh, this message translates to:
  /// **'运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新状态。'**
  String get agentErrorDaemonBootstrapMissing;

  /// No description provided for @agentErrorDaemonUnreachableDelete.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 当前不可达，暂时不能删除。'**
  String get agentErrorDaemonUnreachableDelete;

  /// No description provided for @agentErrorDaemonUnreachableUpgrade.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 当前不可达，暂时不能升级。请先刷新状态或重新安装。'**
  String get agentErrorDaemonUnreachableUpgrade;

  /// No description provided for @agentErrorPersonalAgentMissing.
  ///
  /// In zh, this message translates to:
  /// **'当前 Daemon 尚未创建个人助理。'**
  String get agentErrorPersonalAgentMissing;

  /// No description provided for @agentStatusSyncStillWaiting.
  ///
  /// In zh, this message translates to:
  /// **'状态同步仍在等待，请稍后刷新查看。'**
  String get agentStatusSyncStillWaiting;

  /// No description provided for @agentErrorScopeMismatch.
  ///
  /// In zh, this message translates to:
  /// **'这台电脑已经绑定到另一个 Handle 的 Daemon。请使用对应 Handle 管理，或先清理宿主机上的 AWiki Daemon 数据后重新安装。'**
  String get agentErrorScopeMismatch;

  /// No description provided for @agentErrorControllerHandleMismatch.
  ///
  /// In zh, this message translates to:
  /// **'当前客户端身份和登录 Handle 不一致，请切换到正确账号后重新复制安装命令。'**
  String get agentErrorControllerHandleMismatch;

  /// No description provided for @agentErrorControllerScopeMissing.
  ///
  /// In zh, this message translates to:
  /// **'安装命令缺少账号归属信息，请重新复制最新的 Daemon 安装命令。'**
  String get agentErrorControllerScopeMissing;

  /// No description provided for @agentErrorInstallCommandUsed.
  ///
  /// In zh, this message translates to:
  /// **'这条安装命令已经使用过，请重新复制最新的 Daemon 安装命令。'**
  String get agentErrorInstallCommandUsed;

  /// No description provided for @agentErrorSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效，请重新登录后再查看智能体。'**
  String get agentErrorSessionExpired;

  /// No description provided for @agentErrorRequestTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请稍后重试。'**
  String get agentErrorRequestTimeout;

  /// No description provided for @agentErrorNetworkPreserved.
  ///
  /// In zh, this message translates to:
  /// **'网络连接暂时不可用，已保留当前数据。'**
  String get agentErrorNetworkPreserved;

  /// No description provided for @agentErrorLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'智能体信息暂时无法加载，请稍后重试。'**
  String get agentErrorLoadFailed;

  /// No description provided for @agentErrorStatusSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效，请重新登录后再刷新代理状态。'**
  String get agentErrorStatusSessionExpired;

  /// No description provided for @agentErrorStatusTimeout.
  ///
  /// In zh, this message translates to:
  /// **'刷新状态超时，当前数据已保留。'**
  String get agentErrorStatusTimeout;

  /// No description provided for @agentErrorStatusNetworkPreserved.
  ///
  /// In zh, this message translates to:
  /// **'网络连接暂时不可用，当前数据已保留。'**
  String get agentErrorStatusNetworkPreserved;

  /// No description provided for @agentErrorStatusRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'状态刷新请求发送失败，请稍后再试。'**
  String get agentErrorStatusRefreshFailed;

  /// No description provided for @agentAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'访问权限'**
  String get agentAccessTitle;

  /// No description provided for @agentAccessSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置 Handle 对智能体的控制权限'**
  String get agentAccessSubtitle;

  /// No description provided for @agentAccessWhitelist.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get agentAccessWhitelist;

  /// No description provided for @agentAccessBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get agentAccessBlacklist;

  /// No description provided for @agentAccessSwitchToWhitelist.
  ///
  /// In zh, this message translates to:
  /// **'切换到白名单模式'**
  String get agentAccessSwitchToWhitelist;

  /// No description provided for @agentAccessSwitchToBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'切换到黑名单模式'**
  String get agentAccessSwitchToBlacklist;

  /// No description provided for @agentAccessCurrentWhitelist.
  ///
  /// In zh, this message translates to:
  /// **'当前白名单模式'**
  String get agentAccessCurrentWhitelist;

  /// No description provided for @agentAccessCurrentBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'当前黑名单模式'**
  String get agentAccessCurrentBlacklist;

  /// No description provided for @agentAccessEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get agentAccessEnabled;

  /// No description provided for @agentAccessDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get agentAccessDisabled;

  /// No description provided for @agentAccessHandlePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'bob 或 bob.example.com'**
  String get agentAccessHandlePlaceholder;

  /// No description provided for @agentAccessAddHandle.
  ///
  /// In zh, this message translates to:
  /// **'添加 Handle'**
  String get agentAccessAddHandle;

  /// No description provided for @agentAccessNoHandles.
  ///
  /// In zh, this message translates to:
  /// **'暂无 Handle'**
  String get agentAccessNoHandles;

  /// No description provided for @agentAccessRemoveHandle.
  ///
  /// In zh, this message translates to:
  /// **'删除 Handle'**
  String get agentAccessRemoveHandle;

  /// No description provided for @agentAccessDuplicateWhitelist.
  ///
  /// In zh, this message translates to:
  /// **'这个 Handle 已在白名单中。'**
  String get agentAccessDuplicateWhitelist;

  /// No description provided for @agentAccessDuplicateBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'这个 Handle 已在黑名单中。'**
  String get agentAccessDuplicateBlacklist;

  /// No description provided for @agentAccessHandleRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 Handle。'**
  String get agentAccessHandleRequired;

  /// No description provided for @agentAccessSingleHandleOnly.
  ///
  /// In zh, this message translates to:
  /// **'每次只能添加一个 Handle。'**
  String get agentAccessSingleHandleOnly;

  /// No description provided for @agentAccessHandleInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入短 Handle 或完整 Handle。'**
  String get agentAccessHandleInvalid;

  /// No description provided for @agentDiagnosticsTitle.
  ///
  /// In zh, this message translates to:
  /// **'诊断信息'**
  String get agentDiagnosticsTitle;

  /// No description provided for @agentDiagnosticsDaemonSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 运行与身份信息'**
  String get agentDiagnosticsDaemonSubtitle;

  /// No description provided for @agentDiagnosticsAgentSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'智能体身份信息'**
  String get agentDiagnosticsAgentSubtitle;

  /// No description provided for @agentDiagnosticsShowMore.
  ///
  /// In zh, this message translates to:
  /// **'查看更多'**
  String get agentDiagnosticsShowMore;

  /// No description provided for @agentDiagnosticsCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get agentDiagnosticsCollapse;

  /// No description provided for @agentDiagnosticsShowMoreDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看更多诊断'**
  String get agentDiagnosticsShowMoreDetails;

  /// No description provided for @agentDiagnosticsCollapseDetails.
  ///
  /// In zh, this message translates to:
  /// **'收起诊断详情'**
  String get agentDiagnosticsCollapseDetails;

  /// No description provided for @agentDiagnosticCurrentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本'**
  String get agentDiagnosticCurrentVersion;

  /// No description provided for @agentDiagnosticPlatform.
  ///
  /// In zh, this message translates to:
  /// **'平台'**
  String get agentDiagnosticPlatform;

  /// No description provided for @agentDiagnosticLatestVersion.
  ///
  /// In zh, this message translates to:
  /// **'最新版本'**
  String get agentDiagnosticLatestVersion;

  /// No description provided for @agentDiagnosticMinSupportedVersion.
  ///
  /// In zh, this message translates to:
  /// **'最低可用版本'**
  String get agentDiagnosticMinSupportedVersion;

  /// No description provided for @agentDiagnosticService.
  ///
  /// In zh, this message translates to:
  /// **'服务'**
  String get agentDiagnosticService;

  /// No description provided for @agentDiagnosticLastSeen.
  ///
  /// In zh, this message translates to:
  /// **'最近上报'**
  String get agentDiagnosticLastSeen;

  /// No description provided for @agentDiagnosticErrorCode.
  ///
  /// In zh, this message translates to:
  /// **'错误代码'**
  String get agentDiagnosticErrorCode;

  /// No description provided for @agentDiagnosticRunner.
  ///
  /// In zh, this message translates to:
  /// **'运行器'**
  String get agentDiagnosticRunner;

  /// No description provided for @agentDiagnosticProfileStatus.
  ///
  /// In zh, this message translates to:
  /// **'配置状态'**
  String get agentDiagnosticProfileStatus;

  /// No description provided for @agentDiagnosticInstallationStatus.
  ///
  /// In zh, this message translates to:
  /// **'安装状态'**
  String get agentDiagnosticInstallationStatus;

  /// No description provided for @agentDiagnosticServiceInstalled.
  ///
  /// In zh, this message translates to:
  /// **'服务安装'**
  String get agentDiagnosticServiceInstalled;

  /// No description provided for @agentDiagnosticConfigSummary.
  ///
  /// In zh, this message translates to:
  /// **'配置摘要'**
  String get agentDiagnosticConfigSummary;

  /// No description provided for @agentDiagnosticHermesProfile.
  ///
  /// In zh, this message translates to:
  /// **'Hermes 配置'**
  String get agentDiagnosticHermesProfile;

  /// No description provided for @agentDiagnosticRunnerStatus.
  ///
  /// In zh, this message translates to:
  /// **'运行状态'**
  String get agentDiagnosticRunnerStatus;

  /// No description provided for @agentDiagnosticActiveSessionCount.
  ///
  /// In zh, this message translates to:
  /// **'活跃会话'**
  String get agentDiagnosticActiveSessionCount;

  /// No description provided for @personalAgentSkipped.
  ///
  /// In zh, this message translates to:
  /// **'个人助理跳过此消息'**
  String get personalAgentSkipped;

  /// No description provided for @personalAgentFailed.
  ///
  /// In zh, this message translates to:
  /// **'个人助理处理失败'**
  String get personalAgentFailed;

  /// No description provided for @personalAgentCompleted.
  ///
  /// In zh, this message translates to:
  /// **'个人助理已完成处理'**
  String get personalAgentCompleted;

  /// No description provided for @personalAgentProcessing.
  ///
  /// In zh, this message translates to:
  /// **'个人助理正在处理'**
  String get personalAgentProcessing;

  /// No description provided for @personalAgentReceived.
  ///
  /// In zh, this message translates to:
  /// **'个人助理已收到消息'**
  String get personalAgentReceived;

  /// No description provided for @personalAgentResultGenerated.
  ///
  /// In zh, this message translates to:
  /// **'已生成处理结果'**
  String get personalAgentResultGenerated;

  /// No description provided for @personalAgentDraftApplied.
  ///
  /// In zh, this message translates to:
  /// **'草稿已放入输入框'**
  String get personalAgentDraftApplied;

  /// No description provided for @personalAgentAppActionCompleted.
  ///
  /// In zh, this message translates to:
  /// **'App action 已完成'**
  String get personalAgentAppActionCompleted;

  /// No description provided for @personalAgentRequestRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝个人助理请求'**
  String get personalAgentRequestRejected;

  /// No description provided for @personalAgentAppActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'App action 处理失败'**
  String get personalAgentAppActionFailed;

  /// No description provided for @personalAgentWaitingConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'等待确认'**
  String get personalAgentWaitingConfirmation;

  /// No description provided for @personalAgentUseDraft.
  ///
  /// In zh, this message translates to:
  /// **'使用草稿'**
  String get personalAgentUseDraft;

  /// No description provided for @personalAgentActionCreateDraft.
  ///
  /// In zh, this message translates to:
  /// **'个人助理生成了草稿'**
  String get personalAgentActionCreateDraft;

  /// No description provided for @personalAgentActionSummarize.
  ///
  /// In zh, this message translates to:
  /// **'个人助理生成了摘要'**
  String get personalAgentActionSummarize;

  /// No description provided for @personalAgentActionReadContact.
  ///
  /// In zh, this message translates to:
  /// **'个人助理请求读取联系人'**
  String get personalAgentActionReadContact;

  /// No description provided for @personalAgentActionUpdateDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'个人助理请求修改联系人名称'**
  String get personalAgentActionUpdateDisplayName;

  /// No description provided for @personalAgentActionUpdateNote.
  ///
  /// In zh, this message translates to:
  /// **'个人助理请求修改联系人备注'**
  String get personalAgentActionUpdateNote;

  /// No description provided for @personalAgentActionGeneric.
  ///
  /// In zh, this message translates to:
  /// **'个人助理请求 App action'**
  String get personalAgentActionGeneric;

  /// No description provided for @personalAgentTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人助理'**
  String get personalAgentTitle;

  /// No description provided for @personalAgentRuntimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'运行 Daemon 内创建 {provider} runtime'**
  String personalAgentRuntimeSubtitle(Object provider);

  /// No description provided for @personalAgentExperimentDisabled.
  ///
  /// In zh, this message translates to:
  /// **'实验功能关闭'**
  String get personalAgentExperimentDisabled;

  /// No description provided for @personalAgentReadyToEnable.
  ///
  /// In zh, this message translates to:
  /// **'可启用'**
  String get personalAgentReadyToEnable;

  /// No description provided for @personalAgentNotReady.
  ///
  /// In zh, this message translates to:
  /// **'未就绪'**
  String get personalAgentNotReady;

  /// No description provided for @personalAgentRunningDaemon.
  ///
  /// In zh, this message translates to:
  /// **'运行 Daemon'**
  String get personalAgentRunningDaemon;

  /// No description provided for @personalAgentEngine.
  ///
  /// In zh, this message translates to:
  /// **'引擎'**
  String get personalAgentEngine;

  /// No description provided for @personalAgentScope.
  ///
  /// In zh, this message translates to:
  /// **'处理范围'**
  String get personalAgentScope;

  /// No description provided for @personalAgentAllProcessableConversations.
  ///
  /// In zh, this message translates to:
  /// **'所有可处理会话'**
  String get personalAgentAllProcessableConversations;

  /// No description provided for @personalAgentDaemonVersion.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 版本'**
  String get personalAgentDaemonVersion;

  /// No description provided for @personalAgentCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'可用能力'**
  String get personalAgentCapabilities;

  /// No description provided for @personalAgentSecureBootstrap.
  ///
  /// In zh, this message translates to:
  /// **'安全 bootstrap'**
  String get personalAgentSecureBootstrap;

  /// No description provided for @personalAgentPublicKeyReported.
  ///
  /// In zh, this message translates to:
  /// **'已上报公钥'**
  String get personalAgentPublicKeyReported;

  /// No description provided for @personalAgentWaitingStatusRefresh.
  ///
  /// In zh, this message translates to:
  /// **'等待刷新状态'**
  String get personalAgentWaitingStatusRefresh;

  /// No description provided for @personalAgentEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用个人助理'**
  String get personalAgentEnable;

  /// No description provided for @personalAgentEnabling.
  ///
  /// In zh, this message translates to:
  /// **'启用中'**
  String get personalAgentEnabling;

  /// No description provided for @personalAgentPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停处理消息'**
  String get personalAgentPause;

  /// No description provided for @personalAgentDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除个人助理'**
  String get personalAgentDelete;

  /// No description provided for @personalAgentRevokeAuthorization.
  ///
  /// In zh, this message translates to:
  /// **'撤销 Daemon 消息授权'**
  String get personalAgentRevokeAuthorization;

  /// No description provided for @personalAgentPermissionSummaryEnabled.
  ///
  /// In zh, this message translates to:
  /// **'权限摘要：读取普通消息，分析、总结并生成草稿；不会自动发送消息，也不处理 E2EE 明文。'**
  String get personalAgentPermissionSummaryEnabled;

  /// No description provided for @personalAgentPermissionSummaryDisabled.
  ///
  /// In zh, this message translates to:
  /// **'切换到已批准 AWiki 域名的租户后可配置个人助理。'**
  String get personalAgentPermissionSummaryDisabled;

  /// No description provided for @personalAgentPauseTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂停处理消息'**
  String get personalAgentPauseTitle;

  /// No description provided for @personalAgentPauseMessage.
  ///
  /// In zh, this message translates to:
  /// **'暂停后，个人助理不再读取和处理新消息；runtime 和授权仍会保留，可以重新启用。'**
  String get personalAgentPauseMessage;

  /// No description provided for @personalAgentDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除个人助理'**
  String get personalAgentDeleteTitle;

  /// No description provided for @personalAgentDeleteMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除前会先暂停消息处理，然后归档对应 runtime。Daemon 和授权不会被删除。'**
  String get personalAgentDeleteMessage;

  /// No description provided for @personalAgentRevokeTitle.
  ///
  /// In zh, this message translates to:
  /// **'撤销 Daemon 消息授权'**
  String get personalAgentRevokeTitle;

  /// No description provided for @personalAgentRevokeMessage.
  ///
  /// In zh, this message translates to:
  /// **'撤销需要先通过签名 DID Document 更新移除 daemon-key-1。未完成更新时会失败，不会把暂停误认为撤销成功。'**
  String get personalAgentRevokeMessage;

  /// No description provided for @personalAgentSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置个人助理的启用、暂停和 Daemon 消息授权。'**
  String get personalAgentSettingsSubtitle;

  /// No description provided for @personalAgentSettingsDisabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'个人助理已关闭，不会发送 bootstrap 或授权请求。'**
  String get personalAgentSettingsDisabledSubtitle;

  /// No description provided for @personalAgentNoDaemonSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择运行 Daemon'**
  String get personalAgentNoDaemonSelected;

  /// No description provided for @personalAgentSelectedDaemon.
  ///
  /// In zh, this message translates to:
  /// **'当前运行 Daemon：{name}'**
  String personalAgentSelectedDaemon(Object name);

  /// No description provided for @personalAgentDescription.
  ///
  /// In zh, this message translates to:
  /// **'读取普通 direct text，为你整理并生成草稿；发送前必须由你确认。'**
  String get personalAgentDescription;

  /// No description provided for @personalAgentDisabledDescription.
  ///
  /// In zh, this message translates to:
  /// **'实验功能未开启，当前不会发送 bootstrap 或授权请求。'**
  String get personalAgentDisabledDescription;

  /// No description provided for @personalAgentDaemonStatus.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 状态'**
  String get personalAgentDaemonStatus;

  /// No description provided for @personalAgentAuthorizationStatus.
  ///
  /// In zh, this message translates to:
  /// **'授权状态'**
  String get personalAgentAuthorizationStatus;

  /// No description provided for @personalAgentDirectTextScope.
  ///
  /// In zh, this message translates to:
  /// **'普通 direct text'**
  String get personalAgentDirectTextScope;

  /// No description provided for @personalAgentNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get personalAgentNotSelected;

  /// No description provided for @personalAgentNoDaemon.
  ///
  /// In zh, this message translates to:
  /// **'无可用 Daemon'**
  String get personalAgentNoDaemon;

  /// No description provided for @personalAgentNotBound.
  ///
  /// In zh, this message translates to:
  /// **'尚未绑定'**
  String get personalAgentNotBound;

  /// No description provided for @personalAgentBound.
  ///
  /// In zh, this message translates to:
  /// **'已绑定 {name}'**
  String personalAgentBound(Object name);

  /// No description provided for @personalAgentRefreshDaemonStatus.
  ///
  /// In zh, this message translates to:
  /// **'刷新 Daemon 状态'**
  String get personalAgentRefreshDaemonStatus;

  /// No description provided for @personalAgentSelectDaemon.
  ///
  /// In zh, this message translates to:
  /// **'选择运行 Daemon'**
  String get personalAgentSelectDaemon;

  /// No description provided for @personalAgentRunsOnSelectedDaemon.
  ///
  /// In zh, this message translates to:
  /// **'个人助理会运行在你选择的 Daemon 内。'**
  String get personalAgentRunsOnSelectedDaemon;

  /// No description provided for @personalAgentNoDaemons.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用 Daemon，请先在智能体页创建或安装 Daemon。'**
  String get personalAgentNoDaemons;

  /// No description provided for @personalAgentSelectDaemonSemantic.
  ///
  /// In zh, this message translates to:
  /// **'选择 {name}'**
  String personalAgentSelectDaemonSemantic(Object name);

  /// No description provided for @personalAgentReadyWithPublicKey.
  ///
  /// In zh, this message translates to:
  /// **'Ready · 已上报公钥'**
  String get personalAgentReadyWithPublicKey;

  /// No description provided for @personalAgentReadyWaitingPublicKey.
  ///
  /// In zh, this message translates to:
  /// **'Ready · 等待 bootstrap 公钥'**
  String get personalAgentReadyWaitingPublicKey;

  /// No description provided for @personalAgentDaemonNeedsAttention.
  ///
  /// In zh, this message translates to:
  /// **'{status} · 需刷新或检查 Daemon'**
  String personalAgentDaemonNeedsAttention(Object status);

  /// No description provided for @personalAgentFeatureDisabledNotice.
  ///
  /// In zh, this message translates to:
  /// **'AWIKI_AGENT_IM_ENABLED=false，入口只显示状态，不会发送 bootstrap、binding 或身份授权请求。'**
  String get personalAgentFeatureDisabledNotice;

  /// No description provided for @personalAgentNoDaemonNotice.
  ///
  /// In zh, this message translates to:
  /// **'没有可用 Daemon。请先安装并启动 Daemon。'**
  String get personalAgentNoDaemonNotice;

  /// No description provided for @personalAgentDaemonNotReadyNotice.
  ///
  /// In zh, this message translates to:
  /// **'当前 Daemon 未 ready，请刷新状态或检查 Daemon 运行情况。'**
  String get personalAgentDaemonNotReadyNotice;

  /// No description provided for @personalAgentBootstrapKeyMissingNotice.
  ///
  /// In zh, this message translates to:
  /// **'运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新 Daemon 状态。'**
  String get personalAgentBootstrapKeyMissingNotice;

  /// No description provided for @personalAgentCanEnableNotice.
  ///
  /// In zh, this message translates to:
  /// **'可以启用个人助理。'**
  String get personalAgentCanEnableNotice;

  /// No description provided for @personalAgentSafetyTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全边界'**
  String get personalAgentSafetyTitle;

  /// No description provided for @personalAgentSafetyPlainText.
  ///
  /// In zh, this message translates to:
  /// **'只读取可处理的普通 direct text；不处理 E2EE 明文（Direct / Group）。'**
  String get personalAgentSafetyPlainText;

  /// No description provided for @personalAgentSafetyDraftOnly.
  ///
  /// In zh, this message translates to:
  /// **'只生成草稿和需要确认的 action；不会自动发送消息。'**
  String get personalAgentSafetyDraftOnly;

  /// No description provided for @personalAgentSafetyNoPrimaryKey.
  ///
  /// In zh, this message translates to:
  /// **'runtime 不持有 DID 主私钥，不直连 message-service。'**
  String get personalAgentSafetyNoPrimaryKey;

  /// No description provided for @personalAgentSafetyFeatureDisabled.
  ///
  /// In zh, this message translates to:
  /// **'实验功能关闭时不会触发授权、bootstrap 或 delegated key 操作。'**
  String get personalAgentSafetyFeatureDisabled;

  /// No description provided for @personalAgentBusy.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get personalAgentBusy;

  /// No description provided for @personalAgentDaemonNotReady.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 未就绪'**
  String get personalAgentDaemonNotReady;

  /// No description provided for @personalAgentEnabledState.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get personalAgentEnabledState;

  /// No description provided for @personalAgentCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建个人助理'**
  String get personalAgentCreated;

  /// No description provided for @personalAgentConfigure.
  ///
  /// In zh, this message translates to:
  /// **'配置个人助理'**
  String get personalAgentConfigure;

  /// No description provided for @agentInboxTitle.
  ///
  /// In zh, this message translates to:
  /// **'Agent 收件箱'**
  String get agentInboxTitle;

  /// No description provided for @agentInboxThreadTitle.
  ///
  /// In zh, this message translates to:
  /// **'收件箱线程'**
  String get agentInboxThreadTitle;

  /// No description provided for @agentInboxBackToInbox.
  ///
  /// In zh, this message translates to:
  /// **'返回收件箱'**
  String get agentInboxBackToInbox;

  /// No description provided for @agentInboxBackToConversation.
  ///
  /// In zh, this message translates to:
  /// **'返回会话'**
  String get agentInboxBackToConversation;

  /// No description provided for @agentInboxClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭 Agent 收件箱'**
  String get agentInboxClose;

  /// No description provided for @agentInboxNotRuntimeConversation.
  ///
  /// In zh, this message translates to:
  /// **'当前会话不是 Runtime Agent 会话'**
  String get agentInboxNotRuntimeConversation;

  /// No description provided for @agentInboxDaemonMissing.
  ///
  /// In zh, this message translates to:
  /// **'这个 Runtime Agent 暂时没有绑定 Daemon'**
  String get agentInboxDaemonMissing;

  /// No description provided for @agentInboxRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新 Agent 收件箱'**
  String get agentInboxRefresh;

  /// No description provided for @agentInboxEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个 Agent 暂时没有收件箱消息'**
  String get agentInboxEmpty;

  /// No description provided for @agentInboxLoadMoreThreads.
  ///
  /// In zh, this message translates to:
  /// **'加载更多会话'**
  String get agentInboxLoadMoreThreads;

  /// No description provided for @agentInboxScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get agentInboxScopeAll;

  /// No description provided for @agentInboxScopeDirect.
  ///
  /// In zh, this message translates to:
  /// **'私聊'**
  String get agentInboxScopeDirect;

  /// No description provided for @agentInboxScopeGroup.
  ///
  /// In zh, this message translates to:
  /// **'群聊'**
  String get agentInboxScopeGroup;

  /// No description provided for @agentInboxLatestAttachment.
  ///
  /// In zh, this message translates to:
  /// **'最新：附件'**
  String get agentInboxLatestAttachment;

  /// No description provided for @agentInboxLatestNoPreview.
  ///
  /// In zh, this message translates to:
  /// **'最新：无预览'**
  String get agentInboxLatestNoPreview;

  /// No description provided for @agentInboxLatestPreview.
  ///
  /// In zh, this message translates to:
  /// **'最新：{preview}'**
  String agentInboxLatestPreview(Object preview);

  /// No description provided for @agentInboxReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只读收件箱'**
  String get agentInboxReadOnly;

  /// No description provided for @agentInboxRefreshThread.
  ///
  /// In zh, this message translates to:
  /// **'刷新收件箱线程'**
  String get agentInboxRefreshThread;

  /// No description provided for @agentInboxThreadEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个线程暂时没有消息'**
  String get agentInboxThreadEmpty;

  /// No description provided for @agentInboxLoadEarlier.
  ///
  /// In zh, this message translates to:
  /// **'加载更早消息'**
  String get agentInboxLoadEarlier;

  /// No description provided for @agentInboxContentTruncated.
  ///
  /// In zh, this message translates to:
  /// **'内容较长，已截断'**
  String get agentInboxContentTruncated;

  /// No description provided for @agentInboxDaemonNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'Daemon 暂时没有返回，请稍后重试'**
  String get agentInboxDaemonNoResponse;

  /// No description provided for @agentInboxQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'收件箱查询失败'**
  String get agentInboxQueryFailed;

  /// No description provided for @agentInboxThreadQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'线程查询失败'**
  String get agentInboxThreadQueryFailed;

  /// No description provided for @relationshipNone.
  ///
  /// In zh, this message translates to:
  /// **'未关注'**
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
  /// **'无法打开下载页面，请稍后重试。'**
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
  /// **'更新失败，请打开下载页手动安装。'**
  String get updateInstallFailed;

  /// No description provided for @daemonUpgradeStarted.
  ///
  /// In zh, this message translates to:
  /// **'已开始升级代理。'**
  String get daemonUpgradeStarted;

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

  /// No description provided for @documentSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件保存失败，请稍后重试。'**
  String get documentSaveFailed;

  /// No description provided for @attachmentDownloadEmpty.
  ///
  /// In zh, this message translates to:
  /// **'附件下载结果为空。'**
  String get attachmentDownloadEmpty;

  /// No description provided for @conversationRemovedFromRecents.
  ///
  /// In zh, this message translates to:
  /// **'已从最近会话移除'**
  String get conversationRemovedFromRecents;

  /// No description provided for @attachmentUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'附件文件已过期或本机缓存不存在，请让对方重新发送。'**
  String get attachmentUnavailable;

  /// No description provided for @attachmentOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'附件无法打开，请稍后重试或保存后再打开。'**
  String get attachmentOpenFailed;

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

  /// No description provided for @chatGroupMemberAddedByYou.
  ///
  /// In zh, this message translates to:
  /// **'你邀请{member}加入了群聊'**
  String chatGroupMemberAddedByYou(Object member);

  /// No description provided for @chatGroupMemberAddedBy.
  ///
  /// In zh, this message translates to:
  /// **'{actor}邀请{member}加入了群聊'**
  String chatGroupMemberAddedBy(Object actor, Object member);

  /// No description provided for @chatGroupMemberJoined.
  ///
  /// In zh, this message translates to:
  /// **'{member}加入了群聊'**
  String chatGroupMemberJoined(Object member);

  /// No description provided for @chatGroupMemberRemovedByYou.
  ///
  /// In zh, this message translates to:
  /// **'你将{member}移出了群聊'**
  String chatGroupMemberRemovedByYou(Object member);

  /// No description provided for @chatGroupMemberRemovedBy.
  ///
  /// In zh, this message translates to:
  /// **'{actor}将{member}移出了群聊'**
  String chatGroupMemberRemovedBy(Object actor, Object member);

  /// No description provided for @chatGroupMemberLeft.
  ///
  /// In zh, this message translates to:
  /// **'{member}退出了群聊'**
  String chatGroupMemberLeft(Object member);

  /// No description provided for @chatGroupProfileUpdated.
  ///
  /// In zh, this message translates to:
  /// **'群信息已更新'**
  String get chatGroupProfileUpdated;

  /// No description provided for @handleRecoveryTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复 AWiki Handle'**
  String get handleRecoveryTitle;

  /// No description provided for @handleRecoveryWarning.
  ///
  /// In zh, this message translates to:
  /// **'这是服务辅助恢复，不会找回原 DID 私钥。完成前 Handle 仍指向原 DID。'**
  String get handleRecoveryWarning;

  /// No description provided for @handleRecoveryCreatesNewDid.
  ///
  /// In zh, this message translates to:
  /// **'本设备将创建全新的根密钥和密码学 DID。'**
  String get handleRecoveryCreatesNewDid;

  /// No description provided for @handleRecoverySignsOutOldDevices.
  ///
  /// In zh, this message translates to:
  /// **'完成后原 DID 的所有设备将退出，不能再接收未来消息。'**
  String get handleRecoverySignsOutOldDevices;

  /// No description provided for @handleRecoveryNoHistoryOrGroupInheritance.
  ///
  /// In zh, this message translates to:
  /// **'历史消息解密能力、Direct 安全会话和群组成员关系不会自动继承。'**
  String get handleRecoveryNoHistoryOrGroupInheritance;

  /// No description provided for @handleRecoveryCoolingTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复冷静期进行中'**
  String get handleRecoveryCoolingTitle;

  /// No description provided for @handleRecoveryCoolingUntil.
  ///
  /// In zh, this message translates to:
  /// **'系统正在通知旧设备和绑定渠道；通知投递及完整冷静期均完成前不能最终恢复。当前最新状态给出的时间为 {time}，权威期限以后续刷新结果为准。'**
  String handleRecoveryCoolingUntil(Object time);

  /// No description provided for @handleRecoveryReadyTitle.
  ///
  /// In zh, this message translates to:
  /// **'可以进行独立的再次确认'**
  String get handleRecoveryReadyTitle;

  /// No description provided for @handleRecoveryReadyDetail.
  ///
  /// In zh, this message translates to:
  /// **'请重新获取验证码。第一次验证使用的验证码或授权不能用于最终恢复。'**
  String get handleRecoveryReadyDetail;

  /// No description provided for @handleRecoveryReconfirmationHint.
  ///
  /// In zh, this message translates to:
  /// **'再次确认将授权本设备创建新 DID，并把当前 Handle 切换到新 DID。'**
  String get handleRecoveryReconfirmationHint;

  /// No description provided for @handleRecoveryReconfirmationOtp.
  ///
  /// In zh, this message translates to:
  /// **'再次确认验证码'**
  String get handleRecoveryReconfirmationOtp;

  /// No description provided for @handleRecoverySendReconfirmationOtp.
  ///
  /// In zh, this message translates to:
  /// **'发送新的验证码'**
  String get handleRecoverySendReconfirmationOtp;

  /// No description provided for @handleRecoveryExplicitConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'我了解将创建新 DID、原设备退出，并且历史消息和群组不会自动恢复。'**
  String get handleRecoveryExplicitConfirmation;

  /// No description provided for @handleRecoveryFinalize.
  ///
  /// In zh, this message translates to:
  /// **'确认恢复 Handle 并创建新 DID'**
  String get handleRecoveryFinalize;

  /// No description provided for @handleRecoveryFinalizePresenceReason.
  ///
  /// In zh, this message translates to:
  /// **'确认恢复 Handle 并创建新 DID'**
  String get handleRecoveryFinalizePresenceReason;

  /// No description provided for @handleRecoveryRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新恢复状态'**
  String get handleRecoveryRefresh;

  /// No description provided for @handleRecoveryCancelledTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复已取消'**
  String get handleRecoveryCancelledTitle;

  /// No description provided for @handleRecoveryCancelledDetail.
  ///
  /// In zh, this message translates to:
  /// **'Handle 仍指向原 DID，没有创建或启用新身份。'**
  String get handleRecoveryCancelledDetail;

  /// No description provided for @handleRecoveryExpiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复已过期'**
  String get handleRecoveryExpiredTitle;

  /// No description provided for @handleRecoveryExpiredDetail.
  ///
  /// In zh, this message translates to:
  /// **'本次恢复没有更改 Handle，请重新验证后发起。'**
  String get handleRecoveryExpiredDetail;

  /// No description provided for @handleRecoveryCompletedTitle.
  ///
  /// In zh, this message translates to:
  /// **'Handle 恢复已完成'**
  String get handleRecoveryCompletedTitle;

  /// No description provided for @handleRecoveryCompletedDetail.
  ///
  /// In zh, this message translates to:
  /// **'已创建并启用新 DID。请重新建立联系人安全会话，并按群主确认重新加入群组。'**
  String get handleRecoveryCompletedDetail;

  /// No description provided for @handleRecoveryActivationPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'新 DID 已创建，等待本地激活'**
  String get handleRecoveryActivationPendingTitle;

  /// No description provided for @handleRecoveryActivationPendingDetail.
  ///
  /// In zh, this message translates to:
  /// **'远端恢复已经完成，不能再次最终恢复。请重试加载 Core 已持久化的新身份并初始化端到端加密。'**
  String get handleRecoveryActivationPendingDetail;

  /// No description provided for @handleRecoveryRetryActivation.
  ///
  /// In zh, this message translates to:
  /// **'重试本地激活'**
  String get handleRecoveryRetryActivation;

  /// No description provided for @handleRecoveryActivationFailed.
  ///
  /// In zh, this message translates to:
  /// **'Handle 已完成切换，但本地身份或端到端加密初始化失败。请勿再次最终恢复，只重试本地激活。'**
  String get handleRecoveryActivationFailed;

  /// No description provided for @handleRecoveryCompletionAckPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'新 DID 已启用，等待保存完成状态'**
  String get handleRecoveryCompletionAckPendingTitle;

  /// No description provided for @handleRecoveryCompletionAckPendingDetail.
  ///
  /// In zh, this message translates to:
  /// **'身份和端到端加密已就绪。请重试保存完成状态；不会再次最终恢复、切换身份或初始化端到端加密。'**
  String get handleRecoveryCompletionAckPendingDetail;

  /// No description provided for @handleRecoveryRetryCompletionAck.
  ///
  /// In zh, this message translates to:
  /// **'重试保存完成状态'**
  String get handleRecoveryRetryCompletionAck;

  /// No description provided for @handleRecoveryUserPresenceRejected.
  ///
  /// In zh, this message translates to:
  /// **'系统身份确认已取消或不可用，未提交敏感操作。'**
  String get handleRecoveryUserPresenceRejected;

  /// No description provided for @handleRecoveryUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前版本尚未接入安全的 Handle 恢复流程，未对身份做任何更改。'**
  String get handleRecoveryUnavailable;

  /// No description provided for @handleRecoveryNotReady.
  ///
  /// In zh, this message translates to:
  /// **'恢复仍在冷静期内，请稍后刷新状态。'**
  String get handleRecoveryNotReady;

  /// No description provided for @handleRecoveryConflict.
  ///
  /// In zh, this message translates to:
  /// **'恢复状态已变化或 Handle 不再指向预期身份，请刷新后重试。'**
  String get handleRecoveryConflict;

  /// No description provided for @handleRecoveryAdminSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'身份恢复警报'**
  String get handleRecoveryAdminSectionTitle;

  /// No description provided for @handleRecoveryAdminSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'有人正在申请恢复 {handle} 并创建新 DID。若不是你本人操作，请立即取消。'**
  String handleRecoveryAdminSectionSubtitle(Object handle);

  /// No description provided for @handleRecoveryAdminCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消恢复'**
  String get handleRecoveryAdminCancel;

  /// No description provided for @handleRecoveryAdminCancelConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认取消 Handle 恢复？'**
  String get handleRecoveryAdminCancelConfirmTitle;

  /// No description provided for @handleRecoveryAdminCancelConfirmDetail.
  ///
  /// In zh, this message translates to:
  /// **'取消后本次请求不能再完成，Handle 将继续指向当前 DID。'**
  String get handleRecoveryAdminCancelConfirmDetail;

  /// No description provided for @handleRecoveryAdminCancelConfirmAction.
  ///
  /// In zh, this message translates to:
  /// **'确认取消'**
  String get handleRecoveryAdminCancelConfirmAction;

  /// No description provided for @handleRecoveryCancelPresenceReason.
  ///
  /// In zh, this message translates to:
  /// **'确认取消 Handle 恢复'**
  String get handleRecoveryCancelPresenceReason;
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
