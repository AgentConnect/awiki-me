# Step 03：Desktop CLI peer 账号与服务编排

主 Plan：[../plan.md](../plan.md)  
Step index：03  
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
| Next action | 在用户确认执行后，设计并实现 Desktop E2E runner 的账号 / 服务配置层 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：提供一个 macOS / Linux 共用、可重复、可清理、可脱敏的 CLI peer 准备流程。
- 用户 / 系统可见行为：runner 能构建或定位 `awiki-cli`，创建隔离 workspace，读取非生产测试 OTP，注册或恢复 CLI peer 身份，并确认 CLI 可以访问同一测试服务。
- 非目标：不在本步骤驱动 Flutter UI，不验证 App 收发消息，不把 `.env` 或真实账号状态提交到 repo。
- 完成标准：CLI peer 在隔离 workspace 中完成 `id current` / `id status` / `msg inbox --limit 1 --format json` 的可解析检查。

## 3. 设计方法

- 设计边界：CLI peer 是真实第二客户端，但它的状态和配置必须完全隔离于开发者默认 `~/.awiki-cli/`。
- 核心决策：从 `user-service/.env` 或调用环境读取 key 名；runner 不记录值。测试账号先支持 register / recover 两种路径，以适配 handle 是否已存在。
- 契约 / API / 数据流：CLI 只通过 `awiki-cli` public command surface 操作，不直接读写 CLI 内部 SQLite 或身份私钥。
- 兼容性：保留既有 mobile `tool/e2e_runner.dart`，Desktop CLI peer runner 可以是新文件，避免把 mobile Maestro 逻辑混入 desktop。
- 迁移策略：无用户数据迁移；本地 `.e2e/` 可删除重建。
- 风险控制：所有 child process stdout / stderr 进入 report 前脱敏，至少过滤 OTP、JWT、private key、workspace secret、完整 `.env` 行。

## 4. 实现方法

1. 定义 Desktop CLI peer runner 的输入：

   - `AWIKI_CLI_BIN`：已构建的 `awiki-cli` 二进制，或 runner 自动使用 `cargo build -p awiki-cli --bin awiki-cli --release --locked`；
   - `--platform macos|linux`：选择 Flutter device 和是否使用 `xvfb-run -a`；
   - `DEV_OTP_PHONE` / `DEV_OTP_CODE`：从调用环境读取；
   - `AWIKI_SERVICE_BASE_URL` / `AWIKI_BASE_URL`；
   - `AWIKI_DID_DOMAIN`；
   - 可选 `AWIKI_ANP_SERVICE_URL` / `AWIKI_ANP_SERVICE_DID`；
   - `AWIKI_E2E_APP_HANDLE` / `AWIKI_E2E_CLI_HANDLE`，未传时由 runner 生成唯一 handle。

2. 初始化 CLI peer workspace：

   ```bash
   export AWIKI_CLI_WORKSPACE_HOME_DIR=".e2e/desktop-cli-peer/<run-id>/cli-peer"
   awiki-cli init
   ```

3. 写入或更新 CLI config：

   - 首选使用 CLI 已有命令，例如 `awiki-cli config set --did-domain <domain>`；
   - 当前 `config.set` 只明确支持 `--did-domain`，`service_base_url` 等可由 runner 在 `config.yaml` 中写入，但必须使用结构化 YAML 处理，不能用脆弱字符串替换；
   - 写入后运行 `awiki-cli config show --format json` 或等价命令验证解析结果。

4. 注册或恢复 CLI peer 身份：

   ```bash
   awiki-cli id recover --handle "$AWIKI_E2E_CLI_HANDLE" --phone "$DEV_OTP_PHONE" --otp "$DEV_OTP_CODE" --format json
   ```

   如果 recover 返回 handle 不存在或等价错误，再尝试：

   ```bash
   awiki-cli id register --handle "$AWIKI_E2E_CLI_HANDLE" --phone "$DEV_OTP_PHONE" --otp "$DEV_OTP_CODE" --format json
   ```

   最终顺序需要以 User Service 测试账号策略验证后固化。如果同一测试手机号不能支持两个 handle，必须改为账号池。

5. CLI peer ready check：

   ```bash
   awiki-cli id current --format json
   awiki-cli id status --format json
   awiki-cli msg inbox --limit 1 --format json
   ```

6. 生成脱敏 report：

   - 记录 run id、handles、service base URL、DID domain、命令退出码、耗时；
   - 不记录 OTP、JWT、私钥、完整 workspace 内容。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | 新增 Desktop CLI peer runner | 与 mobile Maestro runner 分离，支持 `macos` / `linux` |
| `test-awiki-me/test/tool/` | 新增 runner dry-run / config parsing tests | 不需要真实服务 |
| `test-awiki-me/awiki_e2e.example.yaml` 或新配置样例 | 可选扩展 Linux desktop 配置 | 不写真实账号值 |
| `test-awiki-me/.gitignore` | 确认 `.e2e/`、local config 已忽略 | 当前 `.e2e/` 已忽略 |
| `awiki-cli-rs2/config.template.yaml` | 不一定修改 | 只在 CLI 需要新配置能力时更新 |
| `user-service/.env` | 不修改、不提交 | 只作为本地输入来源 |

## 6. 依赖

- 前置步骤：Step 02 的 SDK 配置结论；完整 E2E 依赖 Step 01-02，但本步骤 runner dry-run 可独立完成。macOS 可先复用已有 native SDK，Linux 完整执行依赖 Step 02。
- 外部文档或决策：确认 `user-service/.env` 测试 OTP 是否允许两个 handle；确认测试环境 service base URL / DID domain。
- 环境前提：`awiki-cli-rs2` 可构建 CLI，非生产服务可访问。

## 7. 验收标准

- [ ] runner 不读取或污染默认 `~/.awiki-cli/`。
- [ ] runner 支持 dry-run，dry-run 不执行有副作用命令。
- [ ] runner 能从环境变量读取 `DEV_OTP_PHONE` / `DEV_OTP_CODE`，日志不输出实际值。
- [ ] CLI config 指向与 App 相同的非生产 service base URL / DID domain。
- [ ] CLI peer `id current` / `id status` 成功。
- [ ] CLI peer `msg inbox --limit 1 --format json` 返回可解析 JSON 或明确的空 inbox 成功响应。
- [ ] 同一测试 OTP 是否支持 App / CLI 两个身份已经验证或记录为 blocker。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Runner unit | `cd test-awiki-me && flutter test test/tool` | dry-run、config parse、secret redaction tests 通过 |
| CLI build | `cd awiki-cli-rs2 && cargo build -p awiki-cli --bin awiki-cli --release --locked` | 生成 CLI binary |
| CLI workspace | `AWIKI_CLI_WORKSPACE_HOME_DIR=.e2e/desktop-cli-peer/<run-id>/cli-peer awiki-cli init` | 隔离 workspace 初始化成功 |
| CLI identity | `awiki-cli id current --format json` / `awiki-cli id status --format json` | 当前身份可解析且 handle 匹配 |
| CLI inbox | `awiki-cli msg inbox --limit 1 --format json` | 命令成功，输出可解析 |
| Secret scan | 执行项目约定的 secret scan，覆盖 OTP 赋值、JWT、私钥和完整 `.env` 行 | repo docs / tracked files 不包含敏感值；`.e2e/` 只本地检查 |
| Diff hygiene | `cd test-awiki-me && git diff --check` | 无 whitespace / patch 格式问题 |

真实 CLI identity / inbox 验证依赖后端和测试账号；如果不可运行，必须记录环境缺口和替代 dry-run 证据。

## 9. Review 环节

- Review 时机：runner、dry-run tests、CLI ready check 完成后，commit 前。
- Review 重点：secret redaction、workspace isolation、YAML config 写入是否结构化、账号冲突处理、失败日志是否可诊断但不泄密。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 执行时填写 | - |
| 已修复问题 | 执行时填写 | - |
| 剩余风险 | 执行时填写 | 账号池 / OTP 限制需明确 |
| 新增或缺失测试 | 执行时填写 | runner dry-run 至少要覆盖 |
| 已更新或缺失文档 | 执行时填写 | docs/testing 可在 Step 05 汇总 |

## 10. Commit 要求

- Commit 时机：runner、验证、Review 都完成后。
- Commit 范围：`test-awiki-me/tool/`、`test-awiki-me/test/tool/`、必要 sample config / docs。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status --short --branch`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: add desktop cli peer e2e runner`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 测试 OTP 不允许两个 handle | register / recover 第二身份失败 | 尝试唯一 handle、已存在 handle recover | Step 03 / Step 04 | 请求第二测试账号或服务端账号池 |
| CLI 无法配置 service base URL | `config set` 只支持 did-domain | 结构化写入 `config.yaml`；必要时扩展 CLI config command | Step 03 | 如果扩展 CLI，需在 `awiki-cli-rs2` 新增独立步骤或更新本 Plan |
| 后端不可访问 | CLI 命令网络错误 | 检查 service URL、VPN、local system-test env | 当前步骤 | 记录为环境 blocker，保留 dry-run 验证 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 03 | 初始方案拆分 | [../plan.md#20-plan-变更记录](../plan.md#20-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：账号策略是完整 E2E 的主要不确定点；同一测试 OTP 不等于一定能准备两个身份。
- 回滚 / 回退：移除 Linux CLI peer runner 和 sample config；保留 mobile E2E runner 不受影响。
- 后续文档：Step 05 记录如何在本地 / CI 配置 secret 和账号池。
