# AWiki Me E2EE plugin contract

`AWiki Me` 不在 Dart 层直接实现 awiki E2EE 协议。

未来真实插件至少需要暴露以下接口：

- `initialize(identity)`
- `ensureSession(peerDid)`
- `encryptOutgoing(peerDid, originalType, plaintext)`
- `processIncomingProtocolMessage(message)`
- `decryptIncomingMessage(message)`
- `exportSessionState()`
- `importSessionState(state)`

验收标准：

- 与 Python awiki 客户端完成双向互发。
- `e2ee_init / e2ee_ack / e2ee_rekey / e2ee_msg / e2ee_error` 语义一致。
- `session_id / send_seq / recv_seq / expires_at` 持久化语义一致。
