# AWiki Me Computer-Use 测试

这是 AWiki Me 的第三类测试：给 **能看见屏幕、移动鼠标、输入键盘的 AI**（或按同样步骤操作的人）用的产品路径手册。

它回答的问题是：两个真实 macOS App 窗口里，用户点得到、发得出、看得到的路径通不通。它不替代 `tests/unit/` 或 `tests/e2e/`，也不宣称 CLI inbox、Core SQLite 或 case attestation 文件里的 oracle。

| 目录 | 回答的问题 | 谁执行 |
| --- | --- | --- |
| `tests/unit/` | Dart 逻辑对不对 | `dart run tests/unit/runner.dart` |
| `tests/e2e/` | App / CLI / backend 链路对不对 | `dart run tests/e2e/runner.dart` |
| `tests/computer-use/` | 看着屏幕点 App，产品路径通不通 | 读本目录的 computer-use AI 或人工 |

本目录 **没有** Dart runner，也 **没有** `--case computer-use`。不要把这里的 `CU-*` 登记进 `tests/e2e/suite_manifest.json`。

## 读什么

1. [playbook.md](playbook.md)：环境、OTP、双 App 初始状态、Daemon 安装与发布边界、等待规则、结果及残留记录
2. [config.example.yaml](config.example.yaml)：awiki.info 配置形状；真值只放本地或提示词
3. [acceptance.md](acceptance.md)：逐条消息、顺序、稳定性、名称及外部账号回访的公共验收规则
4. [selectors.md](selectors.md)：窗口名、中文文案、`e2e-*` semantics
5. [cases.md](cases.md)：每个用例点什么、输入什么、屏幕上期待什么

默认租户是 `awiki.info`。提示词如果给了别的租户、手机号、验证码或 Handle，以提示词为准。

## 第一版覆盖

当前共 15 个用例，覆盖注册/登录、主壳导航、单聊互发、关注联系人、名称显示、建群、安装 Daemon，以及重点多设备与 Handle Recovery 路径。

个人助理功能不在本套 computer-use 测试范围内。

**多设备与恢复是必测重点**：Join 拒绝与成功、加入后的同账号消息同步及重启追赶、设置恢复保留本地数据、旧设备失效与重新加入、无目标身份本地数据时的登录页恢复。按 [playbook.md](playbook.md) 的必测集合执行；任一重点用例 `failed / blocked / not-run` 都不能给出本套测试整体通过的结论。

名称专项 CU-DISPLAY-001 同样必测。所有消息相关用例都须按 acceptance.md 检查丢失、重复、乱序、气泡／列表闪烁、名称和身份；所有用例检查 App 闪退及无响应。多设备和恢复后的外部 App B 回访必须实际执行，不能只凭发送方双设备看到消息判成功。报告逐项记录结果，最终恢复正常也不能覆盖过程失败。

不改编：CLI peer 断言、performance、paging fixture、planned catalog。屏幕测试不宣称 Core 数据库、协议内部状态或精确故障注入的 E2E 结论。

## 本任务不执行测试

本目录是说明书。只有执行 computer-use 时才打开 App、发送验证码或安装 Daemon。默认验证已发布 Daemon；正式发布是另一项需要明确请求的操作，会更新正式渠道的 `latest`。

每轮按 playbook 记录 `passed / failed / blocked / not-run`，并单独记录资源收尾及残留。关闭 App 不会停止 Daemon；本目录也不会自动生成 Dart E2E 的 resource ledger。
