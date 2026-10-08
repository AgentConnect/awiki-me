# 智能体头像实施方案

状态：代码与素材实现完成；2026-10-05 已完成 Windows 本地编译、awiki.info 服务端部署、真实后端 System Test 和 Windows 头像专项 E2E，详见文末记录。真实生成服务尚未配置。2026-10-08 用户授权提交、推送本任务代码；保留其他任务的工作区改动。

## 现有架构与设计

AWiki Me 使用 Flutter、Riverpod、既有 `AvatarBadge` 和 `ProfileAvatar`。真人头像由 Core Profile facade 管理。智能体的存在性、稳定 `agentDid`、控制者和跨设备清单由 User Service Inventory 管理；头像沿用 Inventory 的 `profile_summary` 扩展及版本事务，不建立第二份身份、消息或资料事实源。

服务端以 Inventory 的不可变 `id` 作为 `agent_id`，使用 DID 查找现有行，名称和 Handle 仅用于显示。头像记录来源、预置素材 ID、动图/封面资源地址、状态、版本、更新时间及安全错误码。创建事务立即绑定稳定默认预置头像；旧行按不可变 ID 兼容映射默认，改名和打开页面不会生成素材。

## 实施顺序与验收

1. 从设计文件按四个准确键提取 GIF/PNG，保存业务静态资源。提供 32 款预置头像（按目标文字暂将“头衔”理解为头像）；预置资源属于随包素材，不冒充生成服务结果。
2. 扩展 Inventory 头像读取/写入能力，复用 ControllerScope 权限、头像不可变资源发布、CAS 与账号状态 outbox。上传 GIF 保留动画并生成封面；静态图沿用裁剪。服务端验证所属控制者、输入边界、版本和幂等请求；恢复默认、失败、旧生成覆盖均有测试。
3. 自动生成仅经可插拔真实服务接口调用；输入仅为明确提供的名称、职责、形象描述。未配置时隐藏生成动作。生成中保留静态封面，失败保留可用素材并提供安全原因与显式重试；生成提交受头像版本限制。
4. 共用头像组件识别智能体并使用圆角方形；真人继续圆形。单独智能体播放动画，群组所有成员和 reduced motion 使用封面。动画失败回退封面，再回退名称/图标。固定 1:1 空间；角标独立定位。
5. 所有者编辑入口支持预置、上传、取消、保存/上传失败、恢复默认和配置后的生成；保存刷新 Inventory/公开资料投影，聊天、消息、身份卡和群头像通过同一组件同步。
6. 更新现有契约及 API 文档，补充 App unit/widget、服务端权限/CAS/存储测试、System Test 与产品 E2E 缺失场景。以实际可运行平台核实，不把 fake 或旧报告当作远端通过。

## 验证与执行记录

- 已读目标文件、App/服务端规则、Verification Policy 及相关资料/Inventory 代码。
- 既有改动仅存在于 `awiki-me` 的文档、Windows 构建脚本和测试资料，必须保留。
- 当前服务端只有真人 JPEG 头像能力；智能体上传需要在现有 User Service 路由内扩展，单独 App 本地设置不能满足权限与跨用户持久化要求。
- 最终审计逐项检查四款原素材、32 款预置、创建默认、持久化同步、权限、动图/封面回退、减少动态、群组、取消/失败/重试及旧生成 CAS。

## 完成结果

- 原设计四组 GIF/PNG 逐字节提取；另以内置 ImageGen 参考这四款的颜色、几何轮廓、眼睛与光泽，生成 28 个独立透明、仅头部的 3D 造型，再以 FFmpeg 编码为 32 帧、3.2 秒、256×256 循环 GIF，并保留 PNG 封面，合计 32 款动图。新素材不是运行时自动生成结果。所有 28 条实际生成提示词和输出来源见 [素材清单](agent-avatar-assets.json)，素材同时进入 App assets 和 User Service wheel。
- 2026-10-05 按用户要求将新增的全身版本替换为头部版本。替换前的 App、User Service 全部 36 个素材文件及生成清单已备份到 `D:/awiki-backups/agent-avatars/20261005-092140-before-heads/`；四组原始 GIF/PNG 保持字节不变。仅本地修改，不提交、不推送。此次素材检查记录在 `D:/awiki-space/verification-runs/agent-avatar-heads-20261005/asset-audit.json`；动图复验记录在同目录 `animation-audit.json`。
- 使用 Inventory 不可变行 ID、头像版本 CAS、既有账号状态事务/outbox 和公开 Profile 投影。所有者权限在读取、写入、幂等重放和任务提交时重新校验；普通资料更新不能覆盖保留头像字段，历史行也不能注入任意头像 URL。
- 同一所有者设备走既有账号状态同步；其他用户通过公开 Profile 刷新收敛。当前机制不保证向每个聊天对端即时广播头像更新。
- 上传 GIF 保留帧，静态图使用裁剪；恢复默认可预览，失败保留编辑草稿并复用幂等请求。生成仅在真实 HTTPS 服务已配置且用户明确操作时调用；失败显示安全原因和显式重试，旧任务无法覆盖新选择。

## 当前验证证据

### 2026-10-05 头部动图修订

- 全部 32 款均提供 GIF 与 PNG；新增 28 款 GIF 为 256×256、32 帧、每帧 100 ms、无限循环、透明背景及 disposal=2，采用轻微周期摇摆/浮动。App 与 User Service 的 64 个文件逐字节一致；四组原设计 GIF/PNG 未变。PNG 头部版本另备份到 `D:/awiki-backups/agent-avatars/20261005-094349-head-pngs-before-animation/`。
- 素材审计：`user-service/.venv-windows/Scripts/python.exe verification-runs/agent-avatar-heads-20261005/audit-animations.py`，32 款通过帧数、时长、实际不同帧、透明度、循环衔接、边界和摘要校验；结果在 `animation-audit.json`。
- App：`flutter test --no-pub tests/unit/avatar/agent_avatar_image_test.dart tests/unit/avatar/agent_avatar_editor_test.dart`，10 项通过；含全部 32 个真实 GIF 的 Flutter 解码及新款动态/减少动态显示策略。日志 `app-animation-tests.log`。
- User Service：`python -m pytest tests/app/agent_inventory/test_agent_avatar.py tests/app/agent_inventory/test_agent_avatar_rpc.py -q`，48 项通过；含全部 32 款匿名 GIF HTTP 读取、封面、历史预置动画投影和上传保持静态的边界。日志 `service-animation-tests.log`。服务端 Ruff 与素材修改后的 diff 检查通过。
- System 及产品 E2E 的预置选择改用新增动图 `research`；真实远端仍未部署新接口/素材，因此这两个远端用例本次未执行。此次没有提交、推送或部署。

证据目录：`D:/awiki-space/verification-runs/agent-avatar-20261005/`。未导出 HTML，未运行完整系统或产品 E2E。

隔离 MySQL 服务已停止；临时脚本已删除。自动审批审查以 `blocked by policy` 拒绝删除 `verification-runs/agent-avatar-20261005/mysql-data/`，因此数据目录和 portable MySQL 保留用于复查，没有运行中的测试数据库进程。

| 检查 | 命令/范围 | 实际结果 |
|---|---|---|
| App unit/widget 与 catalog/artifact 契约 | `flutter test --no-pub tests/unit/avatar tests/unit/data/agent/user_service_agent_inventory_adapter_test.dart tests/unit/agents/agents_provider_test.dart tests/unit/agents/agents_page_layout_test.dart tests/unit/e2e_harness/test_catalog_test.dart tests/unit/e2e_harness/app_artifact_spec_test.dart tests/e2e/test_catalog_contract_test.dart` | 212 通过、失败 0；GIF 预览尺寸及解码回退测试断言已修正后重跑 |
| 最后投影变更 focused 复验 | `flutter test --no-pub tests/unit/agents/agents_provider_test.dart tests/unit/avatar/agent_avatar_editor_test.dart` | 109 通过、失败 0；新增旧头像读取不得覆盖新版本、不得创建清单成员的用例 |
| User Service 头像、Inventory、账号状态和公开资料 | `python -m pytest tests/app/agent_inventory tests/app/account_state tests/app/did_profile/test_router.py tests/app/did_profile/test_agent_profile_capabilities.py -q --require-test-database` | 176 通过、失败 0、跳过 0；使用隔离 MySQL 8.4 数据库，包含真实事务与 HTTP 路由 |
| 最后图片并发变更 focused 复验 | `python -m pytest tests/app/agent_inventory/test_agent_avatar.py tests/app/agent_inventory/test_agent_avatar_database.py tests/app/agent_inventory/test_agent_avatar_rpc.py -q --require-test-database` | 24 通过、失败 0、跳过 0；调整上传/生成共用解码槽位时发现的重复占用已修正并复验 |
| 注册/清单/退役 SQLModel 兼容 | `python -m pytest tests/app/agent_registration/test_agent_registration_storage.py tests/app/account_state/test_domain_mutations_storage.py tests/app/account_state/test_agent_retirement_storage.py -q --require-test-database` | 30 通过、失败 0、跳过 0 |
| Linux 头像运维 unit | 独立临时目录内 `PYTHONPATH=. python -m pytest test_agent_avatar_ops.py -q` | 5 通过、失败 0、跳过 0；含 GIF/PNG 快照恢复、引用保护、真人 JPEG 兼容和 Nginx 配置 |
| System catalog portable 契约 | `python -X utf8 -m pytest tests/non_did/test_case_catalog.py -q -k 'not manifest_node_ids_are_exactly_present_in_raw_collection'` | 19 通过，1 个 Linux raw collection 检查明确未执行 |
| Catalog 与素材完整性 | `dart run tool/validate_test_catalog.dart`、`python -m helpers.case_catalog`、素材摘要/原始 Data URI/wheel 对照 | 127 App cases、224 System cases，36 个文件一致，四组原图字节一致 |

### 未通过或未运行的边界

- 广泛桌面 runner unit：125 通过、12 失败，保留 `app-harness-tests.log`。失败来自现有 Windows/Unix 路径、平台限制和 CRLF oracle；本任务没有扩展桌面 E2E 的 Windows 支持。头像相关 catalog/artifact 契约另行通过。
- 全部 System raw collection 在 Windows 有 8 个 Linux 运维模块的 `fcntl` 导入错误；保留 `system-raw-collection.log`。头像运维用例已在 Linux 执行；新增真实后端头像 case 在 Windows 成功收集（1 case），收集不代表执行通过。
- 既有真人 JPEG 的部分 storage/router 测试在 Windows 受 POSIX 目录 fsync 及过长测试参数环境变量影响，记录在 `existing-avatar-tests.log`；未修改真人实现来适配本机。相关 JPEG 运维和注册兼容已通过，真人完整上传回归仍需要 Linux lane。
- 真实 System 入口：`tests_v2/user_service/test_agent_avatars.py` 已加入 `remote-avatars`；目标需显式 `AWIKI_SYSTEM_TEST_MODE=remote` / `AWIKI_SYSTEM_TEST_TARGET=awiki-info-testing`，并部署新 User Service 和 managed PNG/GIF 路由。本轮没有升级 `awiki.info`，因此该真实后端用例未执行。
- 真实 App 入口：`dart run tests/e2e/runner.dart --case agent-avatars --config <reviewed-config>`。需要支持的 macOS/Linux runner、对应 App/CLI 编译资产，以及 `AWIKI_E2E_AGENT_AVATAR_DID` 指定由 App 账号拥有、头像版本 0 的可销毁新测试智能体；缺失夹具失败。当前 Windows 未执行该产品 E2E。
- 真实生成服务未配置，不调用真实模型；仅验证接口输入边界、失败、取消和 CAS。真实 provider 动图质量、延迟与部署网络策略需在配置后验收。

## 发布前恢复条件

同步部署当前 User Service 及 32 款随包素材，用受管入口生成/验证该环境 PNG/GIF/presets Nginx 配置和备份恢复；随后在真实目标运行 focused System case、Linux 真人上传回归及 App `agent-avatars`，按现有精确 operator/ledger 清理测试身份。本轮仅提供可审阅代码，不更改远端业务进程。

## 2026-10-05 后续本地编译与 awiki.info 联调

用户后续明确要求本地编译并连接上海 awiki.info 测试；上面的“未升级/未执行”描述属于先前离线实现轮次。本轮证据保存在工作区 `verification-runs/agent-avatar-awiki-info-20261005/`，代码未提交。

- Windows x64 原生 DLL 和普通 `lib/main.dart` Debug App 构建成功。按现有源码联调清单构建 SDK，并保存实际依赖提交与 DLL 摘要。原 E 盘 CMake 缓存已备份，补齐 Visual Studio C++ ATL 组件。普通 App 完整运行目录单独保存在 `windows-app/`。
- 上海 User Service 通过受管 prepare → verify-tests → deploy，release 为 `20261005T025940Z-4bfff82715a7`。发布前真实隔离数据库测试 **2500 passed / 8 skipped**；跳过项为未配置外部 URL 的既有 E2E，未跳过数据库发布验证。切换点数据库与头像文件备份恢复校验通过，公网和 loopback readiness 正常，schema 为 `202609280001`。Message/Gateway 业务进程未重启。
- Windows checkout 的冻结 SQL 基线最初因 CRLF 导致摘要检查失败，Linux 候选版本改用同一 Git 提交中的原始字节后重跑全量发布验证通过，没有修改冻结基线合同。
- `tests_v2/user_service/test_agent_avatars.py` 对真实 awiki.info **1 passed**，覆盖新预置动图、GIF 上传、匿名缓存读取、权限拒绝、CAS/重放、改名稳定性和恢复默认。Linux 头像运维测试 **5 passed**。
- 公网 64 个 PNG/GIF 与本地素材逐一 SHA-256 相等，32 个 GIF 均为多帧。
- Windows 直接 Flutter integration 流程最终 **1 passed**，run ID 为 `avatar-win-20261005-112839`；case attestation 为 real/passed，invocation completion 的失败数为 0。沿用独立 App 身份副本隔离普通 App 的单实例锁和凭证命名空间；真实 App Core 注册、真实后端，文件选择器使用既有测试夹具。该结果仅证明头像专项，不代表完整桌面 E2E 或系统认证验收。
- 测试通过 App 的正式 Inventory 端口签发注册令牌，辅助程序复用 System Test 的版本声明与 Manifest 构造。令牌只经 stdin 传递；收尾使用生产 `removeAgentFromAccount`，核对 active Inventory 与服务端状态。账号、归档记录和图片保留遵守环境策略，不扩大 System Test/Recovery 特权清理命名空间。
- 未配置真实 AI 动图生成 provider，本轮未验证真实生成质量和耗时。
- 最终清理复验：前次失败收尾留下的两个智能体已通过所属 App 恢复登录后，使用实际 ProviderScope 的已认证 Inventory 端口移除。清理专项 `flutter test integration_test/task_avatar_cleanup_test.dart -d windows --no-pub --reporter expanded --dart-define=AWIKI_E2E=true` 通过；服务端逐项复核最终 E2E 与前次业务成功尝试创建的四个智能体均已归档，active 数为 0。测试真人账号、归档行和不可变图片按环境保留策略处理；临时 V: 短路径映射已撤销。

### 2026-10-08 提交范围复验

- 从 Git 暂存区导出独立 App 源码，排除工作区其他任务的消息回复、删除和人工双窗口资料改动。头像 unit/widget、Inventory adapter、智能体 provider/layout、E2E catalog/artifact 契约共 **214 passed，失败 0**。命令：`flutter test --no-pub tests/unit/avatar tests/unit/data/agent/user_service_agent_inventory_adapter_test.dart tests/unit/agents/agents_provider_test.dart tests/unit/agents/agents_page_layout_test.dart tests/unit/e2e_harness/test_catalog_test.dart tests/unit/e2e_harness/app_artifact_spec_test.dart tests/e2e/test_catalog_contract_test.dart`。
- User Service 的 88 个暂存文件与 System Test 的 11 个暂存文件，均与 2026-10-05 已验证的部署源码快照一致（文本统一换行后比较，PNG/GIF 比较原始字节）。未重跑远端测试；沿用上述绑定源码的真实后端证据。
- 暂存区 diff 检查和新增源码凭据模式检查通过。验证记录位于 `verification-runs/agent-avatar-awiki-info-20261005/commit-review-20261008/`，未提交本地配置、构建产物或测试身份。
