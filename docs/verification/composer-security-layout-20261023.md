# 移动端加密按钮分组验证（2026-10-23）

分支：`test/singapore-release-20261022`。

## 改动

Compact 输入栏将加密按钮并入附件、表情所在的工具胶囊，复用 40 方形按钮、21 图标和现有缩放。开启时使用主题色闭锁与淡色圆底，关闭时使用普通色开锁。输入框继续占用剩余宽度、自动换行撑高，两侧按钮底部对齐。Expanded 桌面布局、状态来源、偏好持久化和发送合同保持原行为。

## 定向检查

以下检查在本机 macOS arm64、Flutter 3.44.0 / Dart 3.12.0 执行。

| 命令 | 结果 |
| --- | --- |
| `dart analyze lib/src/presentation/chat/chat_page.dart tests/unit/chat_page_test.dart` | 通过，无问题 |
| `flutter test tests/unit/chat_page_test.dart --name 'compact 加密按钮\|compact 聊天使用\|未提供加密时禁止切换\|macOS 聊天输入条保持发送能力\|加密群在标题\|发送.*加密\|加密.*发送\|输入法\|附件.*预览\|个人助理.*(加密\|锁)' --reporter expanded` | 26 项通过 |
| `flutter test tests/unit/chat_composer_paste_test.dart tests/unit/chat_mention_composer_test.dart --reporter expanded` | 18 项通过 |
| `flutter test tests/unit/chat_page_test.dart --name '发送首帧显示气泡且清空输入框\|切换会话后保留各自输入草稿\|macOS 参考稿输入区\|emoji 面板把表情插入\|macOS 选择附件后输入框保持焦点\|Personal Agent' --reporter expanded` | 8 项通过 |
| `dart format --output=none --set-exit-if-changed lib/src/presentation/chat/parts/chat_composer_part.dart tests/unit/chat_page_test.dart`、`git diff --check` | 通过 |

新增布局矩阵覆盖 320、360、390、430 宽度，显示比例 1.0 / 1.3，深浅主题；检查组内顺序、尺寸与居中、加密状态和草稿、长文本撑高后的底部对齐、表情面板及无布局异常。另覆盖模式加载、读取失败及重试时位置稳定。320 宽度、最大缩放时占位文本本身可能换行，测试以单字符输入作为单行高度基线。

首次执行时本机 Xcode 许可未接受，普通 Flutter 测试的 Objective-C 构建 hook 因无法获取 SDK 路径失败。上述测试使用 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`，并以临时 `xcrun` 包装器为 hook 显式选择已安装的 Command Line Tools；没有修改系统许可或仓库工具链配置。用户随后自行阅读并接受许可，`xcrun --sdk macosx --show-sdk-path` 与 `xcodebuild -checkFirstLaunchStatus` 已正常返回。

## 本地 Debug

旧 Core 原生产物来源校验失败；已通过显式 local 模式编译当前 Core、固定 registry ANP 1.0.7 / Identity 0.2.6，生成 arm64 静态库。Rust / Dart 桥接内容哈希均为 `950127689`，本次无 API 变更，未重新生成绑定。

许可解除后，原生框架生成及来源校验通过。首次正常 `flutter run --debug -d macos` 在链接阶段暴露系统代理的 macOS SDK 配置缺项：Rust 静态库引用 `SCDynamicStore*`、`SCNetwork*` 和 `DHCPInfoGetOptionData`，Podspec 未声明 `SystemConfiguration`。已在 Core 提交 `d2687c8c` 补齐该框架及 SDK 文档，并扩展既有 Podspec 合同检查；`flutter test test/macos_podspec_contract_test.dart --reporter expanded` 在 SDK 包目录执行，1 项通过。CocoaPods 生成的 App 链接参数已包含 `-framework "SystemConfiguration"`。

使用 ignored 的 `.artifacts/dependencies/composer-local.json`（只选择当前 Core 源码）按 `scripts/flutter/build-sdk-native.sh --macos-only --macos-arch arm64 --skip-codegen-check` 重建匹配产物；原生依赖构建为优化后的本地开发产物，App 保持 Debug，不发布 SDK。`bash scripts/verify_im_core_native_artifact.sh` 来源校验通过，App 构建中间库与当前 Core 静态库逐字节一致。

`PATH=/opt/homebrew/bin:$PATH flutter run --debug -d macos` 已构建并启动正常 `lib/main.dart`。App 主程序和 Debug dylib 均为 arm64，窗口标题为 **AWikiMe (Development)**；通过原生界面树和截图确认登录页可见。Debug 进程保留运行，登录后可打开普通私聊并缩窄窗口查看分组。本次没有代用户登录、发验证码或发送业务消息；随后用户明确反馈本次移动端加密按钮调整已手动验证无问题；此反馈覆盖本次布局，不扩展为 Windows 原生代理、旧数据迁移或全量产品 E2E 验收。

App 的 `macos/Podfile.lock` 只保留 SDK Podspec 校验值更新；已撤销本机 CocoaPods 版本导致的无关工具版本戳变化。Xcode 仍报告本机 CoreDevice/CoreSimulator 组件版本警告，但没有阻止本次 macOS Debug 构建；本轮不处理 iOS 模拟器组件更新。完整本地构建与定向测试日志保留在 workspace 的 `tmp/composer-security-layout-20261023/`。

本次为共享 Flutter 展示层调整及必要的 macOS SDK 链接声明修复；没有协议、服务端或真实多客户端行为变更，未运行跨服务 System Test 或产品全量 E2E。尚无 Android/iOS 真机触控及键盘验收证据。未生成分发安装包、发布 SDK 或部署服务。
