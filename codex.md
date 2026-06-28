## Codex Notes

- 当 `awiki-me` 连接或联调的域名是 `awiki.info` 时，可以通过 SSH alias `ali` 连接对应服务器（`ssh ali`），用于服务端日志、后台服务、数据库和部署状态联调；不要在记录或回复中暴露密钥、JWT、私钥等敏感信息。
- 运行 awiki-me E2E 前必须先根据当前宿主平台选择配置：`uname -s=Darwin` 时使用 macOS 配置（例如 `tests/e2e/configs/e2e.codex-macos-allowed.local.yaml` 或其他明确 macOS 配置），不要使用默认 `tests/e2e/configs/e2e.local.yaml` 里的 Linux 配置；Linux 主机才使用 Linux 配置并检查 `xvfb-run`。
