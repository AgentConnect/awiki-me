# 服务器功能与网络设置页

服务器功能页只消费 Core 的 BackendCapabilitiesPort 安全投影，不试调用业务接口判断功能，
也不把服务声明当作当前账号授权、当前会话加密或实时健康结论。

## 展示

沿用 App 的设置标题、主题、分组容器和 Cupertino 控件。服务器名称与域名明确当前上下文；
聊天与加密、账户与服务按独立来源分组，各自显示确认时间、旧快照或不兼容提示。
十项功能全部展开，显示图标、名称、简短说明和支持／暂不支持／待确认状态。
`content.pages` 只命名为“内容页面”，不代替独立的 `content.sites`。

内容宽度最多 1040，水平留白 16、列间距 12。每列最小宽度 240，随文字缩放增大，
按实际内容区宽度选择一至三列。每行按自然最高内容对齐，不固定宽高比，不截断说明。
手机设置列表补齐服务器功能入口；桌面右侧嵌入页和独立页面复用同一展示。

刷新保留已有投影，同页只允许一次主动刷新；异常在页内提供反馈和重试。
租户、会话代次或 Core port 变化清除原上下文的局部刷新状态，迟到结果不更新新页面状态。

网络页只保留现有系统代理开关，说明与开关同组；最近连接方式另组显示，不代表测速。
首次读取完成前不显示默认路径为实际结果；读取失败保留最近结果并标明状态不可更新。
初始化失败可重试，保存失败沿用原策略回滚，状态读取不阻塞已初始化的代理设置。
两秒状态读取合并重叠请求，页面销毁停止定时器与监听。Android/iOS/Web 不新增网络入口。

## 2026-10-29 定向验证

- `flutter analyze --no-pub lib/src/presentation/settings lib/src/presentation/server_features lib/src/data/services/desktop_network_preference.dart tests/unit/settings_detail_layout_test.dart`：无问题。
- `flutter test --no-pub tests/unit/settings_detail_layout_test.dart tests/unit/server_features_test.dart tests/unit/desktop_network_preference_test.dart tests/unit/settings_workspace_test.dart tests/unit/settings_page_test.dart tests/unit/settings_version_layout_test.dart`：89 passed，失败 0、跳过 0。
- 新增布局检查覆盖 320/560/1100 宽、1/2 倍文字、中英文、深浅色，共 24 组、两页 48 种展示组合；覆盖全部卡片滚动可达与开关边界。
- 补充初始化失败后重试、诊断请求合并、读取失败、刷新防重、异常脱敏、销毁后迟到结果和四个平台的窄屏入口检查。
- 补入口后发现底部安全操作超出首屏几像素，采用 44 高入口修复；原首屏安全操作回归继续通过。
- 本轮不执行全量 System 或产品 E2E，不变更底层网络路径、协议或 SDK。Mac Debug 复用既有来源已核验的 arm64 Core；不代表 Windows/手机原生验收。

Mac normal main.dart 双 Debug 编译通过，Core 来源及中间库逐字节核验通过。最后一次增量构建
因外层仍记录旧 framework 封存而未通过签名检查；内嵌框架逐项有效。仅对两个本地 Debug App
重新执行原有 ad-hoc 外层签名并保留 entitlements/requirements/flags，随后 deep/strict 检查通过。
未改项目签名配置或正式客户端。桌面继续使用独立恢复调试 App 与原有隔离数据目录。
