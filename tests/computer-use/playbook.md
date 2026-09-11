# Computer-Use 操作手册

给准备点 AWiki Me 的 AI 读。默认环境是 `awiki.info`。本文件不执行测试，只规定怎么准备、怎么点、怎样算停。

## 1. 适用主机

第一版只覆盖 **Intel macOS 桌面双窗口**。

- 双 App 脚本 `scripts/build_manual_dual_macos_apps.sh` 要求 `uname -s == Darwin` 且 `uname -m == x86_64`
- 不要把 Linux/Xvfb 的 `dart run tests/e2e/runner.dart` 步骤写成 computer-use 动作
- 不要打开 `.e2e/build-cache/` 里的隔离制品；那些给 E2E runner 用，手工打开会黑屏

需要两台测试身份时，用 Admin / Joiner 两个不同 bundle 的 Debug App，而不是同一个 `.app` 开两次。

## 2. 配置

模板：[config.example.yaml](config.example.yaml)。形状对齐 `tests/e2e/configs/e2e.example.yaml`。

### 2.1 解析顺序

1. 提示词里的租户、手机号、验证码、Handle、daemon 地址
2. 本机 gitignore 文件 `tests/e2e/configs/*.local.yaml` 的 `service` / `otp` / `accounts`
3. 本目录 `config.example.yaml` 只提供形状，**不能拿它的占位符去登录**

三者都缺关键字段时停下来问，不要猜。example 里的 `+8610000000000` / `000000` 不是可登录账号。

本次默认：

```text
https://awiki.info
wss://awiki.info/im/ws
didDomain: awiki.info
daemon: https://awiki.info/daemon/install.sh
```

### 2.2 OTP

awiki.info 测试部署可为 `DEV_OTP_PHONE` / `DEV_OTP_CODE` 配成对预设。手机号精确命中时：

- 注册、普通 Join、Handle Recovery 仍调用真实 SMS API
- 服务端跳过随机码和外部短信，校验固定六位码
- 必须先点「发送验证码」，再填码；不能跳过发送
- 发码前先填好手机号和目标 Handle；OTP 绑定这两个输入。发码失败不能以“界面不再转圈”当成成功，发码后也不要改成另一个 Handle

真值只留在受保护本地配置。报告、截图、聊天记录里不要出现完整手机号和验证码。

登录页手机号输入框左侧已经显示 `+86`。把本地 YAML 的 E.164 去掉 `+86` 前缀后再输入。例如配置是 `+8610022229999` 时，框里只打后面的数字。设置内「恢复 Handle DID」的手机号框没有此前缀，须填写配置中的完整 E.164 手机号。

验证码冷却中按钮会变成「重新发送（Ns）」。冷却未结束不要连点。

### 2.3 Handle

双窗口互发、联系人、建群用 **两个不同 Handle**（App A / App B）。

加入设备用 **同一个 Handle**（Joiner 是 App A 的第二台设备）。不要拿已经登录了第二个 Handle 的 Joiner 去做 Join。

每次 computer-use 注册用新的小写 Handle，避免和 E2E 账号池抢身份。建议：

```text
cu<MMDD><role><HHMM>
```

例如 `cua09051132`、`cub09051132`。若提示词要求复用 `e2e.local.yaml` 的 `appUser` / `cliPeer`，先说明会污染自动化账号池，再继续。

### 2.4 多设备与恢复的必测边界

本手册中的“恢复”包含两部分：同一 App 本地数据下重启后的消息追赶，以及更换 DID 的 Handle Recovery。六个多设备／恢复重点用例为 CU-JOIN-002、CU-JOIN-001、CU-MULTI-001、CU-RECOVERY-001、CU-RECOVERY-002、CU-RECOVERY-003；名称专项 CU-DISPLAY-001 同样必测。这七个用例均须列入每轮整套执行计划，不能因 Touch ID、环境缺失或前序失败从报告中删掉。

- 主链使用 App A 的新 Handle H、独立通信对象 App B 的 Handle，以及同一 Joiner 上随后加入 H 的第二台设备。先完成 App B 的基础消息和群准备，再退出 App B 进入 Join；不能把两个不同 Handle 的互发冒充同账号多设备同步。
- CU-RECOVERY-001 从已登录 App A 的设置发起，保留同一 bundle、Application Support 和本机凭证；恢复前不能退出或删除 H 的数据。CU-RECOVERY-002 紧随其后，在仍持有旧授权的 Joiner 上观察失效、再加入。
- CU-RECOVERY-003 单独使用新的测试 Handle Hf，例如 `cuf09051132`。在 App A 注册 Hf，在从未保存 Hf 本地身份的 Joiner 上通过登录页恢复；不得用删除 H 的历史来模拟这条路径，也不在主链 H 上连续恢复第二次。
- Joiner 必须保留原 App B 和加入／恢复后的 H 本地凭证。按 [acceptance.md](acceptance.md) 回访流程临时退出当前测试身份，再从登录页「切换身份」选择完整 Handle 对应的现有凭证；不能新注册或恢复账号来替代切换，也不需要第三个 App。CU-RECOVERY-003 的 Hf 与 App B 则在同一 Joiner 上顺序切换收发。
- Recovery 会更换目标 DID，并使该 Handle 的旧设备授权失效。只使用本次创建且归属明确的测试 Handle。已明确要求执行这些恢复用例时，按其风险确认步骤继续；归属不明或没有真人完成系统认证时记 `blocked`。
- 注册 OTP 与 Recovery 专用 OTP 分开请求。登录页选择「恢复 Handle」后通常自动请求恢复验证码，先确认恢复专用发码成功再输入；设置入口则先输入完整手机号、主动发码。固定测试码的数字相同也不能省略第二次请求。
- 基准只包含普通 Direct 和 Handle 群。设置恢复检查已有普通本地历史保留；无目标本地数据的恢复不要求找回恢复前 Direct 历史。旧 E2EE 私钥、E2EE 群、DID-only 群和 Root 管理权转移不作为这些用例的通过条件。

Recovery 提交及收尾每阶段最多 120 秒，普通发码和资格验证仍按 30 秒。遇到“远端结果仍在确认中”或可继续状态，只使用当前页面的「继续恢复」，120 秒预算内最多手动重试两次；若已显示恢复完成但未进入主壳，只点「继续进入消息」。不要重发起恢复、删除目录或点「开始新的恢复」掩盖未知结果。超时保留页面和数据，记录失败及未确认的远端状态；不把恢复状态未知的账号当成已清理。

## 3. 构建两个 App

当前双 App 脚本读取完整的两槽租户 JSON，使用 `AWIKI_TENANT_CONFIG_PATH`；旧的 `AWIKI_PRIMARY_TENANT_DOMAIN` 已不生效。仓库默认 JSON 的主槽为 `awiki.me`，不能直接用默认配置执行本手册的 `awiki.info` 测试。

在 `awiki-me` 仓库根目录创建 `build/computer-use/`，将以下无秘密配置保存为 `build/computer-use/tenant.local.json`。两个槽位都必须提供且域名不同；本轮只选择主槽 `AWiki info 测试`，副槽保留官方定义但不用于本轮测试：

```json
{
  "schema_version": 1,
  "default_slot": "primary",
  "tenants": {
    "primary": {
      "display_name": { "zh-CN": "AWiki info 测试", "en": "AWiki info Test" },
      "backend_origin": "https://awiki.info",
      "did_host": "awiki.info"
    },
    "secondary": {
      "display_name": { "zh-CN": "AWiki 全球（硅谷）", "en": "AWiki Global (Silicon Valley)" },
      "backend_origin": "https://awiki.ai",
      "did_host": "awiki.ai"
    }
  }
}
```

然后构建：

```bash
AWIKI_TENANT_CONFIG_PATH="$PWD/build/computer-use/tenant.local.json" \
  scripts/build_manual_dual_macos_apps.sh
```

脚本会：

1. 校验 / 重建 sibling `../awiki-cli-rs2` 的 x86_64 `awiki_im_core`
2. 用 `lib/main.dart` 编两个 Debug macOS App，将同一租户 JSON 及 SHA-256 通过 Dart define 注入
3. 校验 bundle ID、架构、codesign，并输出租户配置摘要；启动后仍须在两个窗口核对当前选择为 `awiki.info`，再发送 OTP

产物：

| 角色 | 窗口显示名 | Bundle ID | 路径 |
| --- | --- | --- | --- |
| App A / Admin | `AWikiMe (Development)` | `ai.awiki.awikime.dev` | `build/macos/Build/Products/Debug/AWikiMe.app` |
| App B / Joiner | `AWikiMe Joiner` | `ai.awiki.awikime.dev.manual.joiner` | `build/manual-multi-device/AWikiMe-Joiner.app` |

启动：

```bash
open -n 'build/macos/Build/Products/Debug/AWikiMe.app'
open -n 'build/manual-multi-device/AWikiMe-Joiner.app'
```

两个 bundle 有各自的 Application Support，这就是测试双方。把窗口并排放，始终看窗口标题再点。

### 3.1 初始登录状态与复跑

两个 bundle ID 固定；重新构建、`open -n` 或关闭窗口都不会清空本地身份。每次运行先检查两个窗口的当前租户及登录状态，并在本次记录中标明 App A / App B 的角色。

- 已在登录页：确认没有误选历史身份，再填写本次新 Handle。
- 已登录本次测试拥有的旧身份：从「设置」→「退出登录」→ 确认退出，看到「登录或注册」后再开始。退出保留本机凭证，不等于删除本地或远端数据。
- 已登录其他人的身份或无法确认归属：该窗口相关用例记 `blocked`，保留现场；不要为了得到登录页删除本机凭证。
- CU-JOIN-001 使用同一 Joiner 时，先完成 App B 的消息用例并记录结果，再按上述退出路径回到登录页。这里的“干净 Joiner”指没有活动登录会话，并非擦除数据目录。

缺少 Flutter、Intel macOS 或 `awiki-cli-rs2` native Core 时，按脚本报错停。不要改去跑 `tool/build_isolated_e2e_app.dart`。

## 4. macOS Daemon

crate 名是历史拼写 `awiki-deamon`。App 安装 UI 下载的也是这个名字。

### 4.1 本机 Debug 编译

给同一台 Mac 上直接跑 daemon 进程：

```bash
cd ../awiki-cli-rs2
cargo build -p awiki-deamon --locked --bin awiki-deamon
```

产物：`awiki-cli-rs2/target/debug/awiki-deamon`。

本地开发命令见 `awiki-cli-rs2/crates/awiki-deamon/docs/local-dev.md`。computer-use 的 CU-DAEMON-001 优先走 App 复制出来的 `install.sh`，而不是手工 `foreground`，除非提示词只要本机进程。

### 4.2 Darwin 发布包

```bash
cd ../awiki-cli-rs2
scripts/release/daemon/_build-artifact.sh --os darwin --arch amd64
```

Apple Silicon 用 `--arch arm64`。产物默认：

```text
dist/daemon/awiki-deamon-darwin-<arch>.tar.gz
```

### 4.3 默认验证已发布版本

App 的安装 URL 来自租户 `daemonDownloadBaseUrl`，awiki.info 默认是：

```text
https://awiki.info/daemon/install.sh
```

命令形状（token 来自 App 当场签发，不要写进报告）：

```bash
curl -fsSL 'https://awiki.info/daemon/install.sh' | \
  AWIKI_DAEMON_BASE_URL='https://awiki.info' \
  AWIKI_DAEMON_DOWNLOAD_BASE_URLS='https://awiki.info/daemon' \
  sh -s -- --token '<token>'
```

CU-DAEMON-001 默认安装该地址已经发布的版本。安装前记录公开 manifest `https://awiki.info/daemon/releases/manifest.json` 的版本及可取得的源码来源，安装后核对 App 显示的版本；无法确认源码来源时写“未确认”，不要把本机 checkout 的提交当作安装包来源。

4.1 的 Debug 二进制和 4.2 的本地产物不会因执行 App 安装命令而被使用。若任务要求验证某个候选版本，必须先确认下载渠道已经提供对应版本及源码提交；没有对应制品时记 `blocked`，不能用其他版本代替，也不能自动发布正式渠道。

### 4.4 仅在明确要求正式发布时执行

以下是独立的正式发布操作，不属于 computer-use 的默认准备步骤。在实际托管 `/var/www/awiki-web/daemon` 的服务主机上执行，不是在测试用 Mac 上执行：

```bash
cd ../awiki-cli-rs2
scripts/release/daemon/publish-multi-platform.sh
```

该脚本无参数。服务主机须按同目录 `publish-multi-platform.toml.template` 准备受保护的 `publish-multi-platform.toml`；不要把其中 GitHub token 写进命令或报告。脚本根据配置的 `source_ref` 触发 GitHub Actions，下载构建产物并发布到本机 `/var/www/awiki-web/daemon`，不会上传测试 Mac 上刚编译的包。

**该脚本会直接替换正式安装脚本和 manifest，并更新 `latest`，无需也不接受 `--promote-latest`。** 只有已有明确的正式发布授权才执行。`base_url` 必须和签发 registration token 的 user-service 域名一致，awiki.info 就是 `https://awiki.info`。发布与后续安装记录须能对应：配置的 source ref、实际构建提交、发布版本、App 最终显示的安装版本；来源不能对应时，不宣称候选版本通过。

`awiki-cli-rs2/AGENTS.md` 还记载了联调脚本 `scripts/release/daemon/publish-local-nginx.sh`，对外地址 `https://awiki.info/daemon-local`。**当前仓库树里没有这个文件。** computer-use 默认走正式 `/daemon`。只有提示词明确要求联调通道，并且执行环境里该脚本真实存在时，才用 `/daemon-local`。

### 4.5 安装前检查本机已有 Daemon

App 两个 bundle 的隔离不延伸到 Daemon。安装默认使用 `~/.awiki-daemon/deamon/state` 和 `~/Library/LaunchAgents/ai.awiki.deamon.plist`，更新用户级二进制及固定服务 `ai.awiki.deamon`，并重启该服务；仅改 state root 不能证明服务隔离。

执行 CU-DAEMON-001 前，检查这些路径是否已有安装、固定服务是否已注册，并记录 App A 智能体列表的基线。只检查归属、路径和运行状态，不输出配置中的秘密。

- 默认使用没有已有 Daemon 安装的专用 macOS 测试用户。
- 如果已有安装且未明确授权复用或更新，CU-DAEMON-001 记 `blocked`；不要覆盖、停止或删除它。
- 已明确授权复用或更新时，在执行前记录原安装的归属、版本、运行状态、受保护备份位置和恢复步骤；无法恢复则记 `blocked`。将此轮标注为“已有安装更新”，不能作为全新安装通过证据。
- 安装失败也必须登记已经创建的目录、服务或远端条目，并执行第 7 节收尾。

## 5. 点 UI 的规则

- 界面语言跟系统走，中文系统默认简体。本手册按中文文案写；英文系统对照 [selectors.md](selectors.md)
- 先点看得见的中文按钮。同时记下 `e2e-*` semantics，方便以后接 accessibility
- 每个点击或输入后等界面稳定：本地切换 2–5 秒，网络动作默认最多 30 秒；用例明确给出的专属超时优先。Join 按阶段计时，需要切换窗口操作，不是在 Joiner 上被动等完整流程。真人系统认证期间记 `blocked`，不计入网络超时
- 两个窗口始终看标题。Admin 是 `AWikiMe (Development)`，Joiner 是 `AWikiMe Joiner`
- 失败即停，留下最后一屏的窗口标题、可见文案、刚做的一步。不要为了绿而换账号、跳过 OTP、或点系统「以后」
- 截图或短录像打码手机号、OTP、两端 SAS 六位码、token、完整 DID、安装命令里的 `--token`；只记录“两端一致 / 不一致”，不保存 SAS 数字
- 系统「屏幕与系统音频录制」里授权的是 `AWikiMe (Development)` / `AWikiMe Joiner`，不是正式 Release `AWikiMe`
- 本机用户在场（Touch ID / 登录密码）computer-use 过不了就记阻塞，不要把 E2E 的测试 UserPresencePort 当成产品能力
- 无论通过、失败还是阻塞，都按第 7 节记录结果并收尾；关闭窗口不会停止 Daemon
- 每个消息检查点执行 [公共验收规则](acceptance.md)：逐条编号及顺序核对、到齐后至少 10 秒观察、返回列表重开，以及用例要求的重启后复查。昵称已知时不得把 Handle/DID 回退视为等价成功；任何可见闪退、气泡消失／重复／错序或名称串线，最终恢复正常也不能覆盖失败

## 6. 推荐执行顺序

1. 构建并并排打开两个 App，完成初始登录状态检查
2. [CU-AUTH-001](cases.md#cu-auth-001) App A 注册
3. [CU-AUTH-002](cases.md#cu-auth-002) App B 注册另一个 Handle
4. [CU-NAV-001](cases.md#cu-nav-001) 主壳
5. [CU-MSG-001](cases.md#cu-msg-001) 单聊互发
6. [CU-CONTACT-001](cases.md#cu-contact-001) / [CU-CONTACT-002](cases.md#cu-contact-002)
7. [CU-GROUP-001](cases.md#cu-group-001)
8. **必测** [CU-DISPLAY-001](cases.md#cu-display-001)：无昵称回退、改名、跨页面一致性及重启；保存 Na/Nb 名称基线
9. 完成安装基线检查后，在 App A 执行 [CU-DAEMON-001](cases.md#cu-daemon-001)
10. **必测** [CU-JOIN-002](cases.md#cu-join-002)：未登录 Joiner 发起请求，App A 拒绝，验证未获授权
11. **必测** [CU-JOIN-001](cases.md#cu-join-001)：同一测试 H 重新发起新的请求并完成加入
12. **必测** [CU-MULTI-001](cases.md#cu-multi-001)：同账号消息、加入前边界与重启追赶，必须完成 App B 外部账号回访
13. **必测** [CU-RECOVERY-001](cases.md#cu-recovery-001)：App A 设置恢复 H，检查本地普通消息序列、名称和稳定性
14. **必测** [CU-RECOVERY-002](cases.md#cu-recovery-002)：Joiner 失效及重新加入，必须回访 App B 检查恢复后的实际收发和原联系人／会话
15. **必测** [CU-RECOVERY-003](cases.md#cu-recovery-003)：新 Hf 的登录页恢复，必须在 Joiner 上切换 App B 完成实际收发和名称核对

每个用例的字段含义见 [cases.md](cases.md)。

## 7. 结果记录与收尾

每次执行用一个唯一 run ID，在 gitignore 的 `build/computer-use/<run-id>/` 保存脱敏记录。记录时间、租户、平台、App/Core 构建来源、Daemon 安装版本及来源、App A/B 角色，以及每个 CU 用例的状态、最后步骤、可见结果、耗时和证据位置。来源不明就明确记录，不用工作区 HEAD 代替实际制品来源。

| 状态 | 含义 |
| --- | --- |
| `passed` | 已执行全部步骤，所有可见预期均满足 |
| `failed` | 前置满足后执行出现错误、断言不符或超时 |
| `blocked` | 前置、资源归属或真人系统认证条件不满足，无法继续 |
| `not-run` | 未执行；注明未选择或依赖用例未通过 |

失败时停止当前用例，不执行依赖它的用例；不依赖失败项且前置已满足的已选用例可以继续。保留首次失败记录；另一次重试单独记录，不能换账号后覆盖失败结果。

报告单列六个多设备／恢复重点及名称专项的结果，按 acceptance.md 分别记录完整性、唯一性、顺序、气泡／列表稳定性、名称／身份、App 稳定性，以及外部回访实际收发结果。只有所有已选用例、七个必测重点及其适用公共检查均为 `passed`，才可报告整套通过；必测 `blocked / not-run` 说明验证未完成，不能用基础消息或同账号同步通过代替。按每次 Recovery 的角色记录 Handle 是否保留、DID 是否变化、旧设备是否失效、是否成功重新加入；完整 DID 只现场比较，报告使用比较结果和角色代号。

本目录不运行 Dart runner，因此不会自动生成 E2E resource ledger。每创建或改变一项资源，就在本次脱敏记录中登记其角色、所属用例、是否本次新建、收尾动作和结果；涵盖账号及昵称变更、群、关注关系、加入设备及 Daemon 服务。测试昵称在多设备和恢复检查结束前保留，收尾记录最终值或恢复结果。共享报告使用角色代号；精确定位所需的敏感信息仅保存在受保护本地记录中。

1. 仅当安装前基线证明没有已有服务、当前服务确为本次新建时，在终端执行下面的既有管理命令，取消其自启动注册并检查状态。它只处理本机服务，保留安装文件、状态目录和远端资源；此项是环境收尾证据，不是产品用例的 CLI oracle。

   ```bash
   "$HOME/.awiki-daemon/deamon/bin/current/awiki-deamon" service-uninstall
   "$HOME/.awiki-daemon/deamon/bin/current/awiki-deamon" service-status
   ```

   确认服务不再安装、运行；命令失败或仍运行就记录收尾失败。对于明确授权更新的已有安装，执行安装前约定的恢复步骤并核对原版本及运行状态，不能套用上述卸载命令。若用户明确要求保留测试服务，按要求保留并记录运行状态。
2. 默认保留远端账号、群、关注关系、已加入设备和本地测试数据，逐项标为 `residual` 并写明原因。若用户要求清理，使用既有的、与精确测试资源对应的操作流程；没有可用清理路径就登记未完成，不把本地退出或服务卸载当成远端清理成功。
3. 记录两个窗口最终登录状态，再关闭测试窗口。需要退出时仅对本次测试身份使用「退出登录」，不为清场删除其他身份的凭证。

用例状态和收尾状态分别报告。可见步骤通过但有残留时，必须同时报告残留；收尾失败不能写成“全部完成且无残留”。
