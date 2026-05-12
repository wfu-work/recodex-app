# Remote Codex Companion

一个自用的 Remodex 类工具，用 Flutter 做移动端，用 Go 做本机桥接服务，让手机可以安全地远程操作电脑上的 Codex CLI / Codex App 工作流。

这个项目的目标不是重新实现完整的 Codex App，而是做一个轻量、可控、自己能部署的远程控制器：真正读写代码、运行命令、访问本地仓库的能力仍然发生在自己的电脑上，手机端只负责发起任务、查看流式输出、管理会话和执行少量确认操作。

## 项目目标

- 手机端远程连接自己的 Mac / Linux 工作机。
- 在手机上选择项目目录、发送 prompt、查看 Codex 流式响应。
- 支持中断、继续、查看历史会话。
- 支持基础 Git 操作，例如 status、diff、commit、push 确认。
- 支持二维码配对和本地密钥保存。
- 优先支持局域网使用，后续再扩展公网 Relay。
- 尽量使用稳定、简单、可维护的技术栈。

## 非目标

- 不做完整 Codex App 替代品。
- 不在手机端直接运行 Codex 或执行代码。
- 不把用户仓库上传到自建服务器。
- 不依赖未确认稳定的私有协议做重度封装。
- 第一版不追求多人协作、插件系统、云端任务队列或复杂权限模型。

## 技术栈

### 移动端

- Flutter
- Dart
- WebSocket / HTTP
- flutter_secure_storage
- qr_code_scanner 或 mobile_scanner
- provider / riverpod / bloc 任选其一

### 本机 Bridge

- Go
- net/http
- gorilla/websocket 或 nhooyr.io/websocket
- os/exec
- crypto 标准库
- go-git 或直接调用 git CLI
- launchd / systemd 用于后台启动

### 可选 Relay

- Go
- WebSocket 双向转发
- 不解密业务内容
- 只保存最小连接状态

## 总体架构

```text
Flutter App
  - 会话列表
  - 聊天界面
  - Git 面板
  - 二维码配对
  - 本地密钥保存
        |
        | WebSocket / HTTPS
        v
Go Bridge
  - 设备认证
  - 会话管理
  - Codex 进程管理
  - 流式事件转发
  - Git 命令封装
  - 项目目录白名单
        |
        | stdio / HTTP / JSON-RPC
        v
Codex CLI / Codex App Server
        |
        v
Local Repositories
```

第一版可以只支持 Flutter App 直连 Go Bridge。Relay 放到后面再做，避免一开始把网络、安全和部署复杂度全部叠在一起。

## 核心组件

### 1. Flutter App

移动端负责呈现和交互，不直接接触本地文件系统。

主要页面：

- 设备页：展示已配对设备、连接状态、重新配对入口。
- 项目页：列出 Bridge 暴露的项目目录。
- 会话页：展示历史会话、创建新会话。
- 聊天页：发送 prompt，显示流式输出、工具调用、命令结果和确认按钮。
- Git 页：展示 status、diff、branch、commit 输入框和 push 确认。
- 设置页：配置 Relay、通知、显示密度、日志开关。

### 2. Go Bridge

Bridge 是整个系统的核心，运行在用户自己的电脑上。

职责：

- 监听本地或局域网端口。
- 提供二维码配对信息。
- 认证移动端连接。
- 管理允许访问的项目目录。
- 启动或连接 Codex runtime。
- 把 Codex 的流式事件转发给 Flutter。
- 封装 Git 操作并要求用户确认高风险动作。
- 保存本地会话索引和连接日志。

Bridge 不应该默认开放整个用户主目录，应该通过配置明确列出允许访问的 workspace。

### 3. Codex Adapter

Codex Adapter 用来隔离 Codex CLI / Codex App Server 的具体调用方式。

建议定义内部接口：

```go
type CodexAdapter interface {
    StartSession(ctx context.Context, req StartSessionRequest) (Session, error)
    SendPrompt(ctx context.Context, sessionID string, prompt string) error
    StreamEvents(ctx context.Context, sessionID string) (<-chan CodexEvent, error)
    Interrupt(ctx context.Context, sessionID string) error
    Resume(ctx context.Context, sessionID string) error
}
```

第一版可以直接通过 `os/exec` 调用 Codex CLI。后续如果使用 `codex app-server` 或其他本地协议，只需要替换 Adapter，不影响 Flutter App 和 Bridge API。

### 4. Git Adapter

Git 功能先做只读，再做写操作。

第一阶段：

- `git status --short`
- `git branch --show-current`
- `git diff --stat`
- `git diff`
- `git log --oneline -n 20`

第二阶段：

- commit
- push
- checkout existing branch

高风险操作默认不做：

- reset
- rebase
- clean
- force push
- 删除分支

如果未来要支持这些操作，需要单独的确认流程和操作日志。

## 通信协议

移动端和 Bridge 之间使用 WebSocket。HTTP 只用于健康检查、配对二维码和静态信息。

### HTTP 接口

```text
GET /healthz
GET /pairing
GET /version
```

### WebSocket 地址

```text
ws://<bridge-host>:<port>/ws
```

### 消息格式

所有消息使用 JSON，包含 `type`、`id`、`payload`。

```json
{
  "type": "session.start",
  "id": "msg_001",
  "payload": {
    "workspace": "/Users/me/projects/demo",
    "prompt": "分析这个项目的结构"
  }
}
```

### 常用消息类型

客户端发给 Bridge：

- `auth.hello`
- `workspace.list`
- `session.list`
- `session.start`
- `session.prompt`
- `session.interrupt`
- `git.status`
- `git.diff`
- `git.commit`
- `git.push`

Bridge 发给客户端：

- `auth.ok`
- `workspace.list.result`
- `session.created`
- `session.event`
- `session.done`
- `session.error`
- `git.status.result`
- `git.diff.result`
- `confirm.required`

流式输出可以统一成事件：

```json
{
  "type": "session.event",
  "id": "evt_001",
  "payload": {
    "sessionId": "s_123",
    "kind": "assistant_delta",
    "text": "我先看一下项目结构..."
  }
}
```

## 安全设计

第一版安全目标是防止局域网内未授权设备连接 Bridge。

最低要求：

- Bridge 默认只监听 `127.0.0.1`，用户显式开启局域网监听。
- 首次配对通过二维码交换一次性 token。
- 配对成功后生成设备级长期密钥。
- Flutter 使用系统安全存储保存密钥。
- Bridge 保存已授权设备列表。
- 所有高风险操作需要移动端二次确认。
- Bridge 限制可访问 workspace 白名单。

进阶版本：

- TLS
- 端到端加密
- 设备撤销
- 配对码过期
- 操作审计日志
- Relay 只做密文转发

## 配置文件

Bridge 使用本地配置文件，例如：

```yaml
server:
  host: "127.0.0.1"
  port: 8765

codex:
  mode: "cli"
  binary: "codex"

workspaces:
  - name: "demo"
    path: "/Users/me/projects/demo"
  - name: "app"
    path: "/Users/me/projects/app"

security:
  pairing_enabled: true
  pairing_ttl_seconds: 300
  require_confirm_for_git_write: true
```

## 推荐目录结构

```text
remote-codex-companion/
  README.md
  apps/
    mobile/
      pubspec.yaml
      lib/
        main.dart
        app/
        features/
          devices/
          workspaces/
          sessions/
          git/
        services/
          bridge_client.dart
          secure_store.dart
  bridge/
    go.mod
    cmd/
      rcc-bridge/
        main.go
    internal/
      api/
      auth/
      codex/
      config/
      git/
      session/
      workspace/
  relay/
    go.mod
    cmd/
      rcc-relay/
        main.go
  docs/
    protocol.md
    security.md
```

## MVP 开发计划

### Milestone 1：本地 Bridge

- Go Bridge 启动 HTTP 服务。
- 实现 `/healthz`。
- 加载 YAML 配置。
- 返回 workspace 列表。
- Flutter App 能连接 Bridge 并展示连接状态。

### Milestone 2：基础会话

- Flutter 发送 prompt。
- Bridge 调用 Codex CLI。
- Bridge 把 stdout / stderr 流式转发给 Flutter。
- Flutter 展示流式文本。
- 支持中断当前任务。

### Milestone 3：会话历史

- Bridge 保存本地 session index。
- Flutter 展示历史会话。
- 支持继续某个会话。
- 支持查看错误日志。

### Milestone 4：Git 面板

- 展示 status、branch、diff。
- 支持输入 commit message。
- commit / push 前弹出确认。
- Bridge 记录 Git 写操作日志。

### Milestone 5：安全配对

- Bridge 生成二维码。
- Flutter 扫码配对。
- 保存设备密钥。
- Bridge 拒绝未授权设备。
- 支持移除设备。

### Milestone 6：远程 Relay

- 自建 Relay 服务。
- Bridge 和 Flutter 都主动连接 Relay。
- Relay 只转发加密消息。
- 支持断线重连。

## 难点和风险

### Codex 调用方式稳定性

Codex CLI 和 Codex App Server 的接口可能变化。项目应该把所有 Codex 相关逻辑收敛到 Adapter 中，避免协议变化影响全局。

### 流式输出和工具调用表达

简单 stdout 流式转发很容易做，但要完整表达工具调用、确认、错误、权限请求和最终结果，需要设计稳定的事件模型。

### 安全边界

这个工具有能力操作本地代码和执行命令，所以安全边界比普通聊天 App 高很多。默认配置应该保守，宁愿多一步确认，也不要默认暴露危险能力。

### 后台常驻

Bridge 需要稳定运行。macOS 建议用 `launchd`，Linux 用 `systemd`。Flutter App 不应该承担保持连接的核心责任。

### 移动端体验

手机屏幕小，不能照搬桌面 Codex UI。需要优先展示当前任务、最新输出、确认按钮和 Git 变更摘要，复杂日志放到二级页面。

## Flutter 是否合适

Flutter 很适合做这个项目的移动端，因为它可以同时覆盖 iOS 和 Android，聊天 UI、WebSocket、二维码扫描、安全存储和推送通知都有成熟生态。

但 Bridge 不建议用 Flutter 实现。Bridge 更适合 Go，因为它要管理本地进程、文件路径、Git 命令、后台服务和网络连接。Flutter 可以在未来做一个桌面设置面板，但不应该是核心 daemon。

## Go 是否合适

Go 很适合做 Bridge 和 Relay。

优势：

- 单文件部署简单。
- 并发和 WebSocket 支持成熟。
- 调用本地进程方便。
- 标准库足够强。
- 适合做长期运行的小型 daemon。

需要注意：

- 不要把 shell 字符串拼接成命令执行。
- workspace 路径必须做白名单校验。
- Git 写操作要有确认和日志。
- Codex 进程生命周期要能被取消和清理。

## 第一版验收标准

- Mac 上运行 `rcc-bridge`。
- 手机 Flutter App 扫码或手动输入地址连接 Bridge。
- App 能看到 workspace 列表。
- App 能在某个 workspace 中发起 Codex 任务。
- App 能实时看到 Codex 输出。
- App 能中断任务。
- App 能查看 `git status` 和 `git diff`。
- 未配对设备不能连接。

## 当前实现

本仓库的 Flutter App 已实现第一版移动端控制台：

- Device：手动输入 Bridge 地址与 pairing token，完成 WebSocket 认证。
- 首次配对拿到的 device key 会通过 `flutter_secure_storage` 保存。
- 支持从 `/pairing` 获取配对信息、展示配对 QR、扫描 `recodex://pair` QR。
- Console：选择 workspace，发送 prompt，查看 Bridge 转发的 Codex 流式输出，并支持 interrupt。
- Git：查看 status / diff / log，执行 commit / push。
- Sessions：查看 Bridge 返回的本地会话索引。
- Settings：查看/撤销已授权设备，清除本机保存的 device key。

Go Bridge 位于：

```text
/Users/wfu/Documents/works/xiaoxi/code/recodex/recodex-go
```

启动 Bridge：

```bash
cd /Users/wfu/Documents/works/xiaoxi/code/recodex/recodex-go
go run ./cmd/rcc-bridge -config bridge.yaml
```

启动后复制日志中的 pairing token，或访问 `http://127.0.0.1:8765/pairing` 查看配对信息。手机真机连接时需要把 `bridge.yaml` 的 `server.host` 改为 `0.0.0.0`，并在 App 中填写电脑的局域网地址。

Relay 骨架也已实现：

```bash
cd /Users/wfu/Documents/works/xiaoxi/code/recodex/recodex-go
go run ./cmd/rcc-relay -addr 127.0.0.1:8787
```

Relay 暴露 `GET /healthz` 和 `WS /relay/<room>`，只做同房间 WebSocket 消息转发，不解析业务内容。

## 后续方向

- Bridge/App 通过自托管 Relay 建立远程连接。
- APNs / FCM 推送通知。
- 图片附件。
- 多设备同步。
- Android 支持。
- 桌面设置面板。
- 更完整的 Codex 事件模型。
- 更细粒度的权限系统。
