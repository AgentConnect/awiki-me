# Step 05：集成验证、文档同步与发布 gate

主 Plan：[../plan.md](../plan.md)
Step index：05
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-group:feauture/release-0526/group`; `awiki-cli-rs2-group:feauture/release-0526/group` |
| Started | 2026-06-14T21:34:03+08:00 |
| Completed | 2026-06-14T22:40:23+08:00 |
| Commit | `awiki-cli-rs2-group:1da1710 docs: document group mention integration gates`; `awiki-me-group:d373d48 test: add group mention e2e coverage` |
| Review evidence | 手工 Review 通过：P9 payload 仍 schema-less；App E2E 断言无 `schema`；docs 与 SDK / Daemon 行为一致；真实 E2E 使用 fresh handles 通过；真实 daemon live prompt 留后续专项 gate。 |
| Verification evidence | App analyze / mention tests / macOS build-smoke 通过；SDK / Daemon focused tests、Dart SDK payload tests、codegen、CLI release build、macOS SDK native build 通过；`mention-p9-20260614g` 远端 App+CLI group E2E success；workspace cargo live identity 失败为本地依赖未启动。 |
| Next action | Step 05 完成；后续如需完整 live prompt 证据，在 awiki-system-test / daemon live gate 中补 runtime agent 端到端用例 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：通过测试和文档证明 ANP P9 mention 从 App 输入到 Daemon prompt 的链路可用且安全。
- 用户 / 系统可见行为：群聊 mention 的 App UX、消息展示、agent 提示均有可复现验证。
- 非目标：不要求本步骤新增产品能力；不扩大到私聊 mention 或能力 selector。
- 完成标准：
  - App / SDK / Daemon focused tests 通过。
  - 至少一个跨服务或 E2E 场景验证 `@agents` 或单 agent mention。
  - 文档同步完成。
  - 最终全局 Review 完成并记录残余风险。

## 3. 设计方法

- 设计边界：`awiki-system-test` 验证跨服务行为；`awiki-me` 测 UI / mapper；`awiki-cli-rs2` 测 SDK / Daemon。
- 核心决策：测试应验证服务端不展开 selector，Daemon 在终端侧解析；不要用 mock 替代跨服务关键路径。
- 契约 / API / 数据流：App 发送 P9 payload → message-service 保留 / 投递 → App 渲染 → Daemon 解析 / prompt。
- 兼容性：普通群文本、Agent IM delegated text、control payload 不回归。
- 迁移策略：feature flag 或灰度配置可用于关闭 mention 触发，但 payload display 应保持兼容。
- 风险控制：E2EE mention 如未具备明文链路，必须明确跳过原因和后续 gate。

## 4. 实现方法

1. 在 `awiki-me` 补充 docs / testing gate，说明 mention composer、payload mapper、highlight 的测试命令。
2. 在 `awiki-cli-rs2` docs 中记录 P9 DTO / Dart SDK API / Daemon prompt policy。
3. 在 `awiki-system-test` 设计 focused scenario：
   - 建群，加入 human A、human B、runtime agent；
   - App 或 CLI 发送 `@agents` payload；
   - 验证消息 payload 没被服务端改写；
   - 验证 Daemon 对 runtime agent 生成 mention prompt；
   - 发送 `@humans`，验证不触发 agent；
   - 发送 invalid range，验证只显示文本不触发。
4. 如 message-service 增加 payload size / mention count 限制，同步 API / config docs。
5. 执行最终全局 Review，回填主 Plan 执行台账和最终证据。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/docs/testing.md` | 增加 mention App 测试 gate | 代码变更时同步。 |
| `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` | 记录 P9 mention API / payload | SDK 权威文档。 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 记录 Dart DTO / payload 兼容 | App 集成入口。 |
| `awiki-cli-rs2/crates/awiki-deamon/docs/` | 记录 mention prompt policy | Daemon 权威文档。 |
| `awiki-system-test/` | 新增或扩展 focused E2E | 跨服务验证。 |
| `message-service/docs/api/` | 如服务约束变化则更新 | 只在服务行为变化时。 |

## 6. 依赖

- 前置步骤：Step 01-04 完成。
- 外部文档或决策：是否启用 message-service v2 / daemon E2E 环境。
- 环境前提：本地或远端 test stack 可用；敏感信息必须脱敏。

## 7. 验收标准

- [x] 所有相关 unit/widget/focused Rust tests 通过或有明确 blocked 记录。
- [x] E2E 覆盖 `@agents`：`mention-p9-20260614g` 真实 awiki.info App+CLI group case success，验证 schema-less P9 payload 可从 App 发出并被 CLI 历史读回。
- [x] `@humans` 不触发 runtime agent：由 `cargo test -p awiki-deamon --locked mention` focused tests 覆盖。
- [x] invalid mention 不触发：由 `cargo test -p awiki-deamon --locked mention` focused tests 覆盖。
- [x] 相关 docs 与代码行为一致。
- [x] 最终 `git status` 在各受影响仓库清晰可解释。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

说明：本轮真实 E2E 覆盖 App/SDK/message-service/CLI group history，不覆盖 awiki.info 上真实 runtime agent live prompt；Daemon prompt、`@humans`、invalid range 和 E2EE opaque 由 focused daemon tests 覆盖，live prompt 留后续专项 gate。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| App | `cd awiki-me && dart analyze && flutter test tests/unit_test` | App 静态检查和单元 / widget 测试通过。 |
| SDK | `cd awiki-cli-rs2 && cargo test --workspace --locked` | SDK / Daemon Rust 测试通过。 |
| Codegen | `cd awiki-cli-rs2 && scripts/flutter/codegen-check.sh` | Dart / Rust bridge 生成物一致。 |
| System | `cd awiki-system-test && uv run python manage_local_test_env.py run-tests --suite message-v2 ...` | focused mention E2E 通过。 |
| Docs | `git diff --check` | 文档无格式问题。 |
| Security | 人工 Review | mention 不作为授权、不泄露 secret、不复制 target 到 metadata。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：所有实现步骤完成后、最终 commit 前。
- Review 重点：跨 repo 行为一致性、P9 互操作、服务端透明转发、Daemon 权限、安全 / 隐私、文档漂移、未提交变更。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 已记录 | 本地 `-group` worktree 默认误用旧 SDK 会触发 schema 校验；受限 / 污染 handle 会导致远端 E2E 注册失败；真实 daemon live prompt 未在 awiki.info 上跑。 |
| 已修复问题 | 已修复 / 已规避 | 用未提交 `pubspec_overrides.yaml` 指向 `awiki-cli-rs2-group` 并构建 macOS native framework 后验证；换 fresh handles `p9g14app01` / `p9g14cli01` 跑通远端 E2E；补 `GROUP-P9-001` 与文档说明。 |
| 剩余风险 | 已明确 | Daemon live prompt、selector authoritative membership、Group E2EE 明文 agent 触发留后续专项 gate。 |
| 新增或缺失测试 | 已补充 / 已记录 | 新增 App+CLI group P9 E2E slice；daemon focused tests 覆盖 @humans / invalid / E2EE opaque；未新增第三方仓库 awiki-system-test 用例，因本目标限制只修改两个 worktree。 |
| 已更新或缺失文档 | 已更新 | 更新 `awiki-me/docs/testing.md`、SDK API docs、Flutter SDK docs、本 Plan 与 Step05 ledger。 |

## 10. Commit 要求

- Commit 时机：本步骤验证、Review、文档同步完成后。
- Commit 范围：E2E tests、docs、必要的 final integration fixes。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: add group mention integration coverage`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| message-v2 / daemon E2E 环境不可用 | 环境启动失败 | 记录 logs，跑 repo focused tests | E2E gate | 标记 blocked 或用远端环境重跑。 |
| Group E2EE mention 未具备明文路径 | Daemon 只见 cipher | 明确非 E2EE MVP 已通过 | E2EE 场景 | 记录 follow-up，不阻塞 base group mention。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 05 | 初始设计 | `../plan.md#16-plan-变更记录` |

## 13. 实际验证记录

- `cd awiki-me-group && PATH=/Users/cs/development/flutter/bin:$PATH dart analyze`：No issues found。
- `cd awiki-me-group && PATH=/Users/cs/development/flutter/bin:$PATH flutter test tests/unit_test --name mention`：14 passed。
- `cd awiki-me-group && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/desktop_cli_peer_group_test.dart -d macos --dart-define=AWIKI_E2E=false`：macOS build 通过，All tests skipped。
- `cd awiki-cli-rs2-group && cargo test -p im-core --locked mention`：5 passed。
- `cd awiki-cli-rs2-group && cargo test -p awiki-deamon --locked mention`：4 passed。
- `cd awiki-cli-rs2-group/packages/awiki_im_core && flutter test test/message_payload_api_test.dart`：9 passed。
- `cd awiki-cli-rs2-group && scripts/flutter/codegen-check.sh`：Done。
- `cd awiki-cli-rs2-group && cargo build -p awiki-cli --bin awiki-cli --release --locked`：Done。
- `cd awiki-cli-rs2-group && scripts/flutter/build-apple.sh --macos`：Done，生成本地 macOS `AwikiImCore.xcframework` 用于 worktree E2E。
- 真实远端 E2E：`cd awiki-me-group && DEV_OTP_PHONE=... DEV_OTP_CODE=... AWIKI_CLI_BIN=../awiki-cli-rs2-group/target/release/awiki-cli dart run tool/desktop_cli_peer_e2e_runner.dart --platform macos --case group --service-base-url https://awiki.info --did-domain awiki.info --app-handle p9g14app01 --cli-handle p9g14cli01 --run-id mention-p9-20260614g`：success，2m10s。
- `cd awiki-cli-rs2-group && cargo test --workspace --locked`：运行到 `awiki-cli --test identity_live_contract` 时 11 个 live tests 因本地 `127.0.0.1:* /user-service/did-auth/rpc` transport_unavailable 失败，非 P9 回归；focused tests 已覆盖本功能。
- `git diff --check`：两仓库通过。

## 14. 风险、回滚与后续文档

- 风险：跨 repo 变更多，E2E 环境不稳定。
- 回滚 / 回退：保留 App 显示解析，关闭发送和 Daemon 触发 feature flag；普通消息链路不受影响。
- 后续文档：必要时提升到 `awiki-harness/features/` 形成跨仓库 feature map。
