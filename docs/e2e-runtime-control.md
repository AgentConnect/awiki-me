# 桌面 E2E 运行时选择与构建复用

实际构建、执行、恢复与交付流程见 [桌面 E2E 测试方法](desktop-e2e-testing-method.md)，新增测试程序应复用该方法及本合同。

2026-11-04 按最新要求收敛为最多两个固定测试客户端。当前交付为代码、单元测试和静态检查；没有启动客户端 E2E、真实后端测试、整批客户端构建或性能对照。Windows 是本次验证平台。

## 构建与执行的边界

34 个产物名称继续作为 runner/profile 的逻辑选择器，旧 case ID、suite、业务断言和资源处理保持不变。全部指向 `integration_test/shared_desktop_host_test.dart`，同一进程只调用选中场景的原测试入口；不一次注册或执行所有导入文件的测试。

| 固定客户端 | 原生身份 | 消费场景 |
|---|---|---|
| A | `ai.awiki.awikime.dev.e2e.host.a` | 所有单客户端、管理员、恢复和重启阶段 |
| B | `ai.awiki.awikime.dev.e2e.host.b` | App-pair 第二设备 `joiner` |

在固定源码、平台/架构、工具链、SDK 和目标租户配置下，默认测试最多对应两种编译输入；只使用 A 的定向场景准备一份即可。同源缓存有效时可以不重编。各逻辑名称的 JSON manifest 指向同一 A 或 B 内容缓存，不为每个场景复制/编译程序。准备工具分开返回 `logicalArtifactCount` 与 `physicalHostCount`，保留原计数字段兼容调用方。

`shared_host_contract.dart`、产物清单加载器和直接 builder 入口共同拒绝第三种原生身份、旧 target、额外场景编译参数或未知路由；不能删除合同版本字段绕过。所有场景只有统一的 E2E 开关和固定 slot 编译参数。冷/温构建速度尚未实测，不能把定义数量换算为固定提速比例。

Windows/macOS 的显示身份由 bundle ID 稳定派生，不再因产物别名而改变；编译缓存合同版本已更新。target、产品源码、传递测试依赖、SDK、锁文件、路径依赖和工具链变化继续使缓存失效。没有删除 native provenance 校验。

## 私有运行计划

owning runner 为每次执行生成新的私有 `invocations/<nonce>.json`，通过 `AWIKI_E2E_INVOCATION_PATH` 和 `AWIKI_E2E_INVOCATION_DIGEST` 绑定。不要手工修改报告或复用旧 invocation。

`tests/e2e/runtime_control/invocation.dart` 是实际 schema/校验入口。字段包括版本、artifact、run ID、attempt、唯一 invocation ID、scenario、platform、case IDs、artifact SHA-256、phase、role、interruption 和期限。列表不可变，未知字段、错误模式、错误平台、case/run/scenario 不匹配、摘要变化、过期或非私有文件均拒绝。

runner 在写计划前，校验 artifact 的 consumer suite 与当前 case 范围；执行前继续验证原 manifest、来源、编译指纹和实际产物 hash。运行计划摘要独立于 compile key，phase/role/故障选择不会隐式改变程序。

同一逻辑设备跨阶段保持原状态根和 secret service；E2E scope secret 继续按显式状态根保存，scope ID 保持既有随机身份。A/B 使用不同原生身份与私有状态目录；所有默认 prepared 执行与 App-pair 复用现有桌面执行租约，避免两项场景同时抢占 A。崩溃残留不能通过临时增加第三个 host 来绕过。新构建不直接接管旧运行/旧原生命名空间，后续真实测试应使用当前来源和新的 run ID。

owning runner 的真实执行/准备拒绝 `AWIKI_E2E_USE_FLUTTER_TEST=1`，避免继承旧调试环境后静默逐场景重编。旧独立入口保留作历史/显式诊断源码，但不属于默认构建清单，也不会由正常 runner 启动；dry-run 不执行编译。正式安装包、SDK/CLI/Daemon 依赖及专用原生 Release 检查继续遵循各自构建合同，不作为额外的场景客户端。

旧 Hosted 用例的 `AWIKI_RELEASE=1015` 通过受 Release 屏障保护的测试 metadata seam 保留原值，其他场景仍为原默认 `0815`；不靠第三种编译配置实现。退役 Hosted 排除项没有恢复，真实后端与权限均不变。

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
- 批量准备按两种编译配方计算身份；低磁盘缓存回收固定保护当前 A/B 两个指纹，避免后续别名再次触发同源编译。
- 兼容标记绑定工具链/依赖/SDK/原生身份等输入；不一致时按原受控快照边界刷新。源码变更仍进入真实编译指纹和构建，不通过缓存跳过。
- 依 Git source inventory 精确移除已删除源码；内容配置后字节相同时恢复原 mtime，减少仅复制导致的失效。目录/链接逃逸拒绝。
- pub 和 Flutter 构建输出实时脱敏写入工作根的 `pub-get-output.jsonl`、`flutter-build-output.jsonl`，进度文件继续记录阶段与耗时；外层终止也保留已经落盘的输出。
- 输出日志及内存尾部有界，保留原始失败，进程树清理异常不覆盖首个错误；未扩大原 12 分钟外层准备期限。
- 单项失败后，仍通过原 owner 准备入口重试；其余同源且 hash 正确的产物命中内容缓存。必须重新通过 owning full 聚合校验，不能直接编辑旧 failed report。

最新命令、结果与开发完成边界见 [两客户端执行记录](../../awiki-plan/20261104-desktop-e2e-runtime-control/two-host-execution.md)；第一阶段记录保留历史含义。没有实际重新计时前，不给出冷构建或全量提速百分比。
