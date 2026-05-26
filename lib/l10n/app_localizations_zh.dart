// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AWiki Me';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonDone => '完成';

  @override
  String get commonSend => '发送';

  @override
  String get commonJoin => '加入';

  @override
  String get commonBack => '返回';

  @override
  String get commonNext => '下一步';

  @override
  String get commonPrevious => '上一步';

  @override
  String get commonSave => '保存';

  @override
  String get commonGotIt => '知道了';

  @override
  String get commonPleaseWait => '请稍候...';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonError => '错误';

  @override
  String get realtimeStatusConnecting => '正在连接消息服务...';

  @override
  String get realtimeStatusReconnecting => '消息连接中断，正在重连...';

  @override
  String get realtimeStatusDisconnected => '消息服务已断开，正在尝试恢复';

  @override
  String get onboardingLogin => '切换身份';

  @override
  String get onboardingRegister => '登录或注册';

  @override
  String get onboardingImportCredential => '导入身份凭证';

  @override
  String get onboardingRefreshCredentials => '重新识别本地凭证';

  @override
  String get onboardingSendOtp => '发送验证码';

  @override
  String onboardingResendOtpIn(Object seconds) {
    return '重新发送（${seconds}s）';
  }

  @override
  String get onboardingOtp => '验证码';

  @override
  String get onboardingOtpPlaceholder => '输入验证码';

  @override
  String get onboardingEmail => '邮箱';

  @override
  String get onboardingEmailPlaceholder => '输入邮箱地址';

  @override
  String get onboardingSendActivationEmail => '发送激活邮件';

  @override
  String onboardingResendActivationEmailIn(Object seconds) {
    return '重新发送（${seconds}s）';
  }

  @override
  String get onboardingEmailActivated => '邮箱已激活';

  @override
  String get onboardingCheckActivationStatus => '我已激活，检查状态';

  @override
  String get onboardingHandle => '账号用户名';

  @override
  String get onboardingHandlePlaceholder => '用户名 handle';

  @override
  String get onboardingNickname => '昵称';

  @override
  String get onboardingNicknamePlaceholder => '输入昵称';

  @override
  String get onboardingCompleteRegister => '完成';

  @override
  String get onboardingCompleteEmailRegister => '完成注册';

  @override
  String get onboardingLoginRegisterHint =>
      '手机号会自动判断登录已有 Handle 或注册新 Handle；邮箱暂时仅支持注册新 Handle。';

  @override
  String get onboardingAuthMethod => '验证方式';

  @override
  String get onboardingAccountProfile => '账号资料';

  @override
  String get onboardingPhone => '手机号';

  @override
  String get onboardingPhonePlaceholder => '输入手机号';

  @override
  String get onboardingMissingLocalCredential => '暂未识别到本地凭证，请先重新识别。';

  @override
  String get onboardingIncompletePhoneTitle => '手机号不完整';

  @override
  String get onboardingIncompletePhoneContent => '请输入正确的手机号。';

  @override
  String get onboardingMissingOtpTitle => '缺少验证码';

  @override
  String get onboardingMissingOtpContent => '请输入收到的验证码后再继续。';

  @override
  String get onboardingMissingEmailTitle => '缺少邮箱';

  @override
  String get onboardingMissingEmailContent => '请输入邮箱地址。';

  @override
  String get onboardingNotActivatedTitle => '尚未激活';

  @override
  String get onboardingNotActivatedContent => '请先完成邮箱激活并检查状态。';

  @override
  String get onboardingInvalidHandleTitle => 'handle 不合法';

  @override
  String get onboardingInvalidHandleContent => '仅支持小写字母、数字、中划线，长度 2-32。';

  @override
  String get onboardingMissingNicknameTitle => '缺少昵称';

  @override
  String get onboardingMissingNicknameContent => '请输入昵称。';

  @override
  String get secureMessagingClient => 'Secure messaging client';

  @override
  String get shellNavMessages => '消息';

  @override
  String get shellNavFriends => '朋友';

  @override
  String get shellNavMe => '我';

  @override
  String get conversationsTitle => '信息';

  @override
  String get conversationsNoMessagePreview => '暂无消息';

  @override
  String get conversationsEmptyTitle => '还没有消息';

  @override
  String get conversationsEmptySubtitle => '去添加好友、关注联系人，或者先加入一个群聊吧。';

  @override
  String get friendsTitle => '朋友';

  @override
  String get profileMeTitle => '我';

  @override
  String get profileFollowers => '粉丝';

  @override
  String get profileFollowing => '关注';

  @override
  String get profileGroups => '群组';

  @override
  String get profileEmpty => '暂无 profile';

  @override
  String get profileEditTitle => '编辑个人资料';

  @override
  String get profileBioPlaceholder => '个人简介';

  @override
  String get profileTagsPlaceholder => '标签，使用英文逗号分隔';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZhHans => '简体中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsPushNotification => '消息推送通知';

  @override
  String get settingsCurrentVersion => '当前版本';

  @override
  String settingsCurrentVersionValue(Object version) {
    return '当前版本：$version';
  }

  @override
  String get settingsCheckForUpdates => '检查更新';

  @override
  String get settingsViewReleaseNotes => '查看更新日志';

  @override
  String get settingsInstallUpdate => '立即更新';

  @override
  String settingsInstallUpdateVersion(Object version) {
    return '安装新版本：$version';
  }

  @override
  String get settingsDownloadUpdate => '下载更新';

  @override
  String settingsDownloadUpdateVersion(Object version) {
    return '下载新版本：$version';
  }

  @override
  String settingsUpdateAvailable(Object version) {
    return '发现新版本：$version';
  }

  @override
  String get settingsAlreadyLatestVersion => '已是最新版本';

  @override
  String get settingsUpdateStatusLoading => '正在读取版本信息...';

  @override
  String get settingsUpdateStatusChecking => '正在检查更新...';

  @override
  String get settingsUpdateStatusDownloading => '正在下载更新...';

  @override
  String get settingsUpdateStatusInstalling => '正在准备安装更新...';

  @override
  String get settingsUpdateStatusFailed => '检查更新失败，请稍后重试';

  @override
  String settingsUpdateReleaseNotesVersion(Object version) {
    return '查看版本 $version 的更新日志';
  }

  @override
  String get settingsUpdateOpenGitHubHistory => '前往 GitHub 查阅历史版本';

  @override
  String get settingsUpdateOpenGitHubDownload => '前往 GitHub 下载当前版本';

  @override
  String get settingsExportCredential => '导出身份凭证';

  @override
  String settingsExportCurrentCredential(Object credentialName) {
    return '导出当前凭证：$credentialName';
  }

  @override
  String get settingsNoCredentialToExport => '当前暂无可导出的登录凭证';

  @override
  String get settingsLogout => '退出登录';

  @override
  String get settingsLogoutSubtitle => '清除本地登录状态并返回登录页';

  @override
  String get settingsDeleteCredential => '注销当前凭证';

  @override
  String settingsDeleteCurrentCredential(Object credentialName) {
    return '删除本地凭证：$credentialName';
  }

  @override
  String get settingsDeleteCredentialFallback => '删除当前登录凭证';

  @override
  String get settingsLogoutConfirmTitle => '退出登录';

  @override
  String get settingsLogoutConfirmContent => '确定要退出当前账号吗？';

  @override
  String get settingsDeleteCredentialConfirmTitle => '注销当前凭证';

  @override
  String settingsDeleteCredentialConfirmContent(Object credentialName) {
    return '将删除本地凭证 \"$credentialName\"，并退出登录。确定继续吗？';
  }

  @override
  String get settingsDeleteCredentialConfirmAction => '确认注销';

  @override
  String get quickActionsTitle => '更多操作';

  @override
  String get quickActionCreateGroup => '发起群聊';

  @override
  String get quickActionJoinGroup => '加入群聊';

  @override
  String get quickActionAddFriend => '添加朋友';

  @override
  String get addFriendTitle => '添加朋友';

  @override
  String get addFriendPlaceholder => '输入 Handle 或 DID';

  @override
  String get addFriendAlreadyExists => '已经添加或正在申请中';

  @override
  String get addFriendFollowed => '已关注';

  @override
  String get groupListTitle => '群聊列表';

  @override
  String get groupListEmpty => '还没有群组。先创建一个群，或使用 Group DID 加入。';

  @override
  String get groupListLoading => '正在加载群数据...';

  @override
  String get groupJoinDialogTitle => '通过 Group DID 入群';

  @override
  String get groupJoinDialogPlaceholder => '输入群组 Group DID';

  @override
  String get groupNoDescription => '暂无群描述';

  @override
  String groupMemberCount(int count) {
    return '$count 人';
  }

  @override
  String groupMemberCountCompact(int count) {
    return '$count人';
  }

  @override
  String groupIdLabel(Object groupId) {
    return 'Group DID: $groupId';
  }

  @override
  String get groupEnterChat => '进入群聊';

  @override
  String get groupRefreshSnapshot => '刷新群详情与成员';

  @override
  String get groupMembersTitle => '群成员';

  @override
  String get groupMembersEmpty => '暂无成员快照，先执行一次刷新群详情与成员。';

  @override
  String get groupCreateTitle => '创建群组';

  @override
  String get groupFieldName => '名称';

  @override
  String get groupFieldNamePlaceholder => '群组名称';

  @override
  String get groupFieldSlug => '短链接';

  @override
  String get groupFieldSlugPlaceholder => '可选，不填则自动生成';

  @override
  String get groupFieldDescription => '介绍';

  @override
  String get groupFieldDescriptionPlaceholder => '群资料介绍';

  @override
  String get groupFieldGoal => '目标';

  @override
  String get groupFieldGoalPlaceholder => '建群目标';

  @override
  String get groupFieldRules => '规则';

  @override
  String get groupFieldRulesPlaceholder => '社群规则';

  @override
  String get groupFieldPrompt => '提示';

  @override
  String get groupFieldPromptPlaceholder => '发声引导 Message Prompt';

  @override
  String get groupCreating => '正在创建群组...';

  @override
  String get chatUnknownUser => 'Unknown';

  @override
  String get chatConversationUntitled => '未命名会话';

  @override
  String get chatHeaderGroup => 'GROUP';

  @override
  String get chatHeaderOnline => 'ONLINE';

  @override
  String get chatInputPlaceholder => 'Type a message...';

  @override
  String get peerProfileLoadFailed => '无法加载该用户的信息';

  @override
  String get peerProfileTitle => '个人资料';

  @override
  String get peerProfileSendMessage => '发消息';

  @override
  String get peerProfileUnfollow => '取消关注';

  @override
  String get peerProfileDeleteThread => '删除本地聊天记录';

  @override
  String get peerProfileUnfollowed => '已取消关注';

  @override
  String get peerProfileThreadDeleted => '本地聊天记录已删除';

  @override
  String get relationshipNone => 'none';

  @override
  String get relationshipFollowing => 'following';

  @override
  String get relationshipFollower => 'follower';

  @override
  String get relationshipFriend => 'friend';

  @override
  String get profileUpdated => '个人资料已更新';

  @override
  String exportedTo(Object path) {
    return '已导出到 $path';
  }

  @override
  String get importSuccessSelectCredential => '导入成功，请选择该凭证登录';

  @override
  String localCredentialsRefreshed(Object count) {
    return '已重新识别到 $count 个本地凭证';
  }

  @override
  String get noLocalCredentialsFound => '未识别到本地凭证';

  @override
  String get newMessageArrived => '你收到了新消息';

  @override
  String get updateAlreadyLatest => '已是最新版本';

  @override
  String get updateCheckFailed => '检查更新失败，请稍后重试。';

  @override
  String get updateOpenReleaseNotesFailed => '无法打开更新日志，请稍后重试。';

  @override
  String get updateOpenDownloadFailed => '无法打开下载页面，请前往 GitHub Release。';

  @override
  String get updateReadyToInstall => '下载完成，准备安装。';

  @override
  String get updatePermissionRequired => '请允许安装未知应用后重试。';

  @override
  String get updateInstallFailed => '更新失败，请前往 GitHub 下载。';

  @override
  String get requestTimeoutRetry => '请求超时，请检查网络后重试。';

  @override
  String get operationFailedRetry => '操作失败，请稍后重试。';

  @override
  String get featureNotImplemented => '功能暂未实现，请等待后续版本。';

  @override
  String get otpSent => '验证码已发送，请留意短信。';

  @override
  String get activationEmailSent => '激活邮件已发送，请查收邮箱。';

  @override
  String get emailLoginUnsupportedForRegisteredHandle =>
      '该 handle 已注册。邮箱当前仅支持新注册，请使用手机号验证码登录或导入身份凭证。';

  @override
  String get emailNotActivatedClickLink => '邮箱尚未激活，请先点击邮件中的激活链接。';

  @override
  String get sessionExpiredRelogin => '登录状态已失效，请重新登录。';

  @override
  String localCredentialNotFound(Object credentialName) {
    return '本地未找到凭证：$credentialName';
  }

  @override
  String get setupIdentityScriptMissing =>
      '当前版本不再支持旧版脚本凭证，请重新创建或导入新版 e1 DID 凭证。';

  @override
  String deleteCredentialFailed(Object credentialName) {
    return '删除凭证失败：$credentialName';
  }

  @override
  String get noCredentialToExport => '当前没有已登录凭证可导出。';

  @override
  String get credentialPackFailed => '凭证打包失败，请稍后重试。';

  @override
  String get localCredentialDirectoryMissing => '无法定位本地凭证目录。';

  @override
  String get exportUnsupportedOnPlatform => '当前平台暂不支持导出身份凭证。';

  @override
  String get importUnsupportedOnPlatform => '当前平台暂不支持导入身份凭证。';

  @override
  String get currentCredentialIndexMissing => '未找到当前凭证的本地索引信息。';

  @override
  String get currentCredentialDidInvalid => '当前凭证的 DID 文档格式不正确。';

  @override
  String get zipMissingMetadata => 'ZIP 包缺少必要的凭证元信息。';

  @override
  String get zipCredentialIncomplete => 'ZIP 包中的凭证内容不完整。';

  @override
  String invalidFileFormat(Object path) {
    return '文件格式不正确：$path';
  }

  @override
  String get phoneInvalidIntlExample =>
      '手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000';

  @override
  String get phoneInvalidIntlOrCn => '手机号格式不正确，请输入国际格式或中国大陆 11 位手机号';

  @override
  String get handleInvalidPattern => 'handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线';

  @override
  String didRegistrationPluginMissing(Object authHint) {
    return 'AWiki Me 当前无法创建 DID（$authHint注册）。请确认 Dart ANP SDK 初始化成功。';
  }

  @override
  String get didRegistrationRefreshUnsupported =>
      'AWiki Me 当前未接入 DID 注册插件，无法自动刷新 token。';

  @override
  String get e2eePluginMissing => 'AWiki Me 当前未启用 E2EE，请接入原生插件实现';

  @override
  String get documentPickerFailed => '文件选择失败，请稍后重试。';

  @override
  String get linkOpenFailed => '无法打开链接';

  @override
  String linkOpenFailedWithDetail(Object detail) {
    return '无法打开链接: $detail';
  }

  @override
  String get groupNameRequired => '群名称不能为空';
}
