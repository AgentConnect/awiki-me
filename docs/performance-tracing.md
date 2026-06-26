# AWiki Me 性能追踪日志

AWiki Me 支持一个默认关闭的性能诊断开关，用来定位启动后会话列表慢、进入会话后消息列表加载慢、CPU 短时间升高等问题。

## 开启方式

```bash
cd awiki-me
flutter run -d macos --dart-define=AWIKI_PERF_LOG=true
```

可选：调整慢帧阈值，默认 24ms。

```bash
flutter run -d macos \
  --dart-define=AWIKI_PERF_LOG=true \
  --dart-define=AWIKI_PERF_SLOW_FRAME_MS=16
```

日志前缀统一为：

```text
[awiki_me][perf]
```

## 重点事件

| 事件前缀 | 含义 | 用途 |
|---|---|---|
| `main.*` / `bootstrap.*` | App 启动、路径解析、bootstrap 创建 | 判断打开软件初始等待是否卡在 App 初始化 |
| `app_refresh.*` | 登录态后台刷新 profile / conversations / agents / friends / groups | 判断启动后列表慢是否被串行刷新拖慢 |
| `conversation_list.refresh*` | 会话列表 provider 刷新、merge、本地 badge | 判断列表 state 更新是否慢 |
| `conversation_service.*` | im-core list、Agent 投影、overlay、过滤排序 | 判断会话列表业务层慢点 |
| `im_core_conversations.*` | Dart -> im-core native 会话查询边界 | 判断是否卡在 native/SQLite/SDK 查询 |
| `agents.load*` | Agent 清单与 daemon status 本地投影 | 判断 Agent 投影是否拖慢会话列表 |
| `chat.open_conversation` | 点击进入会话 | 进入会话起点 |
| `chat.history.*` / `im_core_messages.history*` | 消息历史拉取、Dart 映射、merge/sort | 判断消息列表 5-8 秒延迟卡在哪一层 |
| `chat.mark_read*` | 打开未读会话后的已读同步 | 判断 mark read 是否额外分页拉历史导致 CPU/IO |
| `chat_page.build.*` / `conversation_list_page.*build.*` | Flutter build 准备阶段 | 判断是否是 UI 构建/重算慢 |
| `frame.slow` | Flutter 慢帧 build/raster 时间 | 判断是否出现明显 UI jank |

## 如何解读

1. 如果 `im_core_conversations.native_list` 或 `im_core_messages.history_native` 很慢，优先怀疑 im-core native、SQLite/WAL、本地库版本或网络历史读取。
2. 如果 `conversation_service.agent_projection` 或 `agents.load.*` 很慢，优先怀疑 Agent inventory / daemon status 投影造成启动列表慢。
3. 如果 `conversation_service.filter_sort`、`conversation_list.refresh.merge` 或 `chat.messages.sort` 很慢，优先看 Dart 侧列表规模、O(n²) 匹配和排序。
4. 如果 `chat.mark_read` 很慢，说明进入未读会话时额外 mark-read 流程可能在分页拉历史。
5. 如果 `frame.slow` 很多而数据层日志不慢，说明主要是 Flutter build/raster 或大量 widget 重建。

## 隐私说明

日志只记录耗时、数量、布尔值和 thread/DID 的短 hash，不应包含 token、私钥、消息正文或完整 DID。向协作者贴日志前仍建议检查并删除任何异常敏感内容。
