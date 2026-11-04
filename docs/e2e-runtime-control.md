# 桌面 E2E 运行时选择与构建复用

2026-11-04 实施。当前交付为代码、单元测试和静态检查；没有启动客户端 E2E、真实后端测试、整批客户端构建或性能对照。Windows 是本次验证平台。

## 构建与执行的边界

产物名称继续作为 runner/profile 的逻辑选择器，旧 case ID、suite、业务断言和资源处理保持不变。多个名称现在可以指向相同 target、bundle ID 和 Dart defines，从校验后的内容缓存复用同一程序：

| 逻辑选择器 | 共用构建身份 | 运行时选择 |
|---|---|---|
| recovery-main、recovery-crash-a/b、recovery-fresh-restart、recovery-registration-resume-a/b | recovery.main | 普通、崩溃边界、重启、注册续办阶段 |
| identity-deletion-a/b | identity.deletion.main | 删除和续办阶段 |
| restart-a/b/c | restart.main / desktop_cli_peer_restart_test.dart | 重启前、重启后、凭据删除后 |
| admin、joiner | 分别保留原生身份 | 角色由运行计划选择；原生单实例/凭据隔离继续成立 |

原 Windows full 活动清单的 27 种构建定义收敛为 19 种。该数字来自定义去重，不代表已完成新构建或已经测得提速比例。未将所有测试入口合并；不同身份仍有必要时保留。

Windows/macOS 的显示身份由 bundle ID 稳定派生，不再因产物别名而改变；编译缓存合同版本已更新。target、产品源码、传递测试依赖、SDK、锁文件、路径依赖和工具链变化继续使缓存失效。没有删除 native provenance 校验。

## 私有运行计划

owning runner 为每次执行生成新的私有 `invocations/<nonce>.json`，通过 `AWIKI_E2E_INVOCATION_PATH` 和 `AWIKI_E2E_INVOCATION_DIGEST` 绑定。不要手工修改报告或复用旧 invocation。

`tests/e2e/runtime_control/invocation.dart` 是实际 schema/校验入口。字段包括版本、artifact、run ID、attempt、唯一 invocation ID、scenario、platform、case IDs、artifact SHA-256、phase、role、interruption 和期限。列表不可变，未知字段、错误模式、错误平台、case/run/scenario 不匹配、摘要变化、过期或非私有文件均拒绝。

runner 在写计划前，校验 artifact 的 consumer suite 与当前 case 范围；执行前继续验证原 manifest、来源、编译指纹和实际产物 hash。运行计划摘要独立于 compile key，phase/role/故障选择不会隐式改变程序。

同一逻辑设备跨阶段保持原状态根和 secret service。不同设备保持不同原生身份和私有状态目录。新构建不是旧未完成运行的续办凭据，不直接用新产物打开旧运行以伪造恢复证明。

兼容诊断路径 `AWIKI_E2E_USE_FLUTTER_TEST=1` 仍可使用原先独立 Flutter test target/编译参数；本次优化的默认 prepared executable 路径不再靠这些阶段参数重编。专用 App-pair 入口也保留旧编译角色作为显式诊断回退，正常 prepared 路径读取受保护计划。

## 故障控制与证据

业务层仅保留 `e2e_fault_hooks.dart` 的最小接口。测试入口按所选故障阶段安装控制器；未配置的检查点不调用控制器，正常路径不读文件、不轮询、不增加异步等待。正式产品入口不导入 controller 或运行计划解析器。

原有语义保持区分：恢复边界停止后续动作与身份删除后的 `StateError` 不是 OS 强杀。现有 full 不自动切换为新强杀方式，不新增/改记 case 的通过结果。

需要精确外部终止时，测试驱动可创建带 `interruption` 的 `E2eInvocation`，选择与阶段相符的固定检查点，并将同一对象传给 `runPreparedIntegrationExecutable(expectedInterruption: ...)`。owning runner 的 `_executePreparedIntegration(interruption: ...)` 也提供对应内部入口。当前只允许 Windows；其他平台明确拒绝，不能声称已有同等进程归属验证。

程序在实际检查点原子写入私有 checkpoint 并暂停；runner 验证 invocation/计划摘要/固定检查点/序号/拥有的 PID，确认进程仍运行且尚无 completion 后，才强制结束该进程树并确认退出。控制器失联时受运行计划期限和 runner 原预算双重限制。

中断返回 `terminatedAfterCheckpoint=true`、`terminatedAfterCompletion=false`。runner 写 `interrupted_not_passed` 中间回执；它不替代 case attestation。若要新增真实强杀恢复用例，须明确准备其持久化交接、重新启动及最终业务断言，不把旧异常用例的阶段结束标记当作强杀证明。本次未启动这些真实业务测试。

## Release 隔离

全局故障钩子只在 `!kReleaseMode && const bool.fromEnvironment('AWIKI_E2E')` 时允许安装。恢复和身份删除的两个故障入口都经过此屏障；Release 即使误传原故障参数也不能激活控制器。

正式 Windows/Unix 打包脚本在构建前调用 `tool/verify_release_test_isolation.dart`，拒绝测试环境、测试入口及编码 `DART_DEFINES` 中的 E2E/故障参数。正常来源元数据和租户参数仍接受。此检查不负责发布，也不启动任何测试。

本次已验证源码屏障与相关单元合同，未构建/检查正式 Release 二进制，不声称已经取得二进制裁剪证据。

## 增量构建和诊断

- Windows 成功构建后保留受控构建槽；兼容标记相同时保留 `.dart_tool`、原生缓存和生成配置。
- 兼容标记绑定工具链/依赖/SDK/原生身份等输入；不一致时按原受控快照边界刷新。源码变更仍进入真实编译指纹和构建，不通过缓存跳过。
- 依 Git source inventory 精确移除已删除源码；内容配置后字节相同时恢复原 mtime，减少仅复制导致的失效。目录/链接逃逸拒绝。
- pub 和 Flutter 构建输出实时脱敏写入工作根的 `pub-get-output.jsonl`、`flutter-build-output.jsonl`，进度文件继续记录阶段与耗时；外层终止也保留已经落盘的输出。
- 输出日志及内存尾部有界，保留原始失败，进程树清理异常不覆盖首个错误；未扩大原 12 分钟外层准备期限。
- 单项失败后，仍通过原 owner 准备入口重试；其余同源且 hash 正确的产物命中内容缓存。必须重新通过 owning full 聚合校验，不能直接编辑旧 failed report。

验证命令、结果与开发完成边界见 [执行记录](../../awiki-plan/20261104-desktop-e2e-runtime-control/execution.md)。没有实际重新计时前，不给出冷构建或全量提速百分比。
