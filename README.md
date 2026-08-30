# RecoDex Mobile

`recodex-app` 是 [`codex-relay-plugin`](../codex-relay-plugin) 的 Flutter
移动端。手机端不运行 Codex，也不访问电脑文件；它通过 Relay 向已认证的
Codex 主机发送命令，并接收会话列表、流式事件和执行结果。

## 实际架构

```text
Flutter App (endpointType=app)
        │  WSS /v1/connect
        ▼
Relay (只做 Space 隔离与盲转发)
        ▲  WSS /v1/connect
        │
Codex Relay Plugin (endpointType=bridge)
        │  stdio JSON-RPC
        ▼
Codex App Server → 本机工作区
```

移动端和插件都主动连接同一个 Relay。Relay 不理解 `codex.v1` 的业务
payload，也没有旧版本地 Bridge、`/pairing` 或 `/ws` 协议。

## 通信协议

连接地址必须是：

```text
wss://<relay-host>/v1/connect
```

本机调试可以使用 `ws://127.0.0.1:8788/v1/connect`。公网地址禁止使用明文
`ws://`。

### 认证首帧

WebSocket 建立后，App 发送唯一的 `connect.hello`。Connect Token 只出现
在首帧，Endpoint 私钥只保存在 Flutter 安全存储中：

```json
{
  "version": 1,
  "type": "connect.hello",
  "requestId": "hello_xxx",
  "spaceId": "studio-mac",
  "endpointId": "app_xxx",
  "endpointType": "app",
  "endpointName": "My phone",
  "token": "short-lived-connect-token",
  "endpointProof": {
    "algorithm": "Ed25519",
    "publicKey": "<raw-public-key-base64url>",
    "issuedAt": 1735689600000,
    "nonce": "<random-base64url>",
    "signature": "<canonical-proof-signature-base64url>"
  },
  "capabilities": ["streams", "ack", "opaque-payload", "codex.v1"]
}
```

签名内容严格为：

```text
relay-connect-v1
<version>
<requestId>
<spaceId>
<endpointId>
<endpointType>
<token>
<issuedAt>
<nonce>
```

Relay 返回 `connect.welcome` 后，App 才能发送业务帧：

```json
{
  "version": 1,
  "type": "connect.welcome",
  "requestId": "hello_xxx",
  "connectionId": "connection_xxx",
  "sessionId": "session_xxx",
  "spaceId": "studio-mac",
  "endpointId": "app_xxx",
  "maxFrameSize": 10485760,
  "features": ["directed-routing"]
}
```

### Codex 业务帧

业务消息统一放在 `stream.message.payload`，App 发给插件的命令如下：

```json
{
  "version": 1,
  "type": "stream.message",
  "messageId": "msg_xxx",
  "streamId": "codex",
  "sequence": 1,
  "to": "host_xxx",
  "protocol": "codex.v1",
  "encrypted": false,
  "payload": {
    "type": "codex.command",
    "requestId": "request_xxx",
    "spaceId": "studio-mac",
    "deviceId": "app_xxx",
    "targetDeviceId": "host_xxx",
    "timestamp": "2026-08-30T00:00:00.000Z",
    "command": {
      "type": "host.get_status"
    }
  }
}
```

插件返回 `codex.command.result`，并使用相同的 `requestId` 关联请求。Codex
流式事件使用 `codex.event`，其中包含 `threadId`、`turnId` 和标准化事件：
`thread.created`、`turn.started`、`message.assistant.delta`、
`tool.output`、`turn.completed`、`turn.failed`、`turn.interrupted` 等。

Relay 自动发送的 `stream.ack` 只表示已接收；App 还会对收到的业务序列发送
带目标的 ACK，并用 `messageId` / `requestId` 去重。断线后 App 发送
`sync.request`，由插件的事件缓冲或当前 Codex 状态恢复界面。

当前支持的插件命令：

- `host.get_status`
- `sync.request`
- `thread.list`
- `thread.read`
- `thread.create`
- `thread.resume`
- `thread.select`
- `turn.start`
- `turn.steer`
- `turn.interrupt`
- `approval.respond`

Git、设备列表和旧版 Bridge 命令不属于当前 `codex.v1` 合约，不会发送未知
消息来“兼容”它们。

## 配置与连接

1. 在 Relay 控制台登记一个 `app` Endpoint，复制 App 生成的 Ed25519 公钥。
2. 创建一个绑定该公钥的 Connect Token；记录 `spaceId`、Endpoint ID、Token
   和目标插件的 `deviceId`。
3. 在插件 Dashboard 配置同一 Relay 地址和 Space，并使用
   `endpointType=bridge` 的主机 Token。
4. 在 App 的“配对”页面填写 Relay 地址、Space ID、目标 Codex 主机 Endpoint、
   本机 App Endpoint ID 和 App Connect Token。
5. 如果控制台同时签发 Endpoint Grant，也可以填写它；Token 到期后 App 会用
   Endpoint 私钥调用 `/api/connect-tokens/refresh` 自动续期。

插件的主机 `deviceId` 可以从 Dashboard 的连接配置或 Relay 控制台获取；它
必须与 App 命令中的 `targetDeviceId` 完全一致。

## 开发与验证

```bash
flutter pub get
flutter analyze
flutter test
```

有真实 Relay、插件和已签发凭证时，可运行跨端 smoke：

```bash
flutter pub run tool/bridge_smoke.dart \
  --relay=wss://relay.example.com/v1/connect \
  --space=studio-mac \
  --token=<app-connect-token> \
  --endpoint=<app-endpoint-id> \
  --target=<plugin-endpoint-id> \
  --seed=<app-ed25519-private-seed-base64url>
```

Smoke 会验证 `connect.hello -> connect.welcome -> host.get_status` 的真实
Relay/插件链路。没有真实 Relay、插件进程和有效 Token 时，源码检查不能替代
这项网络及认证验证。
