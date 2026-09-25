# 开发说明

## 运行路径

原生 GUI 的按键路径为：

```text
HIDRemoteMonitor
  → { key, action }
  → XiaomiInputRouter
  → CodexEmulator
  → CodexFraming
  → CodexSocketServer
  → bundled shim
```

Node CLI 的兼容路径为：

```text
stdin / 外部 JSONL IPC
  → { key, action }
  → XiaomiRemoteBackend
  → Link
  → framing
  → socket
  → shim
```

真实 RC003 的原始输入由原生应用负责。Node 输入源只接收标准化的逻辑事件，不直接打开遥控器 HID。

## 输入源契约

输入源继承 `EventEmitter`，并实现异步 `start()` / `stop()`：

- `key`：`{key: string, action: "press"|"release"|"repeat"}`；
- `disconnect`：上游输入断连，后端释放全部按住的键；
- `error`：后端释放按键并把错误交给调用方；
- `end`：输入结束，后端释放按键并关闭 CLI。

普通按键使用配对的 `press` / `release`。`act: 2` 只用于编码器旋转，不用于普通 HID 自动重复。连接真实 transport 时复用现有 `Link` 和 framing，不复制协议实现。

## 本地开发

```bash
npm install
npm test
npm run check
swift test --package-path native/xiaomi-codex-remote-gui
```

本地 socket 测试需要允许进程监听 Unix domain socket。若受限环境拒绝本地监听，应在具备相应权限的本机重新运行，不能把权限错误当作测试通过。

无硬件启动：

```bash
npm start -- --verbose < examples/buttons.jsonl
```

原生构建与运行时自检：

```bash
swift build --package-path native/xiaomi-codex-remote-gui
bash native/xiaomi-codex-remote-gui/bundle-app.sh
PATH=/usr/bin:/bin "native/xiaomi-codex-remote-gui/Xiaomi Codex Remote.app/Contents/MacOS/Xiaomi Codex Remote" --check-runtime
```

## 变更边界

- 只根据真实捕获数据与 fixture 实现 RC003 专有行为；
- 没有明确缺陷和回归测试时，不改动线协议、USB 标识和 action 值；
- 新行为优先添加最小回归测试；
- 权限测试必须使用注入的权限提供者，不更改开发机的真实系统权限；
- GUI 只有在匹配设备且输入监控已授权时才应显示连接成功；
- socket 断开、输入结束、异常和应用退出都必须清理按键状态。

## 验证层次

自动化验证只覆盖模拟输入、协议、framing、IPC 与 shim 行为。公开发布前仍需分别执行并记录：

1. RC003 每个按键的 press/release/旋转行为；
2. 持键时断连、重新连接与退出清理；
3. 目标 macOS 与桌面宿主版本的枚举和 RPC 兼容性；
4. 语音协商、连续音频、异常恢复和虚拟音频路由。
