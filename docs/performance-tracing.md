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
| `app_refresh.*` | 登录态后台刷新本地会话、profile、agents、friends、groups 以及 product store warm-up | 判断启动后列表慢是否被后台刷新抢资源；`app_refresh.conversation_fast_local` 应先完成，其他数据并发补齐 |
| `conversation_list.refresh_fast_local*` / `conversation_list.refresh_enrich*` | 会话列表 provider 的本地 summary 首屏刷新与后台 enrichment merge/badge | 判断首屏 state 更新是否只等本地 summary，Agent/overlay 是否在后台补齐 |
| `conversation_service.fast_local*` / `conversation_service.enrich*` | im-core summary list、Agent 投影、overlay、过滤排序 | 判断会话列表业务层慢点；`fast_local` 不应等待远端 Agent inventory |
| `product_store.*` | product overlay SQLite warm-up、路径解析、legacy migration、open database、query/decode | 判断 overlay DB 首次 open/migration 是否仍挤进首屏路径 |
| `im_core_conversations.*` | Dart -> im-core native 会话查询边界 | 判断是否卡在 native/SQLite/SDK 查询 |
| `agents.load*` | Agent 清单与 daemon status 本地投影 | 判断 Agent 投影是否拖慢会话列表 |
| `chat.open_conversation` | 点击进入会话 | 进入会话起点 |
| `chat.history.*` / `im_core_messages.history*` | 消息历史拉取、Dart 映射、merge/sort | 判断消息列表 5-8 秒延迟卡在哪一层 |
| `chat.mark_read*` | 打开未读会话后的本地清未读与已读同步 | 判断本地清 unread 和 SDK thread mark-read ack 是否慢 |
| `chat_page.build.*` / `conversation_list_page.*build.*` | Flutter build 准备阶段 | 判断是否是 UI 构建/重算慢 |
| `frame.slow` | Flutter 慢帧 build/raster 时间 | 判断是否出现明显 UI jank |

## 如何解读

1. 如果 `im_core_conversations.native_list` 或 `im_core_messages.history_native` 很慢，优先怀疑 im-core native、SQLite/WAL、本地库版本或网络历史读取。
2. 如果 `conversation_service.fast_local` 很快但 `conversation_service.enrich`、`conversation_service.agent_projection` 或 `agents.load.*` 很慢，说明首屏已经脱离远端 Agent inventory，慢点在后台补齐链路。
3. 如果 `product_store.legacy_migration` 或 `product_store.open_database` 很慢，优先看首次 DB open、旧库迁移和 WAL/SHM 拷贝；这些应通过 `app_refresh.product_store_warm_up` 后台预热，不能阻塞 `conversation_fast_local`。
4. 如果 `conversation_service.filter_sort`、`conversation_list.refresh_fast_local.merge`、`conversation_list.refresh_enrich.merge` 或 `chat.messages.sort` 很慢，优先看 Dart 侧列表规模、O(n²) 匹配和排序。
5. 如果 `chat.mark_read` 很慢，优先看 `im_core_conversations.mark_read.native` 的
   `local_candidates`、`remote_ack`、`partial` 和 `warnings`；旧的
   `im_core_conversations.mark_read.history_page` 不应再出现，出现则说明回归到了
   history 分页找 unread ids。
6. 如果 `frame.slow` 很多而数据层日志不慢，说明主要是 Flutter build/raster 或大量 widget 重建。

## 当前性能门禁

- 启动或恢复时，应先看到 `app_refresh.conversation_fast_local` 与 `conversation_list.refresh_fast_local`，再看到 `conversation_list.refresh_enrich`、`app_refresh.agents`、`app_refresh.friends` 和 `app_refresh.groups`。
- `conversation_service.fast_local` 不应等待 `conversation_service.agent_projection.list_agents`；如果二者耗时同步增长，说明会话首屏又被 Agent RPC 绑定。
- `product_store.open_database` / `product_store.legacy_migration` 可在后台 warm-up 中出现，但不应成为 `conversation_list.refresh_fast_local` 的直接子链路。

## 隐私说明

日志只记录耗时、数量、布尔值和 thread/DID 的短 hash，不应包含 token、私钥、消息正文或完整 DID。向协作者贴日志前仍建议检查并删除任何异常敏感内容。
