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
  String get commonDelete => '删除';

  @override
  String get commonRetry => '重试';

  @override
  String get commonClose => '关闭';

  @override
  String get commonDetails => '详情';

  @override
  String get commonMoreActions => '更多操作';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonCopyDetails => '复制详情';

  @override
  String get commonReject => '拒绝';

  @override
  String get commonRemove => '移除';

  @override
  String get commonPause => '暂停';

  @override
  String get commonRevoke => '撤销授权';

  @override
  String get commonUnknown => '未知';

  @override
  String get commonLoadMore => '加载更多';

  @override
  String get commonPleaseWait => '请稍候...';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonError => '错误';

  @override
  String get commonErrorDetails => '错误详情';

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
  String get onboardingLoadingServerInfo => '正在读取当前服务器支持的登录方式...';

  @override
  String get onboardingServerInfoLoadFailed => '无法读取当前服务器支持的登录方式。请检查租户地址后重试。';

  @override
  String get onboardingRegistrationUnavailable => '当前服务器暂不支持在 APP 内注册身份。';

  @override
  String get onboardingNoVerificationHint => '当前服务器不需要短信或邮箱验证码，可直接创建新身份。';

  @override
  String get handleAlreadyRegisteredImportCredential =>
      '这个 handle 已经存在。当前服务器不支持无验证码恢复，请导入已有身份凭证或联系服务器管理员。';

  @override
  String get registrationMethodUnavailable => '当前服务器不支持所选注册方式，请刷新后重试。';

  @override
  String get tenantSwitcherLabel => '管理租户';

  @override
  String get tenantManagementTitle => '租户';

  @override
  String get tenantManagementSubtitle => '切换这个 App 使用的后端和 DID Host。';

  @override
  String get tenantPrimaryAgentNote => '智能体功能目前只支持 AWiki 主租户。';

  @override
  String get tenantCreate => '添加租户配置';

  @override
  String get tenantEdit => '编辑租户';

  @override
  String get tenantUse => '使用';

  @override
  String get tenantCurrent => '当前';

  @override
  String get tenantName => '租户名称';

  @override
  String get tenantNamePlaceholder => '团队或服务名称';

  @override
  String get tenantBackendBaseUrl => '后端地址';

  @override
  String get tenantBackendBaseUrlPlaceholder => 'https://example.com';

  @override
  String get tenantDidHost => 'DID Host';

  @override
  String get tenantDidHostPlaceholder => 'example.com';

  @override
  String get tenantCreateTitle => '添加租户配置';

  @override
  String get tenantEditTitle => '编辑租户';

  @override
  String get tenantSaving => '保存中...';

  @override
  String get tenantDeleteTitle => '删除租户';

  @override
  String tenantDeleteContent(Object tenantName) {
    return '删除 $tenantName？本机数据会保留，但这个租户不会再出现在切换列表中。';
  }

  @override
  String get tenantCannotEditDefault => '默认 AWiki 租户不能编辑。接入其他后端请添加租户配置。';

  @override
  String get tenantCannotEditWithData =>
      '这个租户已经有本地数据，只能修改名称，不能修改后端地址或 DID Host。';

  @override
  String get tenantCannotDeleteDefault => '默认 AWiki 租户不能删除。';

  @override
  String get tenantCannotDeleteActive => '请先切换到其他租户，再删除当前租户。';

  @override
  String get tenantValidationNameInvalid =>
      '请输入 1-40 个可见字符作为本地显示名称，不能包含不可见控制字符。';

  @override
  String get tenantValidationBackendInvalid =>
      '请输入有效的 http 或 https 后端地址，不能包含 query 或 fragment。';

  @override
  String get tenantValidationDidHostInvalid =>
      '请输入有效的 DID Host，例如 example.com。';

  @override
  String get tenantValidationNameExists => '已经存在同名租户。';

  @override
  String get tenantValidationEndpointExists => '已经存在相同后端和 DID Host 的租户。';

  @override
  String get tenantValidationHasData =>
      '这个租户已经有本地数据，只能修改名称；如需更换后端或 DID Host，请添加租户配置。';

  @override
  String get tenantNotFound => '租户不存在。';

  @override
  String get tenantOperationFailed => '租户操作失败，请稍后重试。';

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
  String get onboardingMacHeroPrefix => '连接你的 ';

  @override
  String get onboardingMacHeroHighlight => 'Agent';

  @override
  String get onboardingMacHeroSuffix => ' 世界';

  @override
  String get onboardingMacSubtitle => '安全连接人、Agent 与组织，协作更智能，决策更高效。';

  @override
  String get onboardingMacFeatureSecureTitle => '安全可靠';

  @override
  String get onboardingMacFeatureSecureSubtitle => '企业级安全防护体系';

  @override
  String get onboardingMacFeatureCollaborateTitle => '高效协作';

  @override
  String get onboardingMacFeatureCollaborateSubtitle => '人机协同，信息无缝流转';

  @override
  String get onboardingMacFeatureControlTitle => '权限可控';

  @override
  String get onboardingMacFeatureControlSubtitle => '精细化权限，数据更安心';

  @override
  String get onboardingMacChipRequirementsAgent => '需求调研 Agent';

  @override
  String get onboardingMacChipRequirementsAgentCompact => '需求调研';

  @override
  String get onboardingMacChipPlanningAgent => '任务拆分 Agent';

  @override
  String get onboardingMacChipPlanningAgentCompact => '任务拆分';

  @override
  String get onboardingMacChipCodingAgent => '编码实现 Agent';

  @override
  String get onboardingMacChipCodingAgentCompact => '编码实现';

  @override
  String get onboardingMacChipUiDesignAgent => 'UI 设计 Agent';

  @override
  String get onboardingMacChipUiDesignAgentCompact => 'UI 设计';

  @override
  String get onboardingMacVerified => '已认证';

  @override
  String get onboardingMacOnline => '在线';

  @override
  String get onboardingCredentialsField => '身份凭证';

  @override
  String get onboardingNoLocalCredentialSaved => '本机暂无已保存身份凭证';

  @override
  String get secureMessagingClient => 'Secure messaging client';

  @override
  String get shellNavMessages => '消息';

  @override
  String get shellNavAgents => '智能体';

  @override
  String get shellNavFriends => '朋友';

  @override
  String get shellNavContacts => '联系人';

  @override
  String get shellNavTasks => '任务';

  @override
  String get shellNavWorkspace => '工作台';

  @override
  String get shellNavSettings => '设置';

  @override
  String get shellNavMe => '我';

  @override
  String get shellTasksPlaceholderTitle => '任务';

  @override
  String get shellTasksPlaceholderSubtitle => '任务视图即将接入。当前任务状态会在会话与身份卡中展示。';

  @override
  String get shellWorkspacePlaceholderTitle => '工作台';

  @override
  String get shellWorkspacePlaceholderSubtitle => '工作台模块即将接入。';

  @override
  String get conversationsTitle => '消息';

  @override
  String get conversationsNoMessagePreview => '暂无消息';

  @override
  String get conversationsEmptyTitle => '还没有消息';

  @override
  String get conversationsEmptySubtitle => '去关注联系人，或者先加入一个群聊吧。';

  @override
  String get conversationsRecentTitle => '最近会话';

  @override
  String get conversationsSearchPlaceholder => '搜索会话';

  @override
  String get conversationsNoResultsTitle => '没有找到相关会话';

  @override
  String get conversationsNoResultsSubtitle => '换个关键词试试';

  @override
  String get conversationsDeleteTitle => '删除会话';

  @override
  String get conversationsDeleteContent =>
      '会话将从最近列表移除，历史消息仍会保留。重新打开或收到新消息后，会话会再次出现在列表中。';

  @override
  String conversationsUnreadTag(Object count) {
    return '未读 $count';
  }

  @override
  String get conversationsMentionMeTag => '@我';

  @override
  String get conversationsDraftTag => '草稿';

  @override
  String conversationsAttachmentPreview(Object name) {
    return '附件：$name';
  }

  @override
  String get conversationsDeletedAgentBadge => '智能体已删除';

  @override
  String get conversationsNewMessages => '有新消息';

  @override
  String get conversationPeerBadgeGroup => '群';

  @override
  String get conversationPeerBadgeAi => 'AI';

  @override
  String get conversationPeerChatBadgeMyAgent => '我的智能体';

  @override
  String get conversationPeerChatBadgeAgent => '智能体';

  @override
  String get conversationPeerTypeGroup => '群聊';

  @override
  String get conversationPeerTypeAgent => '智能体';

  @override
  String get conversationPeerTypeUser => '用户';

  @override
  String get conversationPeerOwnerGroup => 'AWiki 群组';

  @override
  String get conversationPeerOwnerMyRuntimeAgent => '本机 Runtime Agent';

  @override
  String get conversationPeerOwnerAgent => 'AWiki 智能体';

  @override
  String get conversationPeerOwnerUser => 'AWiki 用户';

  @override
  String get conversationInfoTitle => '会话信息';

  @override
  String get conversationIdentityStatus => '身份状态:';

  @override
  String get conversationIdentityVerified => '已验证';

  @override
  String get conversationOwnerLabel => '所属:';

  @override
  String get conversationTypeLabel => '类型:';

  @override
  String get conversationCapabilitiesTitle => '会话能力';

  @override
  String get conversationCapabilitySendMessage => '发送消息';

  @override
  String get conversationCapabilityViewProfile => '查看资料';

  @override
  String get conversationCapabilitySecureConnection => '安全连接';

  @override
  String get conversationCapabilityHistory => '会话记录';

  @override
  String get conversationStatusTitle => '会话状态';

  @override
  String get conversationUnreadMessagesLabel => '未读消息:';

  @override
  String conversationUnreadMessagesValue(int count) {
    return '$count 条';
  }

  @override
  String get conversationLatestPreviewLabel => '最近预览:';

  @override
  String get conversationConnectionStatusLabel => '连接状态:';

  @override
  String get conversationConnectionEstablished => '已建立';

  @override
  String get conversationBackToChat => '返回会话';

  @override
  String get friendsTitle => '朋友';

  @override
  String get friendsGroups => '群组';

  @override
  String get friendsFollowing => '我关注的';

  @override
  String get friendsFollowers => '关注我的';

  @override
  String get friendsViewAll => '查看全部';

  @override
  String get friendsFollow => '关注';

  @override
  String get friendsUnfollow => '取消关注';

  @override
  String get friendsFollowingEmpty => '还没有关注任何人。';

  @override
  String get friendsFollowersEmpty => '还没有新的关注者。';

  @override
  String get friendsUnfollowTitle => '取消关注';

  @override
  String get friendsUnfollowMessage => '取消关注后，对方会从“我关注的”列表中移除。';

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
  String get profileOpenHomepage => '打开主页';

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
  String get settingsUpdateOpenGitHubHistory => '打开下载页查阅历史版本';

  @override
  String get settingsUpdateOpenGitHubDownload => '打开下载页下载当前版本';

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
  String get settingsDeleteCredential => '退出并删除当前凭证';

  @override
  String settingsDeleteCurrentCredential(Object credentialName) {
    return '删除本地凭证：$credentialName';
  }

  @override
  String get settingsDeleteCredentialFallback => '退出并删除当前登录凭证';

  @override
  String get settingsLogoutConfirmTitle => '退出登录';

  @override
  String get settingsLogoutConfirmContent => '确定要退出当前账号吗？';

  @override
  String get settingsDeleteCredentialConfirmTitle => '退出并删除当前凭证';

  @override
  String settingsDeleteCredentialConfirmContent(Object credentialName) {
    return '将退出当前登录，并删除本地凭证 \"$credentialName\"。删除后需要重新导入或恢复身份才能再次使用该凭证。确定继续吗？';
  }

  @override
  String get settingsDeleteCredentialConfirmAction => '退出并删除';

  @override
  String get quickActionsTitle => '更多操作';

  @override
  String get quickActionStartConversation => '发起新消息';

  @override
  String get quickActionCreateGroup => '创建群聊';

  @override
  String get quickActionJoinGroup => '加入群聊';

  @override
  String get quickActionFollowContact => '关注联系人';

  @override
  String get followContactTitle => '关注联系人';

  @override
  String get followContactPlaceholder => '输入 Handle 或 DID';

  @override
  String get followContactAlreadyFollowing => '已关注';

  @override
  String get followContactSucceeded => '已关注';

  @override
  String get identityStartConversationSubtitle =>
      '输入 handle、DID 或 Agent 地址，确认身份后开始可信会话。';

  @override
  String get identityStartConversationAction => '开始聊天';

  @override
  String get identityStartConversationNotice =>
      '消息将通过已验证 DID 连接发送；首次联系外部身份请谨慎确认。';

  @override
  String get identityFollowContactTitle => '关注联系人 / Agent';

  @override
  String get identityFollowContactSubtitle => '输入 handle 或 DID，确认身份后关注该身份。';

  @override
  String get identityFollowContactAction => '关注';

  @override
  String get identityFollowContactNotice => '确认身份后会关注该联系人或 Agent。';

  @override
  String get identityInputSemantics => '输入 handle 或 DID';

  @override
  String get identityInputPlaceholder => '输入 @handle / DID / Agent 地址';

  @override
  String get identitySearchLabel => '匹配身份';

  @override
  String get identityResolving => '匹配中...';

  @override
  String get identitySubmitting => '处理中...';

  @override
  String get identityQueryRequired => '请输入 handle 或 DID。';

  @override
  String get identityResolveFailed => '未找到该身份，请检查 handle / DID 是否正确。';

  @override
  String get identityInvalidContact => '联系人身份无效，无法打开会话。';

  @override
  String get identityMissingDid => '身份解析结果缺少 DID。';

  @override
  String get identityVerified => '已验证';

  @override
  String get identityTypeLabel => '类型';

  @override
  String get identityRelationshipLabel => '关系';

  @override
  String get identityBioLabel => '简介';

  @override
  String get identityTypeAgent => '智能体';

  @override
  String get identityTypeUser => '用户';

  @override
  String get identityAddGroupMemberTitle => '添加群成员';

  @override
  String get identityAddGroupMemberSubtitle =>
      '输入普通用户或 Agent 的 handle / DID，确认身份后加入群聊。';

  @override
  String get identityAddGroupMemberAction => '确认添加';

  @override
  String get identityAddGroupMemberNotice => '请确认这是要加入群聊的身份。';

  @override
  String get identityClearInput => '清空输入';

  @override
  String get identitySearchNameHandleDid => '搜索名称、handle、DID';

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
  String get groupCreateTitle => '创建群聊';

  @override
  String get groupCreateAction => '创建';

  @override
  String get groupFieldName => '名称';

  @override
  String get groupFieldNamePlaceholder => '输入群聊名称';

  @override
  String get groupCreating => '正在创建群组...';

  @override
  String get groupAddMembers => '添加成员';

  @override
  String get groupRefreshMembers => '刷新成员';

  @override
  String get groupDetails => '查看群详情';

  @override
  String get groupRemoveMember => '移除成员';

  @override
  String get groupInviteDialogSubtitle => '搜索本地身份，或输入 handle / DID 匹配新身份。';

  @override
  String get groupInviteShowMore => '查看更多';

  @override
  String get groupInviteAdding => '添加中...';

  @override
  String groupInviteConfirmCount(int count) {
    return '确认添加 ($count)';
  }

  @override
  String get groupInviteCandidates => '可邀请的身份';

  @override
  String get groupInviteSearchResults => '搜索结果';

  @override
  String get groupInviteSelectHint => '选择一个或多个身份后，统一确认添加。';

  @override
  String get groupInviteNoLocalCandidates => '暂无可邀请的本地身份。';

  @override
  String get groupInviteNoMatches => '没有匹配的本地身份，可以尝试匹配 handle / DID。';

  @override
  String get groupInviteAlreadyInGroup => '已在群中';

  @override
  String get groupInviteUnnamedAgent => '未命名智能体';

  @override
  String get groupInviteSourceMyAgents => '我的智能体';

  @override
  String get groupInviteSourceFollowing => '我关注的';

  @override
  String get groupInviteSourceFollowers => '关注我的';

  @override
  String get groupInviteSourceRecent => '最近会话';

  @override
  String get groupInviteSourceResolved => '匹配结果';

  @override
  String groupRemoveMemberContent(Object memberTitle) {
    return '移除 $memberTitle 后，对方将不能继续在这个群里发送消息。';
  }

  @override
  String get chatUnknownUser => 'Unknown';

  @override
  String get chatConversationUntitled => '未命名会话';

  @override
  String get chatHeaderGroup => 'GROUP';

  @override
  String get chatHeaderOnline => 'ONLINE';

  @override
  String get chatInputPlaceholder => '输入消息...';

  @override
  String get chatDeletedAgentDisabled => '智能体已删除，无法继续发送消息';

  @override
  String get chatGroupLeftDisabled => '你已不在这个群聊中，不能继续发送消息';

  @override
  String get chatGroupSendDisabled => '当前群聊暂时不能发送消息';

  @override
  String get chatAgentProcessing => '智能体正在处理...';

  @override
  String get chatAgentStillProcessing => '智能体仍在处理，稍后可刷新查看';

  @override
  String chatSubjectProcessing(Object subject) {
    return '$subject 正在处理...';
  }

  @override
  String chatSubjectStillProcessing(Object subject) {
    return '$subject 仍在处理，稍后可刷新查看';
  }

  @override
  String get chatAgentSubject => '智能体';

  @override
  String chatAgentCountSubject(int count) {
    return '$count 个智能体';
  }

  @override
  String get chatSafeCollaboration => '安全协作中';

  @override
  String get chatAddAttachment => '添加附件';

  @override
  String get chatAddEmoji => '选择表情';

  @override
  String get chatCaptureScreenshot => '截图';

  @override
  String get screenshotPermissionRequired =>
      '录屏权限尚未生效。请在系统设置的“录屏与系统录音”中允许当前 AWiki Me 应用，然后完全退出并重新打开。';

  @override
  String get chatRemoveAttachment => '移除附件';

  @override
  String get chatViewAttachment => '查看附件';

  @override
  String get chatAttachmentFileFallback => '文件';

  @override
  String get chatLoadingMentionCandidates => '正在加载 mention 候选…';

  @override
  String get mentionCandidateBadgeUser => '用户';

  @override
  String get mentionCandidateBadgeAgent => '智能体';

  @override
  String get mentionCandidateBadgeUnknown => '类型未知';

  @override
  String get mentionSelectorAllSurface => '@所有人';

  @override
  String get mentionSelectorHumansSurface => '@所有用户';

  @override
  String get mentionSelectorAgentsSurface => '@所有智能体';

  @override
  String get mentionSelectorAllSubtitle => '提醒群内所有成员';

  @override
  String get mentionSelectorHumansSubtitle => '只提醒群内用户';

  @override
  String get mentionSelectorAgentsSubtitle => '提醒群内智能体';

  @override
  String get mentionSelectorAllBadge => '用户 + 智能体';

  @override
  String get mentionDisabledUnknownMemberType => '成员类型未知，暂不能作为单人 mention 目标';

  @override
  String get mentionDisabledInactiveMember => '成员状态不是 active，暂不能 mention';

  @override
  String get chatSendFailed => '发送失败';

  @override
  String get chatRetrySend => '重试发送';

  @override
  String get chatSending => '发送中';

  @override
  String get chatViewPeerInfo => '查看用户或智能体信息';

  @override
  String chatOpenPeerInfo(Object type) {
    return '打开$type信息';
  }

  @override
  String get chatCurrentConversationCannotSend => '当前会话无法继续发送消息';

  @override
  String get chatAgentDeletedBadge => '智能体已删除';

  @override
  String get chatPeerInfoUserTitle => '用户信息';

  @override
  String get chatPeerInfoAgentTitle => '智能体信息';

  @override
  String get chatPeerInfoGroupTitle => '群聊信息';

  @override
  String get chatPeerInfoGroupSection => '群聊';

  @override
  String get chatPeerInfoIdentityCard => '身份卡';

  @override
  String get chatPeerInfoClose => '关闭信息弹窗';

  @override
  String get chatPeerInfoCopyDid => '复制 DID';

  @override
  String get chatPeerInfoDidCopied => 'DID 已复制';

  @override
  String get chatPeerInfoProfileLoading => '资料加载中';

  @override
  String get chatPeerInfoProfileUnavailable => '资料暂不可用';

  @override
  String get chatPeerInfoAwikiUser => 'AWiki 用户';

  @override
  String get chatPeerInfoCollapseAgentInbox => '收起 Agent 收件箱';

  @override
  String get chatPeerInfoAgentInbox => 'Agent 收件箱';

  @override
  String get chatPeerInfoUnknownContact => '未知联系人';

  @override
  String get chatPeerInfoLoadingProfile => '正在加载资料…';

  @override
  String get chatPeerInfoNoProfile => '暂未填写资料';

  @override
  String get chatPeerInfoRenameAgent => '修改智能体名称';

  @override
  String get chatPeerInfoRenameAgentTooltip => '修改名称';

  @override
  String chatPeerInfoMemberCount(int count) {
    return '共 $count 位成员';
  }

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
  String get agentPageTitle => '智能体';

  @override
  String get agentCreateDaemon => '创建 Daemon';

  @override
  String get agentRefreshList => '刷新智能体列表';

  @override
  String get agentEmpty => '暂无代理';

  @override
  String get agentEmptyWaitingHost => '当前账号还没有可用的 Daemon。安装完成后可自动同步，也可以手动刷新。';

  @override
  String get agentEmptyInstallWaitingHost => '正在等待宿主机完成 Daemon 安装，完成后会自动出现。';

  @override
  String get agentSelectOne => '选择一个代理';

  @override
  String get agentCreateRuntime => '创建 Agent';

  @override
  String get agentOpenChat => '打开聊天';

  @override
  String get agentRename => '改名';

  @override
  String get agentUpgrade => '升级';

  @override
  String get agentUpgrading => '升级中';

  @override
  String get agentCancelUpgrade => '取消升级';

  @override
  String get agentCancelling => '取消中';

  @override
  String get agentDeleteDaemon => '删除代理';

  @override
  String get agentDeleteRuntime => '删除智能体';

  @override
  String get agentRemoveFromAccount => '从账号移除';

  @override
  String get agentDeleting => '删除中';

  @override
  String get agentRecentRuns => '最近 Run';

  @override
  String get agentRefreshStatus => '刷新状态';

  @override
  String get agentDeletingNotice => '删除请求已发送，正在等待代理同步。';

  @override
  String agentDaemonSubtitle(int count, Object status) {
    return 'Daemon · $count 个 Agent · $status';
  }

  @override
  String agentRuntimeSubtitle(Object runtime, Object status) {
    return '$runtime · $status';
  }

  @override
  String get agentUnnamedDaemon => '未命名 Daemon';

  @override
  String get agentUnnamedRuntime => '未命名智能体';

  @override
  String get agentListDeletingSync => '删除中 · 等待同步';

  @override
  String get agentListUpgradeFailed => '升级失败';

  @override
  String get agentListCancellingUpgrade => '正在取消升级';

  @override
  String get agentListOrphanGroup => '未关联 Daemon';

  @override
  String get agentListNoRuntime => '尚未创建 Runtime Agent';

  @override
  String agentListRuntimeCreating(Object runtime) {
    return '$runtime · 创建中';
  }

  @override
  String agentListRuntimeWaitingStatus(Object runtime) {
    return '$runtime · 创建状态暂未返回，可刷新查看';
  }

  @override
  String get daemonUpgradePreparingDownload => '正在准备下载';

  @override
  String get daemonUpgradeRouteDirect => '直连';

  @override
  String get daemonUpgradeRouteEnvironmentProxy => '代理';

  @override
  String daemonUpgradeRouteLocalProxy(Object route) {
    return '本机代理 $route';
  }

  @override
  String daemonUpgradeDownloaded(Object size) {
    return '已下载 $size';
  }

  @override
  String daemonUpgradeRouteIndex(int index, int count) {
    return '线路 $index/$count';
  }

  @override
  String get agentUpgradeTitle => '升级代理';

  @override
  String get agentUpgradeMessage => '代理会下载 latest 版本并重启服务。';

  @override
  String get daemonUpgradeRequesting => '正在发送升级请求';

  @override
  String get daemonUpgradeWaitingForDaemon => '升级请求已发送，正在等待 Daemon 确认';

  @override
  String get daemonUpgradeFetchingManifest => '正在获取版本信息';

  @override
  String get daemonUpgradeSelectingSource => '正在选择下载线路';

  @override
  String get daemonUpgradeDownloading => '正在下载安装包';

  @override
  String get daemonUpgradeRetryingSource => '下载中断，正在重试';

  @override
  String get daemonUpgradeVerifying => '正在校验安装包';

  @override
  String get daemonUpgradeExtracting => '正在解压安装包';

  @override
  String get daemonUpgradeInstalling => '正在安装新版本';

  @override
  String get daemonUpgradeRestarting => '正在重启 Daemon';

  @override
  String get daemonUpgradeInProgress => '正在升级';

  @override
  String get agentUpgradeIncomplete => '升级没有完成，请检查网络后重试。';

  @override
  String agentUpgradeDownloadFailed(Object summary) {
    return '安装包下载失败，请检查网络后重试。$summary';
  }

  @override
  String get agentUpgradeNotCancellable => '当前升级已经进入重启阶段，无法取消。请稍后刷新状态确认结果。';

  @override
  String get agentUpgradeCancelFailed => '取消升级失败，请刷新状态后重试。';

  @override
  String get agentUpgradeCancelNoResponse =>
      '取消请求已发送，但 Daemon 暂未响应。请刷新状态确认升级结果。';

  @override
  String get agentDeleteDaemonMessage =>
      '删除后会停止宿主机上的代理服务，并移除它创建的智能体。本地数据会归档保留，不会继续使用。';

  @override
  String get agentDeleteRuntimeMessage => '删除后该智能体会从列表中移除。本地数据会归档保留，不会继续使用。';

  @override
  String get agentRemoveDaemonFromAccountMessage =>
      '当前 Daemon 不可连接。此操作只会从当前账号移除这个 Daemon 以及它创建的智能体，不会访问或清理宿主机上的本地文件。';

  @override
  String get agentRemoveRuntimeFromAccountMessage =>
      '当前无法通过所属 Daemon 删除这个智能体。此操作只会把它从当前账号移除，不会访问或清理宿主机上的本地文件。';

  @override
  String get agentInstallTitle => '到宿主机安装代理';

  @override
  String get agentInstallSupportedTypes =>
      '支持的 Agent 类型：Hermes、Codex、Claude Code。安装宿主代理后，可在 Daemon 下创建 Runtime Agent。';

  @override
  String agentInstallTokenExpiresAt(Object expiresAt) {
    return '有效期至: $expiresAt';
  }

  @override
  String get agentCopyInstallCommand => '复制安装命令';

  @override
  String get agentCleanupHostTitle => '清理宿主机';

  @override
  String get agentCleanupHostToggle => '需要清理宿主机上的旧 Daemon？';

  @override
  String get agentCleanupHostWarning =>
      '这会停止宿主机上的 AWiki Daemon，并永久删除该宿主机上的所有 Daemon 数据，包括身份、数据库、日志、归档、Runtime Profile 和已下载的 Daemon 二进制。此操作不可恢复。';

  @override
  String get agentCopyCleanupCommand => '复制清理命令';

  @override
  String get agentCreateTitle => '创建 Agent';

  @override
  String get agentCreateType => 'Agent 类型';

  @override
  String get agentCreateWorkspacePolicy => '工作目录策略';

  @override
  String get agentCreateWorkspaceRouteRoot => '按会话目录';

  @override
  String get agentCreateWorkspaceRouteRootDescription =>
      '每个联系人、群组或线程使用独立上下文目录。';

  @override
  String get agentCreateWorkspaceSharedRoot => '共享目录';

  @override
  String get agentCreateWorkspaceSharedRootDescription => '该身份共用一个目录，适合手工任务。';

  @override
  String get agentCreateWorkspaceWorktreePerTask => '每次任务 worktree';

  @override
  String get agentCreateWorkspaceWorktreePerTaskDescription => '每次运行使用独立工作树。';

  @override
  String agentCreateHandlePreview(Object handle) {
    return '最终 Handle：$handle';
  }

  @override
  String get agentCreateHandleAvailabilityChecking => '正在校验可用性...';

  @override
  String get agentCreateHandleAvailabilityPending => '暂时无法校验可用性，创建时会再次确认';

  @override
  String get agentCreateHandleChecking => '正在校验 Handle 可用性';

  @override
  String get agentCreateHandleAvailable => '这个 Handle 可以使用';

  @override
  String get agentCreateHandleUnavailableUsed => '这个 Handle 已被使用';

  @override
  String get agentCreateHandleUnavailable => '这个 Handle 不可使用';

  @override
  String get agentCreateHandleRequired => '请输入 Handle';

  @override
  String agentCreateHandleTooLong(Object maxLength) {
    return 'Handle 最多 $maxLength 个字符';
  }

  @override
  String get agentCreateHandleInvalidPattern => '仅支持小写字母、数字和连字符，且首尾必须是字母或数字';

  @override
  String get agentCreateHandleNoDoubleHyphen => 'Handle 不能包含连续连字符';

  @override
  String agentCreateNeedsRouteWorkspace(Object agentType) {
    return '$agentType 需要按会话目录工作模式。';
  }

  @override
  String get agentCreateHermesDescription => '内置 Hermes Runtime Agent。';

  @override
  String agentCreateNeedsGenericCliCapability(Object agentType) {
    return '$agentType 需要 Daemon 提供 generic-cli capability。';
  }

  @override
  String agentCreateUnsupportedDriver(Object agentType) {
    return '当前 Daemon 不支持 $agentType driver。';
  }

  @override
  String agentCreateNeedsRouteSession(Object agentType) {
    return '$agentType 需要 route session 和 native resume 支持。';
  }

  @override
  String agentCreateNeedsHostAccess(Object agentType) {
    return '$agentType 需要 Daemon 支持宿主机全权限模式。';
  }

  @override
  String agentCreateRequiresSignedInCli(Object agentType) {
    return '需要 Daemon 上已安装并登录的 $agentType CLI。';
  }

  @override
  String get agentCreateHostAccessTitle => '宿主机全权限';

  @override
  String get agentCreateHostAccessDescription => '可按用户指令使用本机文件、命令、工具和网络。';

  @override
  String get agentRenameTitle => '修改智能体名称';

  @override
  String get agentRenameSubtitle => '名称会显示在智能体列表、最近会话和对话窗口中。';

  @override
  String get agentNameField => '名称';

  @override
  String get agentNamePlaceholder => '显示名称';

  @override
  String agentNameHelp(int maxLength) {
    return '最多 $maxLength 个字符。';
  }

  @override
  String get agentNameRequired => '请输入智能体名称';

  @override
  String agentNameTooLong(int maxLength) {
    return '名称最多 $maxLength 个字符';
  }

  @override
  String get agentStatusProcessing => '正在处理';

  @override
  String get agentStatusReady => '正常';

  @override
  String get agentStatusNeedsConfig => '需要配置';

  @override
  String get agentStatusNeedsUpgrade => '需要升级';

  @override
  String get agentStatusFailed => '异常';

  @override
  String get agentStatusOffline => '离线';

  @override
  String get agentStatusDisabled => '已停用';

  @override
  String get agentStatusUnknown => '未知';

  @override
  String get agentStatusRefreshNeeded => '需刷新';

  @override
  String get agentStatusUnsupported => '未支持';

  @override
  String agentStatusSemantic(Object status) {
    return '智能体状态：$status';
  }

  @override
  String get agentErrorLoginRequired => '请先登录。';

  @override
  String get agentErrorHandleUnavailable =>
      '当前账号没有可用 Handle，暂时不能生成 Daemon 安装命令。';

  @override
  String get agentErrorMessageAgentDisabled => '消息处理 Agent 功能未开启。';

  @override
  String get agentTenantUnsupportedTitle => '当前租户暂不支持智能体';

  @override
  String get agentTenantUnsupportedSubtitle =>
      '请回到登录页切换到 AWiki 主租户后，再管理 Daemon 和智能体。';

  @override
  String get agentErrorTenantUnsupported => '当前租户暂不支持智能体功能。';

  @override
  String get agentErrorSelectDaemon => '请选择运行 Daemon。';

  @override
  String get agentErrorDaemonBootstrapMissing =>
      '运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新状态。';

  @override
  String get agentErrorDaemonUnreachableDelete => 'Daemon 当前不可达，暂时不能删除。';

  @override
  String get agentErrorDaemonUnreachableUpgrade =>
      'Daemon 当前不可达，暂时不能升级。请先刷新状态或重新安装。';

  @override
  String get agentErrorMessageAgentMissing => '当前 Daemon 尚未创建消息处理 Agent。';

  @override
  String get agentStatusSyncStillWaiting => '状态同步仍在等待，请稍后刷新查看。';

  @override
  String get agentErrorScopeMismatch =>
      '这台电脑已经绑定到另一个 Handle 的 Daemon。请使用对应 Handle 管理，或先清理宿主机上的 AWiki Daemon 数据后重新安装。';

  @override
  String get agentErrorControllerHandleMismatch =>
      '当前客户端身份和登录 Handle 不一致，请切换到正确账号后重新复制安装命令。';

  @override
  String get agentErrorControllerScopeMissing =>
      '安装命令缺少账号归属信息，请重新复制最新的 Daemon 安装命令。';

  @override
  String get agentErrorInstallCommandUsed =>
      '这条安装命令已经使用过，请重新复制最新的 Daemon 安装命令。';

  @override
  String get agentErrorSessionExpired => '登录状态已失效，请重新登录后再查看智能体。';

  @override
  String get agentErrorRequestTimeout => '请求超时，请稍后重试。';

  @override
  String get agentErrorNetworkPreserved => '网络连接暂时不可用，已保留当前数据。';

  @override
  String get agentErrorLoadFailed => '智能体信息暂时无法加载，请稍后重试。';

  @override
  String get agentErrorStatusSessionExpired => '登录状态已失效，请重新登录后再刷新代理状态。';

  @override
  String get agentErrorStatusTimeout => '刷新状态超时，当前数据已保留。';

  @override
  String get agentErrorStatusNetworkPreserved => '网络连接暂时不可用，当前数据已保留。';

  @override
  String get agentErrorStatusRefreshFailed => '状态刷新请求发送失败，请稍后再试。';

  @override
  String get agentAccessTitle => '访问权限';

  @override
  String get agentAccessSubtitle => '配置 Handle 对智能体的控制权限';

  @override
  String get agentAccessWhitelist => '白名单';

  @override
  String get agentAccessBlacklist => '黑名单';

  @override
  String get agentAccessSwitchToWhitelist => '切换到白名单模式';

  @override
  String get agentAccessSwitchToBlacklist => '切换到黑名单模式';

  @override
  String get agentAccessCurrentWhitelist => '当前白名单模式';

  @override
  String get agentAccessCurrentBlacklist => '当前黑名单模式';

  @override
  String get agentAccessEnabled => '已启用';

  @override
  String get agentAccessDisabled => '已禁用';

  @override
  String get agentAccessHandlePlaceholder => 'bob 或 bob.example.com';

  @override
  String get agentAccessAddHandle => '添加 Handle';

  @override
  String get agentAccessNoHandles => '暂无 Handle';

  @override
  String get agentAccessRemoveHandle => '删除 Handle';

  @override
  String get agentAccessDuplicateWhitelist => '这个 Handle 已在白名单中。';

  @override
  String get agentAccessDuplicateBlacklist => '这个 Handle 已在黑名单中。';

  @override
  String get agentAccessHandleRequired => '请输入 Handle。';

  @override
  String get agentAccessSingleHandleOnly => '每次只能添加一个 Handle。';

  @override
  String get agentAccessHandleInvalid => '请输入短 Handle 或完整 Handle。';

  @override
  String get agentDiagnosticsTitle => '诊断信息';

  @override
  String get agentDiagnosticsDaemonSubtitle => 'Daemon 运行与身份信息';

  @override
  String get agentDiagnosticsAgentSubtitle => '智能体身份信息';

  @override
  String get agentDiagnosticsShowMore => '查看更多';

  @override
  String get agentDiagnosticsCollapse => '收起';

  @override
  String get agentDiagnosticsShowMoreDetails => '查看更多诊断';

  @override
  String get agentDiagnosticsCollapseDetails => '收起诊断详情';

  @override
  String get agentDiagnosticCurrentVersion => '当前版本';

  @override
  String get agentDiagnosticPlatform => '平台';

  @override
  String get agentDiagnosticLatestVersion => '最新版本';

  @override
  String get agentDiagnosticMinSupportedVersion => '最低可用版本';

  @override
  String get agentDiagnosticService => '服务';

  @override
  String get agentDiagnosticLastSeen => '最近上报';

  @override
  String get agentDiagnosticErrorCode => '错误代码';

  @override
  String get agentDiagnosticRunner => '运行器';

  @override
  String get agentDiagnosticProfileStatus => '配置状态';

  @override
  String get agentDiagnosticInstallationStatus => '安装状态';

  @override
  String get agentDiagnosticServiceInstalled => '服务安装';

  @override
  String get agentDiagnosticConfigSummary => '配置摘要';

  @override
  String get agentDiagnosticHermesProfile => 'Hermes 配置';

  @override
  String get agentDiagnosticRunnerStatus => '运行状态';

  @override
  String get agentDiagnosticActiveSessionCount => '活跃会话';

  @override
  String get messageAgentSkipped => '消息 Agent 跳过此消息';

  @override
  String get messageAgentFailed => '消息 Agent 处理失败';

  @override
  String get messageAgentCompleted => '消息 Agent 已完成处理';

  @override
  String get messageAgentProcessing => '消息 Agent 正在处理';

  @override
  String get messageAgentReceived => '消息 Agent 已收到消息';

  @override
  String get messageAgentResultGenerated => '已生成处理结果';

  @override
  String get messageAgentDraftApplied => '草稿已放入输入框';

  @override
  String get messageAgentAppActionCompleted => 'App action 已完成';

  @override
  String get messageAgentRequestRejected => '已拒绝消息 Agent 请求';

  @override
  String get messageAgentAppActionFailed => 'App action 处理失败';

  @override
  String get messageAgentWaitingConfirmation => '等待确认';

  @override
  String get messageAgentUseDraft => '使用草稿';

  @override
  String get messageAgentActionCreateDraft => '消息 Agent 生成了草稿';

  @override
  String get messageAgentActionSummarize => '消息 Agent 生成了摘要';

  @override
  String get messageAgentActionReadContact => '消息 Agent 请求读取联系人';

  @override
  String get messageAgentActionUpdateDisplayName => '消息 Agent 请求修改联系人名称';

  @override
  String get messageAgentActionUpdateNote => '消息 Agent 请求修改联系人备注';

  @override
  String get messageAgentActionGeneric => '消息 Agent 请求 App action';

  @override
  String get messageAgentTitle => '消息处理 Agent';

  @override
  String messageAgentRuntimeSubtitle(Object provider) {
    return '运行 Daemon 内创建 $provider runtime';
  }

  @override
  String get messageAgentExperimentDisabled => '实验功能关闭';

  @override
  String get messageAgentReadyToEnable => '可启用';

  @override
  String get messageAgentNotReady => '未就绪';

  @override
  String get messageAgentRunningDaemon => '运行 Daemon';

  @override
  String get messageAgentEngine => '引擎';

  @override
  String get messageAgentScope => '处理范围';

  @override
  String get messageAgentAllProcessableConversations => '所有可处理会话';

  @override
  String get messageAgentDaemonVersion => 'Daemon 版本';

  @override
  String get messageAgentCapabilities => '可用能力';

  @override
  String get messageAgentSecureBootstrap => '安全 bootstrap';

  @override
  String get messageAgentPublicKeyReported => '已上报公钥';

  @override
  String get messageAgentWaitingStatusRefresh => '等待刷新状态';

  @override
  String get messageAgentEnable => '启用消息处理 Agent';

  @override
  String get messageAgentEnabling => '启用中';

  @override
  String get messageAgentPause => '暂停处理消息';

  @override
  String get messageAgentDelete => '删除消息处理 Agent';

  @override
  String get messageAgentRevokeAuthorization => '撤销 Daemon 消息授权';

  @override
  String get messageAgentPermissionSummaryEnabled =>
      '权限摘要：读取普通消息，分析、总结、生成草稿，并向 App 请求需要确认的 action。';

  @override
  String get messageAgentPermissionSummaryDisabled =>
      '切回 AWiki 主租户后可配置消息处理 Agent。';

  @override
  String get messageAgentPauseTitle => '暂停处理消息';

  @override
  String get messageAgentPauseMessage =>
      '暂停后，消息处理 Agent 不再读取和处理新消息；runtime 和授权仍会保留，可以重新启用。';

  @override
  String get messageAgentDeleteTitle => '删除消息处理 Agent';

  @override
  String get messageAgentDeleteMessage =>
      '删除前会先暂停消息处理，然后归档对应 runtime。Daemon 和授权不会被删除。';

  @override
  String get messageAgentRevokeTitle => '撤销 Daemon 消息授权';

  @override
  String get messageAgentRevokeMessage =>
      '撤销需要先通过签名 DID Document 更新移除 daemon-key-1。未完成更新时会失败，不会把暂停误认为撤销成功。';

  @override
  String get agentInboxTitle => 'Agent 收件箱';

  @override
  String get agentInboxThreadTitle => '收件箱线程';

  @override
  String get agentInboxBackToInbox => '返回收件箱';

  @override
  String get agentInboxBackToConversation => '返回会话';

  @override
  String get agentInboxClose => '关闭 Agent 收件箱';

  @override
  String get agentInboxNotRuntimeConversation => '当前会话不是 Runtime Agent 会话';

  @override
  String get agentInboxDaemonMissing => '这个 Runtime Agent 暂时没有绑定 Daemon';

  @override
  String get agentInboxRefresh => '刷新 Agent 收件箱';

  @override
  String get agentInboxEmpty => '这个 Agent 暂时没有收件箱消息';

  @override
  String get agentInboxLoadMoreThreads => '加载更多会话';

  @override
  String get agentInboxScopeAll => '全部';

  @override
  String get agentInboxScopeDirect => '私聊';

  @override
  String get agentInboxScopeGroup => '群聊';

  @override
  String get agentInboxLatestAttachment => '最新：附件';

  @override
  String get agentInboxLatestNoPreview => '最新：无预览';

  @override
  String agentInboxLatestPreview(Object preview) {
    return '最新：$preview';
  }

  @override
  String get agentInboxReadOnly => '只读收件箱';

  @override
  String get agentInboxRefreshThread => '刷新收件箱线程';

  @override
  String get agentInboxThreadEmpty => '这个线程暂时没有消息';

  @override
  String get agentInboxLoadEarlier => '加载更早消息';

  @override
  String get agentInboxContentTruncated => '内容较长，已截断';

  @override
  String get agentInboxDaemonNoResponse => 'Daemon 暂时没有返回，请稍后重试';

  @override
  String get agentInboxQueryFailed => '收件箱查询失败';

  @override
  String get agentInboxThreadQueryFailed => '线程查询失败';

  @override
  String get relationshipNone => '未关注';

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
  String get updateOpenDownloadFailed => '无法打开下载页面，请稍后重试。';

  @override
  String get updateReadyToInstall => '下载完成，准备安装。';

  @override
  String get updatePermissionRequired => '请允许安装未知应用后重试。';

  @override
  String get updateInstallFailed => '更新失败，请打开下载页手动安装。';

  @override
  String get daemonUpgradeStarted => '已开始升级代理。';

  @override
  String get requestTimeoutRetry => '请求超时，请检查网络后重试。';

  @override
  String get networkUnavailableRetry => '网络连接暂时不可用，请检查网络后重试。';

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
  String get didNotFoundOrRevoked =>
      '未找到这个身份，或它已经被撤销。请检查 DID 是否正确，或切换到可用身份后重试。';

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
  String get documentSaveFailed => '文件保存失败，请稍后重试。';

  @override
  String get attachmentDownloadEmpty => '附件下载结果为空。';

  @override
  String get conversationRemovedFromRecents => '已从最近会话移除';

  @override
  String get attachmentUnavailable => '附件文件已过期或本机缓存不存在，请让对方重新发送。';

  @override
  String get attachmentOpenFailed => '附件无法打开，请稍后重试或保存后再打开。';

  @override
  String get linkOpenFailed => '无法打开链接';

  @override
  String linkOpenFailedWithDetail(Object detail) {
    return '无法打开链接: $detail';
  }

  @override
  String get groupNameRequired => '群名称不能为空';

  @override
  String chatGroupMemberAddedByYou(Object member) {
    return '你邀请$member加入了群聊';
  }

  @override
  String chatGroupMemberAddedBy(Object actor, Object member) {
    return '$actor邀请$member加入了群聊';
  }

  @override
  String chatGroupMemberJoined(Object member) {
    return '$member加入了群聊';
  }

  @override
  String chatGroupMemberRemovedByYou(Object member) {
    return '你将$member移出了群聊';
  }

  @override
  String chatGroupMemberRemovedBy(Object actor, Object member) {
    return '$actor将$member移出了群聊';
  }

  @override
  String chatGroupMemberLeft(Object member) {
    return '$member退出了群聊';
  }

  @override
  String get chatGroupProfileUpdated => '群信息已更新';
}
