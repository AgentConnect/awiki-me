# 桌面测试：固定 A/B 客户端的构建与验收方法

适用：当前 Windows x64、真实后端 `awiki.info` 的 owning AWiki Me E2E。本文描述可复用方法；每次实际结果、来源 SHA、时长和报告 URL 保存在独立运行记录，不能以方法说明代替验收。实现合同见 [运行时控制](e2e-runtime-control.md)，通用门槛见 [Verification Policy](../../awiki-harness/rules/verification-policy.md)。

## 一、开发新的测试场景

1. 产品交互/业务断言仍放在 `tests/e2e/flutter/`，用例和必需 phase 由 `case_catalog.json`、`suite_manifest.json` 管理。每个场景有明确成功、失败、持久化/恢复和清理证据。
2. 在 `runtime_control/shared_host_contract.dart` 添加逻辑别名/路由，并在 `flutter/shared_desktop_host.dart` 注册原场景函数。每次启动只调用一个入口，禁止把所有导入文件的 `main()` 一起执行。
3. `app_artifact_specs.json` 仍声明逻辑别名及 consumer suite，target 固定为 `integration_test/shared_desktop_host_test.dart`。单端/管理员用 A，第二设备用 B；不新增第三个 bundle ID、场景 target 或按阶段切换的编译开关。
4. 场景、角色、阶段、故障和状态根通过私有运行计划或已有受保护配置传递，不把 run ID、手机号、OTP、PIN、令牌和 fixture 值编入程序或放进命令行。
5. 同一设备重启沿用原数据根和逻辑身份；不同设备保持根、原生实例与凭据隔离。用检查点证明已经到达故障边界，不能用固定 sleep 猜提交时间。预期中断只是中间状态，恢复后的实际断言才能证明通过。
6. 新增或改变断言时先做所属单元/组件验证；补充两客户端上限、路由覆盖、错误 slot、过期/错误计划和 Release 禁用分支。不能因实现方便放宽原业务超时、把 pending 当远端确认或删掉失败记录。

## 二、冻结本轮来源与输入

为每次验收创建唯一 `verification-runs/<run-id>/`，保存不公开的原始日志、脚本、私有 fixture 引用、源码/SDK 摘要、进程归属和恢复记录；不放进 `html-docs/`。

- 记录 App/Core/ANP/Identity 的完整 SHA、分支与已有工作区差异。提交改动后再构建，验收期间不混入不同来源。
- 核验 Windows PE x64、SDK DLL SHA-256、FRB binding hash、CLI/probe/Daemon 的嵌入源码 SHA。依赖继续走各 owner 的已审核入口，不为省时跳过来源检查。
- 私有输入用当前用户/SYSTEM 的 NTFS ACL，公开输出只记录固定类别、计数、布尔核验结果和所需非敏感摘要。
- 记录基线环境文件哈希、受管配置/进程及注册配额策略。过期 Realm 配置只能用原签名者和 owning renewal 工具续签，保持 crypto projection、端点、权限及 PIN 预算不变。

## 三、先准备程序，再打开测试窗口

首先使用 owning Windows launcher 的 `-PrepareOnly`；此时不启用临时后端环境、不创建业务账号。旧 registration/discovery fixture 的实际准备应在临时窗口启用且预设匹配后进行。

```powershell
./scripts/run_windows_e2e.ps1 `
  -Case full -RunId <unique-prepare-id> -PrepareOnly `
  -ConfigPath <private-reviewed-config.yaml> `
  -PinFixturePath <private-pin-fixture.json> `
  -OtpPresetPath <private-otp-preset.json> `
  -PythonBin <native-Windows-python.exe>
```

复用已有管理脚本的命令解析，不把占位符当成可直接执行的命令；参数内容由本轮私有输入提供。启动器管理的依赖包含原生工具、受审依赖和 DSH 入口，不能用 WSL/远程客户端替代本机证据。

逻辑清单可能有多份 JSON manifest，但在固定来源/架构/工具链/SDK/目标租户配置下只有 A/B 两个编译指纹。相同指纹、真实内容哈希及来源核验通过才复用缓存；只使用 A 的定向场景不必构建 B。记录 `cacheHit`、唯一物理 host 数及构建阶段时长，不把逻辑别名数或 prepared case 数当作编译次数/业务通过数。

准备必须由 owning runner 汇总完成；Windows 当前范围是 114 audited = 109 prepared + 4 user_excluded + 1 not_applicable，业务 passed 为 0。任一成员准备失败都不能手改聚合报告为成功。

## 四、受控执行与独立恢复

程序准备成功、输入与来源再次核验后，才通过原受管 operator 打开有限 OTP/注册/恢复 allowlist 和配额窗口。保存原文件字节、选中配置、三角色运行环境及实际数据库策略；用本轮独占域与 registration fixture，不复用旧 closed 窗口。

执行仍使用 `scripts/run_windows_e2e.ps1 -Case full`，附本轮 registration/discovery fixture 和新的 actual run ID。需要 required/execution-only 模式时，准备目录与逻辑 manifest 必须齐全，缺失即失败；禁止静默换源或追加场景二进制。

外层 `try/finally` 必须依序处理：本轮 registration intent 精确清理、原环境文件恢复、受管原配置加载与健康核验、原配额策略恢复、独占域策略精确清理。即便启动失败也要检查未知写入结果。另用只读 inspector 核对真实文件哈希、实际运行角色的受控值、SQL 策略/fixture 残留，不能只相信本地 restored 标记。

资源账本允许按合同保留缺少删除接口的隔离身份等，必须说明范围与原因；环境恢复成功不等于所有数据零残留。不清空整个数据库、整个 cache 或其他运行的账号来制造通过。

## 五、失败后如何继续

区分构建/依赖、进程与编码、页面前置、实际业务断言、completion/attestation、清理恢复六类边界。先看最早原始失败，清理异常单独记录，不能覆盖主错误。

- 构建看 `preparation-progress.json`、实时脱敏的 pub/Flutter JSONL 和 owning child report；超时应确认本轮进程树状态。保留旧输出，禁止只增加时限反复重试。
- 执行看实际 case phase、闭合诊断和 attestation，不凭组名把前置失败归因于后续业务。
- 修复先复现并跑所属单元，再只跑相关定向用例；通过后才安排一次新来源冻结的最终 full，不每修一处就循环全量。
- 源码确需改动，重新提交、核验并准备对应 A/B。新旧来源和历史定向结果不得累计成一次全量通过，旧失败证据保留。

恢复夹具要求远端已读确认时，复用 `tests/e2e/recovery_read_ack.dart`：固定消息、水位和 readAt，只对精确的 `predecessor_in_flight` 排队状态在原预算内等待最终 ACK。错误目标、fallback、其他 partial/服务错误和超时均终止，不把本地提交当远端成功。

Root 送达接受不等于接收端本地管理权限已就绪。管理权限观察使用当前 Session 的精确 protocol device ID，先由公开 `localManagementReady` 确认本地状态，再读取 Registry，并保留原两分钟预算、会话归属检查和最终两端管理员断言。`permission_denied` 仍为终止错误，不能作为通用可重试类别，也不在测试中直接刷新凭据或重发 Root。

普通 Join 后的设备绑定检查不能假定目标一直保持 rootless member：自动管理可能在后续夹具准备期间完成。使用同一精确设备检查，允许 member/未就绪或 admin/就绪两个合法阶段，仍要求恰好两台 active 设备、唯一当前 ready admin 和精确非当前目标；拒绝 role/readiness 矛盾、错误 principal 和第三设备。撤销测试继续证明破坏性确认、一次新鲜 E2E user presence、精确撤销、存活管理员、MLS Remove 收敛和被撤销端无法读取未来消息，不能用新的前置检查替代这些终态。

桌面页面等待或身份恢复失败时，`desktop-closed-failure` 记录固定字段的会话匹配、运行状态、头像控件状态和 Core 网络阶段。它不输出 DID、任意页面文本、服务错误正文或凭据；先据此定位失败边界，再决定是否需要产品修复。组异常中断但没有逐条终态的 `not_run` 不能解释为完全未启动，更不能计为通过。

## 六、结果和方法的交付

最终核对聚合的每个 case ID、原平台/用户排除项、必需 phase/assertion、实际 passed 集合、每个 child attestation hash、源码/SDK冻结及独立恢复证据。构建准备和组内部分通过不能替代 full 完整结果。

完成必要的正常客户端构建和既有产品 review，保留原预览进程；E2E 程序不充当人工使用客户端。全量 HTML 只导出简短结论和必需展示资源，原始日志/配置/二进制继续留在执行目录。发布到 `awiki.info` 设计文档静态服务，核对 HTTPS、资源和 Chrome 展示，最终提供可点击 HTTPS URL。

实际执行记录补充本轮时长、最终来源、唯一 host/编译次数、相关修复与局限；实际冷/温对照完成前不给出提速百分比。后续测试程序应复用此流程和已有 owner helper，不再另建按场景编译或绕过 attestation 的平行框架。
