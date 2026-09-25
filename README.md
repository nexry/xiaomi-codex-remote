# Xiaomi Codex Remote

Xiaomi Codex Remote 是一个面向 macOS 的开源实验项目，用于把小米 RC003 蓝牙遥控器的按键事件转换为 Codex Micro 兼容协议，并通过本地 shim 连接支持该设备协议的桌面宿主应用。

项目同时提供：

- 原生 macOS SwiftUI 控制应用；
- RC003 按键映射与按下/释放状态管理；
- Codex Micro JSON-RPC、64 字节 HID framing 与本地 socket 传输；
- 不依赖真实硬件的 JSONL 输入与协议测试；
- 实验性的 ATVV 音频解析和虚拟音频驱动代码。

> [!IMPORTANT]
> 当前以“按键 MVP”为主要范围。自动化测试能够验证模拟输入、协议封包和本地链路，但不能替代真实 RC003、当前 ChatGPT 桌面版或音频链路的真机验收。语音功能仍属于实验性实现，请勿将其视为即装即用的稳定功能。

## 当前状态

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| JSONL 模拟按键 | 可用 | 无需遥控器，适合开发和协议回归测试 |
| Codex Micro 协议与 shim | 已实现 | 宿主应用版本变化可能影响兼容性 |
| macOS 原生 GUI | 已实现 | 源码构建需要 macOS 14+ 与 Xcode |
| RC003 按键输入 | 待持续真机验证 | 仅按捕获数据实现，不推断未知 HID/BLE 字段 |
| RC003 语音与虚拟音频 | 实验性 | 仍需针对设备、系统权限和音频设备完整验收 |

## 工作原理

```text
RC003 / JSONL 模拟输入
          │
          ▼
标准化事件 { key, action }
          │
          ▼
按键映射 → Codex Micro 协议模拟器 → 64 字节 framing
          │
          ▼
本地 Unix socket → node-hid shim → 桌面宿主应用
```

普通按键发送配对的 `press` / `release`；旋转事件发送 `act: 2`。输入断开、程序退出或发生异常时，桥接层会释放仍处于按下状态的按键。

## 环境要求

- macOS 14 Sonoma 或更高版本；
- 从源码构建 GUI：Xcode 与 Swift 5.9+；
- 使用 CLI 或运行 JavaScript 测试：Node.js 18+；
- 真实遥控器路径：已在 macOS 蓝牙设置中配对的 RC003；
- 实验性语音路径：项目虚拟音频驱动或其他可用的双声道回环设备。

## 快速开始

### 1. 获取依赖

```bash
npm install
```

依赖只用于 CLI、兼容输入和 JavaScript 测试；原生 GUI 的 Swift 包没有第三方包依赖。

### 2. 无硬件模拟

先启动桥接服务：

```bash
npm start -- --input xiaomi --xiaomi-source stdin --mode shim --verbose
```

然后逐行输入标准化 JSON 事件，例如：

```json
{"key":"home","action":"press"}
{"key":"home","action":"release"}
```

也可以直接使用仓库示例：

```bash
npm start -- --verbose < examples/buttons.jsonl
```

### 3. 构建原生应用

```bash
npm run build:gui
bash native/xiaomi-codex-remote-gui/bundle-app.sh
open "native/xiaomi-codex-remote-gui/Xiaomi Codex Remote.app"
```

`bundle-app.sh` 会生成未公证、临时签名的本地应用包。公开分发前需要使用自己的 Apple Developer 身份完成正式签名与公证。

### 4. 系统权限

真实设备路径可能需要以下 macOS 权限：

- 输入监控：读取遥控器按键；
- 蓝牙：连接遥控器和读取相关服务；
- 麦克风：仅实验性语音链路需要；
- 辅助功能：仅启用音量键拦截时需要。

请只在理解用途后授权。关闭主窗口会让应用继续驻留菜单栏；从菜单退出应用才会停止监听并释放按键。

## 默认按键映射

| RC003 逻辑键 | Codex Micro 输出 | 行为 |
| --- | --- | --- |
| `voice` | `ACT10` | 按下/释放 |
| `ok` | `ENC_CLK` | 编码器按压 |
| `volume_up` | `ENC_CC` | 旋转事件，`act: 2` |
| `volume_down` | `ENC_CW` | 旋转事件，`act: 2` |
| `home` | `AG00` | 按下/释放 |
| `menu` | `AG01` | 按下/释放 |
| `back` | `ACT08` | 按下/释放，可禁用 |
| `up/down/left/right` | `v.oai.rad` | 摇杆方向 |
| `power` | 未绑定 | 默认禁用 |

CLI 可通过 `--xiaomi-config` 加载 [config/xiaomi.example.json](config/xiaomi.example.json) 格式的覆盖配置。不要为未捕获、未验证的设备字段自行填写 VID/PID、usage、GATT UUID、opcode、采样率或编解码器。

## 与桌面宿主应用连接

GUI 中的“启动 ChatGPT”操作会由用户主动触发，并使用 `NODE_OPTIONS` 预加载 `shim/preload.cjs`。这会退出并重新打开已有 ChatGPT 进程，但不会修改应用包中的文件。

也可以在桥接服务已运行时手动执行：

```bash
bash shim/launch-chatgpt.sh
```

可选环境变量：

- `CHATGPT_APP`：宿主应用路径，默认 `/Applications/ChatGPT.app`；
- `CODEX_MICRO_SOCKET`：Unix socket 路径；
- `CODEX_MICRO_SHIM_LOG`：shim 日志路径。

该集成依赖宿主应用的内部运行环境，升级后可能失效。请在使用前自行评估风险，并仅在本地测试环境中启用。

## 测试与检查

```bash
npm test
npm run check
swift test --package-path native/xiaomi-codex-remote-gui
```

测试分为三个层次，请分别记录结果：

1. 模拟输入和协议自动化；
2. 真实 RC003 按键、断连与退出释放；
3. 具体桌面宿主版本的兼容性。

语音链路还需要单独验证设备固件、协商参数、连续音频质量与虚拟音频设备。协议单元测试通过不代表这些真机项目已经通过。

## 目录结构

```text
assets/                              App 图标源文件
bin/                                 Node CLI 入口
config/                              按键映射示例
examples/                            JSONL 模拟输入
native/xiaomi-codex-remote-gui/      SwiftUI macOS 应用
native/XiaomiCodexRemoteAudio/       实验性虚拟音频驱动脚本
native/CodexMicroVirtualHID/          可选原生虚拟 HID helper
shim/                                桌面宿主的 node-hid shim
src/xiaomi/                          RC003 映射、输入和音频协议代码
src/transports/                      本地传输层
test/                                JavaScript 自动化测试与 fixture
```

## 开发约定

- 小米设备相关行为放在 `src/xiaomi/` 或原生应用对应模块中；
- 输入源统一输出 `{key, action}`，CLI 不直接解析原始 HID/BLE 数据；
- 不在没有捕获数据和回归测试的情况下修改线协议、USB 标识或 action 值；
- 新配置必须可验证、可禁用；
- 断连、退出和异常路径必须释放按住的键；
- 提交变更前运行 JavaScript 测试、语法检查和相关 Swift 测试。

更多开发信息见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 许可证与致谢

项目以 [MIT License](LICENSE) 发布。协议模拟、Stream Deck/keyboard 兼容层的部分设计和代码源自 Marcel Pociot 的 `codex-micro-stream-deck-emulator`，其 MIT 版权声明保留在 LICENSE 中。本开源目录不包含该参考仓库、其文档副本或内部开发计划。

Xiaomi、OpenAI、ChatGPT、Codex、Work Louder 和 Elgato 是其各自所有者的商标。本项目是独立社区项目，与这些公司没有隶属、授权、赞助或背书关系。
