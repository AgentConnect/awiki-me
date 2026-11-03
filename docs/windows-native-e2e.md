# Windows 原生桌面 E2E

入口为 `scripts/run_windows_e2e.ps1`，在 Windows x64 上运行 owning
`tests/e2e/runner.dart`，保留相同 case ID 和业务断言。App、CLI、Daemon、
ConPTY 和离线 ACP 子进程均在 Windows 本机执行；User、Message、Realm 仍使用
明确配置的远程测试后端。WSL 或远程 Linux Daemon 不能替代本平台证据。

## 本机依赖与私有输入

需要 PowerShell 7、Git、Rust MSVC 工具链及 Windows SDK、Flutter/Dart、Node.js
和原生 Windows x64 Python。Python 必须通过 `-PythonBin` 或
`AWIKI_E2E_PYTHON_BIN` 指定真实 `python.exe`；不接受 Windows Store alias。
Flutter/Dart/Node 可复用工作区 `.tools/`。Rust 工具链以 Core 仓库为准。
全量中的 Agent 头像 fixture 使用 sibling `awiki-system-test` 的原生 Windows
`.venv/Scripts/python.exe` 及其锁定依赖；其私有 ledger 同样使用 NTFS ACL。
在该仓库执行 `uv sync --locked`；launcher 对 full/Agent 头像使用只读的
`uv sync --locked --check`，同时拒绝旧 SDK 和移动工作区后遗留的 editable 安装。
`uv.exe` 可复用工作区 `.tools/uv/`；检查不会自动改写环境或锁文件。
全量及包含 DSH 加入用例的 `multi-device-remote-join` 还需要 sibling `dsh-awiki` 的锁定 Node 依赖及
`pnpm.cmd`。先按其 dependency workflow 准备依赖；默认使用 registry，不能把
残留的 sibling SDK 链接当作正式依赖。Windows 入口会核对来源、加载本机原生
provider，并构建当前 DSH Host 后再执行产品用例；准备失败直接报错。

输入来自已审核、Git 忽略且仅当前用户/SYSTEM 可读的文件：

- `ConfigPath`：服务 origin/DID domain、测试账号及现有 runner 配置。
- `PinFixturePath`：Realm/PIN 用例的专用测试 fixture。
- `OtpPresetPath`：可选的受保护手机号/验证码预设；不放入命令行或报告。
- 全量额外需要 `RegistrationFixturePath`、`RegistrationDiscoveryFixturePath`、
  `HostedFixturePath`、`HostedPhoneFixturePath`；对应已有 owning fixture 合同。

入口当前只接受 `https://awiki.info` / `awiki.info` 主目标。它从当前已提交的
Core HEAD 构建并验证 Windows x64 CLI、probe、Daemon，检查 PE、版本和源码
SHA；校验当前 SDK DLL、绑定 hash 及源码摘要。离线 ACP fixture 使用独立
HOME/USERPROFILE，不调用真实模型 API 或个人安装的 Agent CLI。

## 执行

在本仓库根目录运行，例如：

```powershell
./scripts/run_windows_e2e.ps1 `
  -ConfigPath <private-config.yaml> `
  -PinFixturePath <private-pin-fixture.json> `
  -OtpPresetPath <private-otp-preset.json> `
  -PythonBin <native-python.exe> `
  -Case full -RunId <unique-run-id> `
  -RegistrationFixturePath <private-registration.json> `
  -RegistrationDiscoveryFixturePath <private-discovery.json> `
  -HostedFixturePath <private-hosted-email.json> `
  -HostedPhoneFixturePath <private-hosted-phone.json>
```

`-PrepareOnly` 只准备产物，不创建远程账号或启动测试 App；它不能作为通过证据。
定向复验使用既有 suite 名称，例如 `pin-recovery` 或
`multi-device-app-pair-functional`，不能代替 full。准备产物的来源、摘要与平台
仍由原有 manifest 校验；required 模式禁止静默回退到新构建。
Remote Join 可附加 `-CaseId DEVICE-JOIN-E2E-002` 定向复验；选择范围和依赖仍由
owning runner 校验，其他 suite 不因此获得跳过成员的入口。

提供原生 Python 3.13+ 时，既有 Windows 清理重试仍失败后会复用 Core 的
`scripts/testing/windows_file_lock_probe.py` 记录文件共享诊断。日志只含类别、数量及
是否截断，不读取内容或打印路径；辅助进程不继承业务/模型凭据，超时终止本次 helper。
原清理失败继续失败，不扩大删除范围、不延长重试，也不重写保留的历史日志。

NTFS ACL 代替 POSIX `chmod`。CLI 子进程保留 Windows DNS 所需的 `SystemRoot`，
并将 USERPROFILE、临时文件和 AppData 指向测试 HOME。交互 CLI 使用本仓库
固定版本 ConPTY 桥接；终止时仅清理本轮拥有的进程树。
构建快照保留 E2E 引用的共享 unit fakes，并遵守 Git 忽略规则。绝对可执行文件
直接检查文件，不交给 Windows `where` 解析；Windows 系统工具使用系统编码，
CLI 等结构化输出继续严格验证 UTF-8，解码失败写入报告并执行清理。
CLI 子进程的启动、超时、编码和管道失败记录固定类别、超时长度及系统错误码，
便于区分 Windows 环境故障和服务端拒绝。
未完成的 CLI Join/Root Transfer 保留受保护的包装 key 以便检查原状态；Windows
同样使用 NTFS ACL，保留失败不会降级权限，也不会为旧状态创建替代 key。
重启、崩溃续办与身份删除续办的独立阶段产物，保留同一逻辑设备的测试 secret
service，以重开原始加密状态；窗口身份遵循各阶段的 bundle ID。
Hosted Join/Resume 沿用其原本相同的 bundle ID。
并发 Admin/Joiner 使用不同服务，所有测试服务均与普通客户端命名空间分离。
Windows 运行状态使用 `.e2e/ws/<scope-run-hash>/` 及短角色目录，报告仍保留原有
suite/run 路径。工作区过深时仅选择当前用户的短 TEMP 根；两个位置都无法给
SQLite 备份名留足空间时提前报错。实际状态根继续设置私有 NTFS ACL，并写入
原有私有资源记录；不会移动或删除旧运行的状态和备份。
Windows 构建复用 `local_auth_windows` 自身固定 URL/SHA-256 的 NuGet 可执行文件，
缓存位于工作区 `.tools/nuget/<sha256>/`；每次使用均校验摘要，避免每个隔离产物
重复下载相同工具。包版本、TLS 与哈希验证保持原有约束。
本版本固定的 WIL/CppWinRT Microsoft 包也以记录的 SHA-256 保存在本机 feed；
生成快照的 `NuGet.Config` 仅使用该 feed，机器和用户的 NuGet 配置不变。
SQLite 源码使用锁定插件中固定的下载 URL，缓存包和编译所需源码的摘要并逐次
核对；生成快照通过 CMake 的 SQLite source override 复用这些相同字节，减少
隔离产物重复下载。该插件本身未提供上游 archive hash，缓存记录不冒充上游签名。
生成快照中的 CMake install prefix 始终固定为自身 runner 目录；中断后重用缓存
也不沿用 Program Files 默认安装位置。实际项目的发布 CMake 文件保持原有行为。

## 服务端与专用 fixture

必须先按服务 owner 的运维合同准备 scoped OTP、设备/Recovery allowlist、有限
注册配额及测试算子。Windows launcher 不自行扩大这些后端权限，也不恢复或复用
其他运行的临时配置。临时窗口应保存原始值，并在成功、失败时都恢复和核验。

`full` 和 `pin-recovery` 在构建前检查公开 Realm 配置接口是否可用；过期配置、
重定向、超时或无效响应直接失败。该检查仅确认可用性，App/Core 继续执行原有
固定公钥验签和配置验证。配置过期应由服务 owner 按 User Service 的续签工具和
受管生命周期处理，不能跳过到期检查或重新生成已有节点的密钥和配置投影。

主目标使用 SSH alias `ali`。Hosted Gateway 用例继续固定访问隔离实例
`mcp-adapt.anpclaw.com`，其 OTP operator 使用 `singapore-dev`；两者不能互换。
SSH alias 必须有已核实的严格 host key、正确用户及身份文件。

`dart run tool/prepare_windows_hosted_gateway_fixture.dart <run-id>` 可在 Windows
本机准备该固定实例的合成邮箱身份及手机号 fixture。输出仅含私有文件路径；
远程仅运行已有 OTP 算子。失败保留 intent，先检查失败原因；需要续办时使用同一
run ID 加 `--resume`，沿用原 operation ID，并验证 task ID 不变。成功后保留
隔离 Gateway 身份/设备恢复材料，不声称零残留。

短 Handle 邀请与客户域能力发现依然由各自 fixture owner 准备，必须与当前部署的
数据库和接口匹配。缺 fixture、权限、算子或编译资产属于失败/未运行，不能转成跳过。

## 证据边界

full 保留全部 114 个 case ID；Windows 必须声明全部可移植成员 suite，矩阵缺项
直接拒绝。`did-method-web` 按用户已有决定记录为 `user_excluded`；签名 macOS
Keychain 专属 `NATIVE-E2E-002` 为平台不适用，不能描述为 Windows 凭据验收。

报告使用 `.e2e/<scope>/<run-id>/reports/`，原始日志、状态、私有配置与构建产物
保留在忽略目录。正式交付按 Verification Policy 导出脱敏 HTML 到
`html-docs/test-reports/`，提供 awiki.info HTTPS 链接。编译、unit、prepare-only
和定向通过都不能表述为 Windows 全量通过；以实际 full 报告和 case attestation 为准。
