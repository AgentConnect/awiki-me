# Step 07：Mobile 双设备 E2E

主 Plan：[../plan.md](../plan.md)  
Step index：07  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待执行时记录 |
| Started | 待记录 |
| Completed | 待记录 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 建立 iOS/Android 两设备登录和消息互通 E2E |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：让移动端真实两设备 E2E 覆盖登录、发送、接收和基础聊天回归。
- 用户 / 系统可见行为：后续移动端新功能不会破坏基本账号和消息互通。
- 非目标：不把移动真实设备 E2E 放入普通 PR required gate，不要求覆盖所有平台 UI 细节。
- 完成标准：`mobile_e2e_runner.dart` 能用 `mobile.local.yaml` 驱动两台 iOS 或 Android 设备完成双向消息 smoke，并输出脱敏报告。

## 3. 设计方法

- 设计边界：移动 E2E 使用 Maestro flows 和 mobile runner；复杂协议验证仍由 SDK/system tests 覆盖。
- 核心决策：先覆盖 A 登录发送给 B、B 接收，再反向发送；后续再加 profile/settings/notification。
- 契约 / API / 数据流：两个设备使用不同账号和 handle，同一套非生产服务。
- 兼容性：iOS 和 Android 使用同一 runner/config schema，平台字段决定设备准备方式。
- 迁移策略：复用现有 `login.yaml`、`open_chat_and_send.yaml`、`open_chat_and_wait.yaml`，先稳定 P0。
- 风险控制：设备池不稳定时不阻塞 PR，只在 nightly/release 或 manual run。

## 4. 实现方法

1. 准备 `mobile.local.yaml`：
   - iOS: 两个 simulator name 或 UDID。
   - Android: 两个 AVD name 或 device serial。
   - 两个非生产账号和 handle。
2. 扩展 runner：
   - 安装/启动 App。
   - reset app data 可配置。
   - 注入 service URLs。
   - 调用 Maestro flows。
3. 执行 flow：
   - Device A 登录。
   - Device B 登录。
   - A 打开 chat 并发送 runId 消息。
   - B 等待并断言收到。
   - B 反向发送，A 等待并断言收到。
4. 输出报告：
   - 设备信息。
   - runId。
   - flow pass/fail/skipped。
   - screenshot/log 路径脱敏。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/e2e_test/harness/mobile_e2e_runner.dart` | 后续扩展两设备真实 run | 已有 dry-run |
| `test-awiki-me/tests/e2e_test/mobile/maestro/` | 后续维护 Maestro flows | 平台共享 |
| `test-awiki-me/tests/e2e_test/configs/mobile.example.yaml` | 后续补字段说明 | 只提交 example |
| `test-awiki-me/tests/e2e_test/configs/mobile.local.yaml` | 本地运行配置 | 不提交 |
| `test-awiki-me/.e2e/mobile/` | 运行时报告和状态 | 不提交 |

## 6. 依赖

- 前置步骤：Step 03。
- 外部文档或决策：设备池、账号池、nightly runner 类型。
- 环境前提：iOS simulator/Xcode 或 Android emulator/SDK，Maestro 可用，后端可达。

## 7. 验收标准

- [ ] dry-run 不需要设备和真实后端。
- [ ] real run 使用两套账号和两个独立设备/模拟器。
- [ ] A->B 和 B->A 均有唯一 runId 消息断言。
- [ ] device logs、screenshots、reports 不泄漏 OTP/JWT/private key。
- [ ] 设备不可用时明确 skipped/blocker，不影响 PR required gate。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Mobile dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | 设备和 flow 计划可生成。 |
| iOS real | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.local.yaml` | iOS 两设备 run 通过或记录 host 不支持。 |
| Android real | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.local.yaml` | Android 两设备 run 通过或记录 host 不支持。 |
| Unit | `cd test-awiki-me && flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` | runner parser 和 command planning 通过。 |
| Secret | 扫描 `.e2e/mobile` report | 无真实 secret。 |

## 9. Review 环节

- Review 时机：mobile runner/flow/config 调整完成后、commit 前。
- Review 重点：设备隔离、账号隔离、flow 稳定性、失败证据、Maestro selector、日志脱敏、是否误入 PR required gate。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待记录 |  |
| 已修复问题 | 待记录 |  |
| 剩余风险 | 待记录 |  |
| 新增或缺失测试 | 待记录 |  |
| 已更新或缺失文档 | 待记录 |  |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：mobile runner、Maestro flows、example config、docs 的聚焦修改。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: add mobile two device e2e`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无设备池 | runner/maestro 报错 | 保留 dry-run 和 desktop E2E | Mobile real E2E | 标 nightly/manual blocked |
| Maestro selector 不稳定 | flow 失败截图 | 补稳定 semantics 或拆分 flow | 当前步骤 | 先保留最小登录/消息 flow |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：移动 E2E flake 高于桌面 E2E。
- 回滚 / 回退：将 mobile real run 保持 manual/nightly，不纳入 required gate。
- 后续文档：Step 08 记录移动 E2E 的运行频率和失败处理策略。
