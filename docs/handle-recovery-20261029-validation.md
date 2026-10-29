# Handle 恢复页修复与验证（2026-10-29）

## 问题与修复边界

旧凭证已完成本机删除，其他设备随后恢复了同一 Handle，本机留有较旧的 binding。
旧 Core 因缺少连续迁移链拒绝准备；App 又按粗粒度 OTP phase 隐藏错误和输入区，最终只剩取消，
用户既不知道原因，也没有重新准备的路径。这与前一轮联邦根端点/Nginx 故障不同。

Core 在验证账号与完整 Handle 后，仅凭所有相关 binding 的精确已完成删除证明选择 fresh owner。
历史留在旧 owner；不拼接缺失的迁移链、不复活旧凭证或密钥、不自动归并历史。
App 只消费公开动作，始终显示状态和错误，提供明确的验证、确认、精确续办、重新准备及进入消息操作。

## 安全与兼容性复核

| 边界 | 处理及证据 |
| --- | --- |
| 权威账号/Handle | 以同次 OTP 验证后的权威 binding 为准；账号或 Handle 不符仍拒绝 |
| 历史退役证明 | owner/DID/device 精确匹配已完成删除，所有相关行逐条检查；缺证明、活跃凭证、未来代次和混合冲突均拒绝 |
| 代次 | 相同 DID 必须为权威当前代次；不同旧 DID 必须严格早于当前代次，不猜测 continuity |
| 竞争与提交 | 准备时确定 owner；首次 Commit 前在原 Handle→owner 锁内重查竞争操作，冻结的 operation、intent、DID 和密钥不重写 |
| 普通 Join | 不共享 Recovery fresh 例外；matcher 回归同时断言 Join 仍拒绝缺失连续链 |
| 历史与密钥 | 新旧 owner 分区保留，fresh 不迁移旧普通历史，旧 E2EE 私钥不恢复；准备重开测试保留旧 binding |
| 已有任务 | 旧未提交失败任务必须明确 discard 后再准备；已尝试提交的任务仍精确续办，不透明重发 |
| 页面生命周期 | 返回使旧页面 epoch 失效，Core 持久化任务保留；原会话/新会话副作用仍受现有 session guard 控制 |
| 诊断 | 只复制闭合错误码、阶段和时间；widget 检查不含 Handle 或手机号，代码不读取 OTP/密钥/HTTP body |
| 服务兼容 | 未改服务 wire、公共 DTO、数据库 schema、租户认证或 P5/P6 协议；本轮不部署服务或发布 SDK |

源码复核未发现需要放宽以上边界的遗留问题。真实服务闭环和正式 registry 来源仍各自作为独立门禁。

## 已执行的定向验证

| 命令/范围 | 结果 |
| --- | --- |
| Core `cargo test -p awiki-im-core --lib identity_local_owner_matcher --quiet` | 18 passed，失败 0；循环覆盖 14 类退役/冲突组合，并验证普通 Join 边界与历史行保留 |
| Core `cargo test -p awiki-im-core --lib identity_handle_recovery_runtime --quiet` | 69 passed，失败 0；含真实 custody/Vault/SQLite 的旧代次准备、重开及首次 Commit 前竞争变化 |
| App `flutter analyze --no-pub lib/src/presentation/recovery tests/e2e/flutter/app/handle_recovery_ui_test.dart tests/unit/handle_recovery_flow_test.dart` | 无问题 |
| App Recovery flow、crash cut、Core adapter、onboarding lookup 四文件定向测试 | 109 passed，失败 0；新增诊断复制检查后重跑 flow 为 77 passed |
| App `flutter test --no-pub tests/unit/e2e_harness/` | 436 passed，失败 0；断点代理后续变更后，受影响的 4 项 owning 检查再次通过，其余未重复 |
| 布局矩阵 | 390/1100 宽、中英文、深浅色、1/1.6 字号共 16 组合；无 overflow/异常，阻断原因与主要操作可达 |
| System `uv run --no-sync pytest tests/non_did/test_handle_recovery_v1_contract.py -q -rs` | 41 passed，失败 0，跳过 1：受管 operator 检查仅支持 Linux；不是远端恢复通过 |
| System `cargo check --manifest-path probes/handle-recovery-v1/Cargo.toml --locked` | 通过；probe 及锁同步当前 Core 0.1.12 源码依赖 |
| Core `AWIKI_APPLE_SOURCE_INTEGRATION=1 scripts/flutter/build-sdk-native.sh --macos-only --macos-arch arm64` | 通过；第一次发现原有生成文件 import 顺序差异，仅统一 6 行后重跑，内容哈希不变 |
| App `AWIKI_APPLE_SOURCE_INTEGRATION=1 scripts/verify_im_core_native_artifact.sh` | 通过；macOS arm64 单架构、固定 Core 源码及原生库摘要匹配 |

Core 测试夹具和 App 默认测试能力夹具补齐现有 Recovery capability 声明，未修改生产能力判断。
Flutter 使用原 pubspec.lock，未升级依赖；构建工具产生的 CocoaPods 版本尾注不进入提交。

## 真实后端与本地 Debug

产品专项仍为 `handle-recovery-state-machine`，新增：删除本机凭证后，另一隔离 native runtime
先恢复同一 Handle，再回到原 App 验证 fresh owner、不迁移旧历史及显式进入消息。
catalog/attestation 同步更新，沿用现有隔离配置与测试专用 user presence，不证明系统生物认证通过。

首次新用例构建发现 SessionIdentity 字段名错误，已修正并通过 analyze。后续真实执行在首次测试账号
注册 OTP 请求处收到新加坡 HTTP 502，未进入恢复提交。两个受管服务此前在 10 月 27 日正常停止；
用户明确授权后，通过受管 `awiki-user-service start` / `awiki-message-service start` 启动，双 readiness
通过且 `trafficGated=false`。仍使用 User `20261026T120940Z-f3a43cfd4152`、Message
`20261026T135122Z-2381a8d8b750`，未构建或部署新服务版本。

恢复断点测试的 loopback proxy 起初未转发新版 Core 的公共能力查询，导致首次 Commit 前正确拒绝。
测试代理现仅额外透传精确域名、固定版本参数的真实 server-info；去掉认证/Cookie、禁用跳转并限长，
不合成能力声明，原 exact-operation Commit 与提交后 WNS 切点保持。对应 4 项单元检查与 analyze 通过。

产品专项随后完成目标隔离及重开续办两段，连续恢复段遇到共享测试手机号的验证窗口限制；现场记录
确认 factor exchange 的 HTTP 429。服务按手机号/purpose 与客户端 IP 限制 5 次/300 秒，正常测试须
串行排程、等待原窗口，不能改限额或把错误当成准备成功。失败证据保留在本机
`.e2e/handle-recovery-state-machine/`。错开共享窗口后，最终产品 run
`20261029072339-hnnnmxb4d2` 完整通过 TARGET / RESUME / REPEAT 三项、18 条业务断言，
失败 0、跳过 0，耗时 2 分 28 秒。包括真实提交切点、迟到回调隔离、同 Scope 重开续办、凭证
删除后独立设备先恢复、原设备再建立 fresh owner、显式进入消息及独立账号保留。
制品来源为干净的 `bed46eec4b9b1d6c55e4f2ec0c47296d5fa562f0`，`evidenceEligible=true`；
不存在以未提交修改或测试替身冒充服务结果的情况。输出中的 integration_test 插件提示来自
直接执行 prepared executable，runner 已按 attestation 校验全部业务断言；不是忽略失败结果。

`remote-handle-recovery-state-machine` 是支持 Mac 的独立公开 Core/真实服务专项，已经按 owning
入口启动；0600 临时 target manifest 只把新加坡目标的 operator 换为既有 reviewed SSH profile，
URL/domain/capabilities 保持不变，关闭自动远端删除并保留 `remote_residual_ledger`。
此前把此专项误写成必须 Linux cleanup 的表述在此纠正。Linux 本机审计要求适用于另一组
`remote-handle-recovery-v1` 完整门禁；本轮未执行该完整门禁，不用产品 E2E 替代它。

System 首轮为 2 通过、2 失败、2 未完成，已中断并按失败点收敛。新增旧代次 fresh Recovery
与响应丢失/延迟链已通过；另一设备恢复后的旧操作关闭定向复验为 1 passed、失败 0、跳过 0。
初次 RPC 拒绝只记录为 `other`，未保存正文，不能据此推定具体服务拒绝原因；现已补齐受限的
V4 `awiki_code` 诊断及 14 项 owning 单元验证，后续未知值仍归 other，不输出正文。

还修正了状态机专项漏用已有持久文件隔离的问题。首轮 pytest 默认临时目录已被后续 pytest
轮换清理，远端残留账本仍在；这是隔离测试材料保留缺口，不涉及正式 App/真实用户数据。
专项现经 owning runner 创建独立 0700 artifact/basetemp，失败或中断保留整个恢复根和包装
密钥，成功才删除本地 basetemp；15 项隔离检查通过。此修复不放宽 canonical Linux cleanup
或远端删除权限。

最终六个相关 System case 均有逐项通过证据，且核对各 test body 与当前提交一致、所有执行固定
Core `943659489ec376c9802e2dc2db4f5683e7b9ddbe`。这是首轮与定向复验的合并证据，不是单轮六项
全绿，也不代表全量 System。原始失败记录保留，机器摘要在 System 仓
`ops/releases/20261029-handle-recovery-focused-evidence.json`。

| System case | 最终证据 |
| --- | --- |
| 已提交重开、注册互斥、旧凭证删除、远端推进后 fresh 恢复 | 首轮 passed |
| 响应丢失及延迟原始 Commit | 首轮 passed |
| 另一设备恢复后关闭原已提交操作 | 定向 1 passed，0 failed，0 skipped；初次拒绝的具体原因不可还原，未推定为 SDK 缺陷 |
| bootstrap 设备撤销后关闭原已提交操作 | 定向 1 passed，0 failed，0 skipped |
| 自然过期、同 intent 续期、绑定改变及 activate/discard 竞态 | remaining-r2 的该项 passed |
| 旧设备无历史／已有普通历史重新加入 | 最后定向 1 passed，0 failed，0 skipped，376.17 秒；旧 owner 和 exactly-one 普通历史均保留 |

撤销场景补齐切点后新 admin 的真实 tail-only 接收初始化，并额外断言 Recovery 仍精确 pending、
未新增普通消息，再产生 Join 请求；没有给被测 cold 旧设备增加 warmup。另一次夹具收取出现
transport_unavailable，同一持久身份重读成功。共享读取 helper 现可显式选择一次传输错误重读，
Join 通知轮询使用该选项；认证、业务拒绝、畸形投影与持续失败仍失败，普通收取默认不重试。
该 helper 的 168 项 owning 检查、41 项 Recovery contract（另 1 项 Linux-only skip）、
14 项代理检查、15 项隔离检查通过。没有改变业务发送或验证码的透明重试策略。

本地正常 main.dart 的 Mac Debug 双 App 构建已通过，使用既有
`scripts/build_manual_dual_macos_apps.sh`、独立 bundle ID 与数据目录。主调试 App 已复制到桌面
`AWiki-恢复调试-20261029.app` 并实际打开，正常显示独立空状态的登录页，未改动安装的正式 App。
其 bundle ID 为 `ai.awiki.awikime.dev.recovery20261029`，状态目录为工作区同级
`dsh-recovery-20261029/manual-state/admin`；副 App 使用独立 joiner ID/目录。原生中间库和
Core 当前制品逐字节匹配，均为 host arm64。这个启动检查不代表旧用户恢复/OS presence 的人工验收。
未运行全量 System/产品 E2E、Android/iOS/Windows 原生构建；本轮范围为定向验证和 Mac Debug。

## 源码与发布顺序

- Core 实现固定 `b34103837800c94176230e8b22f7b8e53f8d78e1`，消费端/桥接输入为
  `943659489ec376c9802e2dc2db4f5683e7b9ddbe`，对应 Core PR #66。
- App `dependencies.source.json` 固定完整消费端提交；Core 自有清单和锁只选择该修复 Core，
  ANP `1.0.7`、Identity `0.2.6` 来自 registry。原生构建记录和实际解析来源已核验。
- System probe 的本地编译沿用其 owning workspace path；不作为 registry 制品来源证明。
- 当前已发布同名 Core 0.1.12 不包含本修复。本轮不覆盖同版本发布；正式 App 合并发布前，先发布包含
  修复的新 Core 版本，再更新正式 pin/lock、撤销临时源码清单并完成 registry/真实服务门禁。
- Message #22、System #55 继续保留前一轮生产修复；这次仅把配套恢复回归并入 System #55。


## 正式依赖切换（后续生产候选）

同事已从 `04dd9991024ab77ce00f4460706d2536f6571e0a` 发布 `awiki-im-core 0.1.13`。
官方归档 checksum 为 `0c39ab233dbe9ba2732461ea28a1184ab5d9c59ca7222394a992af6a91c9d9c6`；
本次独立核对包内 vcs SHA 与六个恢复相关 Rust 文件，均与该提交一致，发布 workflow 成功。
撤销 App/Core 临时源码清单，正式 Rust SDK policy/锁切换到 registry 0.1.13；ANP 1.0.7、
Identity 0.2.6 保持。新 App 候选版本为 0.1.42+54。
前文源码联调和失败记录保留为历史证据；正式制品来源及发布验收另行记录，不能由 Debug 代替。
