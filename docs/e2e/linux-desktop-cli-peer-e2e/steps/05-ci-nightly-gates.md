# Step 05：CI / nightly gate 与文档收口

主 Plan：[../plan.md](../plan.md)  
Step index：05  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | `feature/test-awiki-me` |
| Started | - |
| Completed | - |
| Commit | - |
| Review evidence | - |
| Verification evidence | - |
| Next action | 在 Step 01-04 完成后，更新 CI gate 和测试文档 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：把 Linux Desktop smoke、Linux native smoke 和真实 App+CLI peer E2E 放到合适的本地 / CI / nightly gate。
- 用户 / 系统可见行为：普通 PR 仍然有稳定 quick gate；真实后端 E2E 有明确 manual / nightly 命令和 secret 配置要求。
- 非目标：不把真实后端账号依赖直接变成所有 PR 的硬阻塞，不把 `.e2e/` 报告上传为未脱敏 artifact。
- 完成标准：文档与 CI 配置一致，开发者知道哪些测试已覆盖、哪些测试需要 secret / backend / nightly。

## 3. 设计方法

- 设计边界：区分快速、确定性的代码 gate 和依赖后端账号的 E2E gate。
- 核心决策：PR quick gate 只跑 `flutter test`、analyze、mobile runner dry-run、Linux app smoke / native smoke；真实 App+CLI peer E2E 放 nightly、manual 或 release gate。
- 契约 / API / 数据流：CI secret 只以环境变量注入；日志和 artifacts 脱敏。
- 兼容性：保留现有 `docs/testing.md` 的 mobile E2E 说明，新增 Linux Desktop + CLI peer 链接和命令。
- 迁移策略：无数据迁移。
- 风险控制：真实 E2E job 要有显式条件，例如只在 nightly schedule、manual dispatch、或 secrets 存在时运行。

## 4. 实现方法

1. 更新 `test-awiki-me/docs/testing.md`：

   - 说明 Linux Desktop runner 已支持后，`app_smoke_test.dart` 能测试哪些内容；
   - 说明 Linux native SDK smoke 覆盖真实 `AwikiImCore.open`；
   - 链接本 Plan；
   - 明确 App+CLI peer E2E 的运行条件和非覆盖范围。

2. 更新 CI workflow：

   - PR quick gate：

     ```bash
     flutter pub get
     dart analyze
     flutter test
     dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run
     xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
     ```

   - 如果 Step 02 已稳定，PR 或 nightly 可加入：

     ```bash
     xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
     ```

   - Full E2E nightly / manual：

     ```bash
     dart run tool/linux_cli_peer_e2e_runner.dart --config <local-or-ci-config>
     ```

3. 配置 secrets：

   - `DEV_OTP_PHONE`；
   - `DEV_OTP_CODE`；
   - `AWIKI_SERVICE_BASE_URL`；
   - `AWIKI_DID_DOMAIN`；
   - 可选 `AWIKI_ANP_SERVICE_URL` / `AWIKI_ANP_SERVICE_DID`。

4. artifact / report 策略：

   - 上传前脱敏；
   - 默认不上传 CLI workspace、App local state、SQLite、identity files；
   - 只保留 timings、command categories、exit codes、sanitized summaries。

5. 更新本 Plan 执行台账和最终全局 Review。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/docs/testing.md` | 更新 Linux Desktop / CLI peer E2E 文档 | 当前文档已有 Linux future note |
| `test-awiki-me/.github/workflows/` | 可选新增 / 更新 CI jobs | 只在执行阶段改 |
| `test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/plan.md` | 回填执行台账、最终 Review | 本 Plan 是执行事实来源 |
| `test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/steps/*.md` | 回填每步状态 | 每步完成后更新 |

## 6. 依赖

- 前置步骤：Step 01-04。
- 外部文档或决策：CI runner 是否允许安装 Linux desktop deps；nightly secrets 是否可配置。
- 环境前提：PR runner 有 Flutter Linux desktop deps 或 workflow 能安装；nightly runner 有后端访问权限。

## 7. 验收标准

- [ ] `docs/testing.md` 清楚说明 Linux smoke、native smoke、full E2E 的覆盖范围和命令。
- [ ] 本 Plan 链接可从 `docs/testing.md` 找到。
- [ ] PR quick gate 不依赖真实 OTP 和后端账号状态。
- [ ] full E2E gate 只在 secrets 存在且 job 条件满足时运行。
- [ ] CI artifacts 不包含 secret、本地身份、JWT、私钥或 `.e2e/` 原始 workspace。
- [ ] 所有步骤执行台账、Review 证据、验证证据已回填。
- [ ] 最终全局 Review 已完成。
- [ ] 本步骤在完成后已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Docs path | `cd test-awiki-me && test -f docs/e2e/linux-desktop-cli-peer-e2e/plan.md` | Plan 文件存在 |
| Docs link | `cd test-awiki-me && rg -n "linux-desktop-cli-peer-e2e" docs/testing.md docs/e2e/linux-desktop-cli-peer-e2e/plan.md` | testing doc 链接 Plan |
| Quick gate | `cd test-awiki-me && dart analyze && flutter test` | App 基础 gate 通过 |
| Mobile dry-run | `cd test-awiki-me && dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run` | 既有 mobile E2E runner dry-run 不回归 |
| Linux smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | desktop smoke 通过 |
| Native smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | SDK native smoke 通过 |
| Full E2E | `cd test-awiki-me && dart run tool/linux_cli_peer_e2e_runner.dart ...` | nightly / manual 条件下双向消息通过 |
| Secret scan | 执行项目约定的 secret scan，覆盖本机绝对路径、OTP 赋值、JWT 和私钥 | 无本机绝对路径或敏感值 |
| Diff hygiene | `cd test-awiki-me && git diff --check` | 无 whitespace / patch 格式问题 |

如果 CI 环境尚未具备 Linux desktop deps，则 workflow 变更不能标记为 required；必须在文档中记录 bootstrap 条件。

## 9. Review 环节

- Review 时机：docs、CI、最终验证完成后，commit 前。
- Review 重点：gate 分层是否合理、真实 E2E 是否条件化、secret 是否安全、docs 是否与实际命令一致、Plan 台账是否完整。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 执行时填写 | - |
| 已修复问题 | 执行时填写 | - |
| 剩余风险 | 执行时填写 | 例如 nightly runner 可用性 |
| 新增或缺失测试 | 执行时填写 | gate 文档需匹配实际 |
| 已更新或缺失文档 | 执行时填写 | 本步骤核心是文档收口 |

## 10. Commit 要求

- Commit 时机：docs / CI、验证、Review 都完成后。
- Commit 范围：`test-awiki-me/docs/testing.md`、CI workflow、本 Plan 台账和 step 状态。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status --short --branch`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`ci: gate linux desktop e2e`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| CI runner 没有 Linux desktop deps | workflow apt install 或 `flutter doctor` 失败 | 增加 apt deps；使用 self-hosted runner | CI gate | 保持 local/manual 文档，不设 required |
| Nightly secrets 未配置 | job 条件跳过或 secret missing | 文档记录 secret names | full E2E | 不阻塞 PR quick gate |
| Full E2E flake | 多次 nightly timeout | 增强 diagnostics、polling、账号池 | nightly / release | 保持非 required，直到稳定 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 05 | 初始方案拆分 | [../plan.md#20-plan-变更记录](../plan.md#20-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：把真实后端 E2E 放入 PR required gate 会导致无关 PR 被账号 / 服务波动阻塞。
- 回滚 / 回退：保留 docs 和 local command，关闭 CI full E2E job 或改为 manual dispatch。
- 后续文档：若 Linux E2E 成为 AWiki 标准测试入口，再同步 `awiki-harness/context/30-tools-env.md` 和 `awiki-harness/context/40-verification.md`。
