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

真实 RC003 的原始输入由原生应用负责，GUI 直接使用内置原生桥接，不依赖 Node CLI，也不自动向 CLI IPC 转发事件。Node 的 `stdin` 接收模拟 JSONL，`ipc`（别名 `miremote`、`sayall`）在 `/tmp/xiaomi-remote-events.sock` 监听外部进程发送的标准化逻辑事件，不直接打开遥控器 HID。该输入 socket 与发往 shim 的 Codex 协议 socket 不同。Node 的 `ble` 输入源仍为占位实现，会明确报告不支持；不能与 GUI 的 BLE 语音实现混淆。

## ChatGPT 兼容副本

`ChatGPTCompatibilityManager` 在用户点击设置、更新、修复遥控支持，或明确启用并按下 Power 启动键后工作。固定目标为 `~/Applications/ChatGPT-for-XiaomiRemote.app`，显示名为「ChatGPT 遥控版」，官方应用保持只读。处理流程为：

1. 在目标同目录创建 staging bundle；
2. 复制官方应用并嵌入 `preload.cjs` 与 `patch.cjs`；
3. 原生扫描 Electron fuse wire，对所有架构 slice 开启 `EnableNodeOptionsEnvironmentVariable`；
4. 写入固定 socket、日志路径和兼容副本内部的 preload 路径；
5. 使用 ad-hoc 签名重新签署完整 bundle，并进行严格签名、版本、fuse、shim 和启动环境验证；
6. 全部通过后替换旧副本，失败时恢复备份。

ad-hoc 签名不能保留 OpenAI 团队专属的 application identifier、application groups、推送和 keychain entitlements。`codesign --verify` 本身不会报告这一类 AMFI 启动失败，因此兼容性检查还必须读取根应用 entitlements 并拒绝包含受限项的旧副本。

GUI 以 `CFBundleVersion` 区分需要设置和需要更新，以 bundle 内容、显示名、fuse、启动环境及签名策略区分需要修复。启动动作进入等待状态，只有 `CodexSocketServer` 的真实连接回调才能把状态改为“已连接”。从 Dock 启动依赖遥控版 `Info.plist` 中持久化的 `LSEnvironment`，不是 GUI 进程临时传入的环境变量。

GUI 的 Power 键是固定启动操作，不进入 Micro 路由。首次确认持久化用户同意，后续按键自动正常退出正在运行的 ChatGPT、按需准备副本、启动并等待连接；已连接时激活窗口，退出失败不会强制终止。整个操作防止重复进入。CLI 的 Power 默认仍未绑定且允许覆盖；语音协调和线协议不受此次修改影响。

## 输入源契约

Node 输入源继承 `EventEmitter`，并实现异步 `start()` / `stop()`；后端处理以下事件，但各输入源并不保证发出全部事件：

- `key`：`{key: string, action: "press"|"release"|"repeat"}`；
- `disconnect`：上游输入断连，后端释放全部按住的键；
- `error`：后端释放按键并把错误交给调用方；
- `end`：`stdin` 在 EOF 时发送，后端释放按键并关闭 CLI；IPC 客户端断开发送的是 `disconnect`，不能据此假定 CLI 会退出。

普通按键使用配对的 `press` / `release`。`act: 2` 只用于编码器旋转，不用于普通 HID 自动重复。连接真实 transport 时复用现有 `Link` 和 framing，不复制协议实现。

本项目绑定的是 Micro 键位或旋钮、摇杆输入，实际行为由 ChatGPT 的 Codex Micro 控制面板决定。当前 Shim 只转发 HID 数据，不读取或同步宿主行为配置；界面应使用键位标识，而不是硬编码「提交」「拒绝」等行为名称。

GUI 将语音键固定为 ACT10，加载保存配置时也会恢复该绑定，并在按下/释放时开启/关闭遥控器麦克风；这不保证 ACT10 在宿主中一定执行语音行为，宿主行为仍由其配置决定。Node CLI 的配置仍允许覆盖或禁用语音键。两条路径默认都将方向键映射到摇杆事件，但 `config/xiaomi.example.json` 显式禁用了四个方向键，加载示例时需注意这一覆盖行为。

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

Swift 包声明工具版本为 5.9；完整应用打包还需要支持当前 Icon Composer `.icon` 资源的 Xcode `actool`。`bundle-app.sh` 自行构建 release 二进制，`RELEASE_UNIVERSAL=1` 可生成 arm64 / x86_64 通用包。脚本根据 `package.json` 写入应用版本，使用 ad-hoc 签名，不执行正式签名或公证；公开分发建议另外完成这两项。

v0.3.0 发布附件不内置音频驱动。源码打包时，脚本会复制已有的 `native/XiaomiCodexRemoteAudio/MiCodexRemote2ch.driver`；不能假定所有本地打包结果都不含驱动。驱动构建脚本下载并修改 BlackHole v0.7.1，第三方源码适用其独立的 [GPLv3 许可](https://github.com/ExistentialAudio/BlackHole/blob/v0.7.1/LICENSE)，不是本项目 MIT 许可覆盖的代码。

`shim/patch-app.sh` 和 `shim/launch-chatgpt.sh` 是需要 Node.js 的开发回退方式，检查能力不等同于原生 GUI。启动脚本会尝试退出正在运行的 ChatGPT；运行前需保存工作，并明确指定已准备的兼容副本。不要把这些脚本作为无需确认的测试步骤。

## 变更边界

- 只根据真实捕获数据与 fixture 实现 RC003 专有行为；
- 没有明确缺陷和回归测试时，不改动线协议、USB 标识和 action 值；
- 新行为优先添加最小回归测试；
- 权限测试必须使用注入的权限提供者，不更改开发机的真实系统权限；
- GUI 只有在匹配设备且输入监控已授权时才应显示连接成功；
- 只有真实 `shimConnected` 回调才能显示 ChatGPT 已连接；
- 兼容副本签名不得保留需要 OpenAI Team ID 的受限 entitlements；
- socket 断开、输入结束、异常和应用退出都必须清理按键状态。

## 验证层次

自动化验证覆盖模拟输入、协议、framing、IPC 与 shim 行为，不能替代真机验收。历史开发环境有按键和语音的真机验证记录，但 v0.3.0 新默认 OK → ACT12 仍需宿主真机验收。语音使用前需授予所需系统权限，并准备兼容的虚拟音频设备。发布与兼容性维护需分别记录：

1. RC003 每个按键的 press/release/旋转行为及录制时的实际界面效果；
2. 持键时断连、重新连接与退出清理；
3. 目标 macOS 与桌面宿主版本的枚举和 RPC 兼容性；
4. 语音协商、连续音频、异常恢复和虚拟音频路由；
5. 验证所使用的 macOS、ChatGPT、RC003 固件与虚拟音频设备版本。
