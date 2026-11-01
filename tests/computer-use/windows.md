# Windows x64 同机双 App

本页是 playbook 的 Windows 准备与平台差异分支。公共 15 个 CU 用例、执行顺序、消息序列、名称与过程稳定性验收全部沿用；不能把 Windows 构建成功记成用例通过。

## 前置与构建

使用 Windows x64、PowerShell 7、Flutter、Rust x86_64-pc-windows-msvc、Visual Studio 2022 C++ 工具和 Windows SDK，安装 C++ ATL（安全存储及通知插件需要 `atlstr.h` / `atlbase.h`）。需要可用的 Python 3.10+、Git 和网络以执行 Core 的 registry 构建入口。真实系统认证使用 `local_auth`，需操作员在场；无法使用 Windows Hello 等系统认证时，相应用例记 `blocked`，不注入测试认证实现。

先按 [playbook 第 3 节](playbook.md#3-构建两个-app) 保存无秘密的 `build/computer-use/tenant.local.json`，然后在仓库根目录的 PowerShell 执行：

```powershell
./scripts/build_manual_dual_windows_apps.ps1 -TenantConfigPath ./build/computer-use/tenant.local.json
```

工作区提供 `activate.ps1` 时，先加载它，例如本机 `E:\awiki-space\activate.ps1`。脚本仅接受主槽 awiki.info、副槽 awiki.ai 的本套配置，启动后仍须在两窗口核对租户，再请求 OTP。

脚本输出 `build/computer-use/windows-<时间>/build.json`。它在该目录下复制当前工作区的 App 构建输入，分别生成 Admin/Joiner 源码副本；所有身份替换仅发生在副本，保留主工作区未提交改动。输出保留每端源码与 Debug 运行目录，以便复核身份差异。以 `lib/main.dart` 构建，不设置 `AWIKI_E2E`，不使用 fake secret 或 UserPresencePort，不运行 integration_test 入口。

Core 使用已有 Windows native 脚本和 registry 模式，记录 Core 仓库提交及最终 DLL 哈希；它的 Rust SDK 来源是固定的已发布 registry 依赖，不能把本地 sibling SDK 修改当成本次使用的依赖。App Dart wrapper 仍来自 sibling package。记录构建结果的 `status=built`，`prepared` 只代表完成副本准备，不代表可启动。`-PrepareOnly` 可检查身份副本，不编译或联网。

## 隔离合同

| 项目 | Admin | Joiner |
| --- | --- | --- |
| 窗口标题 | AWiki Me CU Admin | AWiki Me CU Joiner |
| ProductName | AWikiMeComputerUseAdmin | AWikiMeComputerUseJoiner |
| Credential Manager service | ai.awiki.awikime.dev.cu.admin.scope-secrets | ai.awiki.awikime.dev.cu.joiner.scope-secrets |
| Core support/cache | `%LOCALAPPDATA%\AWiki\AWikiMeComputerUseAdmin\support` / `cache` | `%LOCALAPPDATA%\AWiki\AWikiMeComputerUseJoiner\support` / `cache` |
| 临时根 | `%TEMP%\AWikiMeComputerUseAdmin` | `%TEMP%\AWikiMeComputerUseJoiner` |
| 窗口位置注册表 | `HKCU\Software\AWiki\AWikiMeComputerUseAdmin` | `HKCU\Software\AWiki\AWikiMeComputerUseJoiner` |

单实例 mutex、窗口类、激活/升级关闭 IPC、AppUserModelID 和 toast GUID 也分别隔离。`path_provider` 使用每个 EXE 的 CompanyName/ProductName，因此 tenant registry 和 App overlay 不会读取普通 App 或对端目录。凭证仍由原生 Credential Manager / DPAPI 保存，scope UUID、vault 校验和恢复逻辑不变。不得复制任何一端的身份目录、vault 或凭证给另一端。

这些应用身份固定，重新构建不清除登录状态。启动前按 playbook 检查身份归属，不能删除历史身份制造“干净”窗口。运行目录内 EXE、DLL 和 data 必须整体保留，不能只复制 EXE。制品只供本套 Debug 测试，不打包或发布。

## 启动、退出与隔离验收

使用脚本实际输出的 manifest 路径，禁止猜测某个旧运行目录：

```powershell
$build = Get-Content '<脚本输出的 build.json 绝对路径>' -Raw | ConvertFrom-Json
if ($build.status -ne 'built') { throw '双 App 尚未构建成功' }
foreach ($app in $build.apps) {
    Start-Process -FilePath $app.executable -WorkingDirectory (Split-Path $app.executable)
}
```

此处启动的是用户需要看见的两个测试窗口。先分别观察窗口标题、租户和登录状态，记录角色及 PID/EXE 路径。两个窗口必须同时存在。再次启动 Admin 应只激活原 Admin，不新增第三个进程、不激活 Joiner。对 Joiner 同样检查。不能只靠两个文件存在判断双实例隔离通过。

Windows 点击右上角 X 可能隐藏到托盘，不能作为离线或重启证据。要完全退出一端，使用该端托盘菜单 `Exit`；先根据标题激活确认目标，无法区分托盘项时不要盲点。必要时从非 UI 终端对 manifest 中该端 EXE 执行 `--shutdown-for-update`（既有受控退出入口），并确认该 EXE 对应进程已退出、另一端仍在运行，再发送离线序列。不要按 `AWikiMe` 进程名批量杀进程，也不要用“退出登录”代替关闭进程。

重启使用原 manifest 的同一 EXE。验收独立持久状态：A 注册后 B 仍停留在原登录状态；B 注册另一个 Handle 后两端保持各自身份；完全退出并重启某一端后身份不串线、另一端不受影响。任何一项失败都阻塞后续 Join/Recovery，保留现场。

## 用例平台映射

- CU-AUTH/NAV/MSG/CONTACT/GROUP/DISPLAY：按原步骤，在上述两个窗口中执行。`Command-Q` / `.app` 重开替换为本页的完全退出和同一 EXE 重启。复制粘贴使用 Ctrl-C / Ctrl-V，不沿用 macOS 快捷键。
- CU-JOIN-002、CU-JOIN-001、CU-MULTI-001、CU-RECOVERY-001/002/003：全部必测。系统认证交给真人，未完成或设备不支持时如实 `blocked`；不得自动填写 Windows PIN/密码、改安全设置或启用 E2E 绕过。Joiner 先作为外部 App B，随后加入 H；外部账号回访仍通过保留的本地凭证切换，不能省略。
- CU-DAEMON-001：当前方案的安装器是 POSIX `install.sh`、服务是 macOS LaunchAgent，仓库尚未提供对应 Windows 原生安装链。本轮 Windows 记 `blocked`，保留该用例，不执行 macOS 命令，不用 Git Bash/WSL 的安装成功冒充 Windows 安装通过。需要支持原生 Windows Daemon 时另行补齐产品安装和服务生命周期。
- 截图/附件的系统权限按实际 Windows 界面处理；不宣称 macOS 屏幕录制、Keychain、codesign 或 Touch ID 验证通过。权限操作由具备授权的人完成。

## 结果与收尾

按 playbook 第 7 节记录所有 15 项，包括七个必测重点。单独报告 Windows 适用项结果和整套未完成原因；CU-DAEMON-001 阻塞意味着原始 15 项整套不能宣称全通过。记录构建 manifest、平台、源码 dirty 状态、每项最后 UI 动作、超时和外部账号回访结果，截图脱敏。

仅退出本轮两个测试实例；保留凭证和业务数据，不动正常 App、其他进程或远端服务。本轮未安装 Daemon 时记录“未安装，无新增服务”，不要执行 macOS `service-uninstall`。App A/B 固定数据目录、Credential Manager 条目及远端测试资源按角色登记 residual；未操作的既有资源保持原状。
