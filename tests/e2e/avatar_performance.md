# 头像滚动基准

使用 `flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/avatar_performance_test.dart -d macos --dart-define=AVATAR_PERFORMANCE_OUTPUT=<绝对 JSON 路径>`。原生 SDK 架构必须与主机一致；仅有 arm64 SDK 时，通过独立 Xcode xcconfig 将 Profile 构建限定为 arm64，不改产品工程或构建 universal SDK。

基准使用真实 ConversationListPage、产品 Material/Cupertino 主题、AvatarBadge 和磁盘/解码缓存，1000 会话包含 200 个四人群；资料和 JPEG 传输使用确定性夹具。三轮字符/冷/热测量均滚动到底再返回。记录 Flutter FrameTiming build/raster P95 和图片请求数；热缓存请求必须为零。停止其他构建后运行，不以 Debug 数据作为性能结论。

比较主线程 build P95，同轮回退检查线为 10%，并保留原始各轮结果与绝对值。基准不替代真实后端 E2E、移动相机/HEIC、设备权限或跨设备人工验收。正常手工交付必须重新构建 `lib/main.dart`；这个 integration_test 包不能用作正常 APP。
