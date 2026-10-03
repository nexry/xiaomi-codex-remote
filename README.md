# Xiaomi Codex Remote

Xiaomi Codex Remote 是一个面向 macOS 的开源实验项目，用于把小米 RC003 蓝牙遥控器的按键事件转换为 Codex Micro 兼容协议，并通过本地 shim 连接支持该设备协议的桌面宿主应用。

项目同时提供：

- 原生 macOS SwiftUI 控制应用；
- RC003 按键映射与按下/释放状态管理；
- Codex Micro JSON-RPC、64 字节 HID framing 与本地 socket 传输；
- 不依赖真实硬件的 JSONL 输入与协议测试；
- 基于捕获数据实现的 ATVV 音频解析和虚拟音频路由。

> [!IMPORTANT]
> v0.3.0 主要更新键位配置与界面。自动化测试只覆盖模拟输入、协议封包和本地链路，不能替代真机验收。最近的运行日志出现「BLE 语音特征尚未就绪」：语音键可触发 ACT10，但此时不会有遥控器音频输入；本版本没有修复该问题。发布包未内置 `MiCodexRemote2ch.driver`，使用遥控器语音前仍需准备兼容的双声道虚拟音频设备，并确认 BLE 音频连接就绪。

## 当前状态

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| JSONL 模拟按键 | 可用 | 无需遥控器，适合开发和协议回归测试 |
| Codex Micro 协议与 shim | 已实现 | 使用受管理的 ChatGPT 兼容副本；宿主升级后需要更新副本 |
| macOS 原生 GUI | 已实现 | 包含独立权限与日志面板、Dock 图标偏好、兼容副本管理和真实 shim 连接状态 |
| RC003 按键输入 | 已有真机验证记录 | v0.3.0 新默认 OK → ACT12 已通过协议测试，仍需在目标宿主重新进行真机验收 |
| RC003 语音与虚拟音频 | 已实现，存在连接问题 | 历史环境有真机验证记录；最近 BLE 语音特征未就绪，不能保证当前音频可用 |

## v0.3.0 更新

- 新增独立键位映射页，直接点击小米遥控器图片上的按钮进行配置。
- 使用 240 × 240 pt 的真实 Micro 图片选择输出，旋钮和摇杆展开二级事件菜单，并显示子事件的选中态。
- 统一待绑定虚线、已绑定蓝色实线和点击渐变样式；修正方向键轮廓与 OK 层级。
- OK 默认绑定 ACT12「提交」；语音键固定 ACT10「按住说话」，不可取消或修改。
- 优化固定 800 × 560 pt 窗口、偏好设置与菜单栏菜单。
- 已保存的键位配置会保留，不自动覆盖 OK 的旧绑定。只需手动将 OK 改为「提交」；恢复默认键位会重置全部绑定。

详情见 [CHANGELOG.md](CHANGELOG.md)。

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
- 遥控器语音路径：项目虚拟音频驱动或其他可用的双声道回环设备；v0.3.0 发布包未内置驱动。

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
- 蓝牙：连接遥控器并接收语音数据；
- 麦克风：使用遥控器语音链路时需要；
- 辅助功能：仅启用音量键拦截时需要。

请只在理解用途后授权。关闭主窗口会让应用继续驻留菜单栏；从菜单退出应用才会停止监听并释放按键。

如需只保留菜单栏入口，可在“偏好设置 → 通用”中开启“隐藏 Dock 图标”；该选择会立即生效并在后续启动时保留。

## 默认按键映射

| RC003 逻辑键 | Codex Micro 输出 | 行为 |
| --- | --- | --- |
| `voice` | `ACT10` | 固定按住说话，按下/释放 |
| `ok` | `ACT12` | 提交当前 Agent 的输入内容（composer.submit），按下/释放 |
| `volume_up` | `ENC_CC` | 旋转事件，`act: 2` |
| `volume_down` | `ENC_CW` | 旋转事件，`act: 2` |
| `home` | `AG00` | 按下/释放 |
| `menu` | `AG01` | 按下/释放 |
| `back` | `ACT08` | 按下/释放，可禁用 |
| `up/down/left/right` | `v.oai.rad` | 摇杆方向 |
| `power` | 未绑定 | 默认禁用 |
| `tv` | 未绑定 | GUI 可配置；真实 RC003 的 TV 输入 usage 尚未捕获，不能保证真机触发 |

CLI 可通过 `--xiaomi-config` 加载 [config/xiaomi.example.json](config/xiaomi.example.json) 格式的覆盖配置。不要为未捕获、未验证的设备字段自行填写 VID/PID、usage、GATT UUID、opcode、采样率或编解码器。

## 与桌面宿主应用连接

官方 ChatGPT 的 Electron fuse 默认不接受 `NODE_OPTIONS`。GUI 通过明确的用户操作，在 `~/Applications/ChatGPT-Patched.app` 创建受管理的兼容副本；官方 `/Applications/ChatGPT.app` 保持只读。

首次使用流程：

1. 正常退出 ChatGPT；
2. 在 GUI 中点击“准备 ChatGPT 兼容副本”；
3. GUI 原生完成复制、NodeOptions fuse 修改、内置 shim、启动环境、本地签名和验证，不需要 Node.js 或终端；
4. 点击“打开 ChatGPT Shim”。只有本地 socket 实际连接后，界面才显示“已注入并连接”；
5. 使用“在 Finder 中显示”可将显示名为 `ChatGPT Shim` 的兼容副本拖入 Dock。以后从 Dock 启动也会加载 shim，但 Xiaomi Codex Remote 需要保持运行。

GUI 会比较官方应用与兼容副本的 `CFBundleVersion`：

- 没有兼容副本：显示“需要准备”；
- 官方版本变化：显示“需要更新兼容副本”；
- fuse、内置 shim、启动环境、签名或签名权限不符合要求：显示“需要修复”。

兼容副本使用本地 ad-hoc 签名。OpenAI 团队专属的 application groups、推送和 keychain 权限不能保留，否则 macOS AMFI 会拒绝启动；因此首次打开兼容副本时可能需要重新登录或重新授予系统权限。

开发者可以使用回退脚本复现同一流程：

```bash
bash shim/patch-app.sh
CHATGPT_APP="$HOME/Applications/ChatGPT-Patched.app" bash shim/launch-chatgpt.sh
```

可选环境变量：

- `CHATGPT_APP`：源应用或启动目标路径；
- `CHATGPT_SHIM_APP`：兼容副本路径，默认 `~/Applications/ChatGPT-Patched.app`；
- `CODEX_MICRO_SOCKET`：Unix socket 路径，GUI 默认使用 `/tmp/xiaomi-codex-remote-<uid>.sock`；
- `CODEX_MICRO_SHIM_LOG`：shim 日志路径。

该集成依赖宿主应用的内部运行环境。自动化测试不能替代具体 ChatGPT 版本的人工兼容性验证。

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

历史开发环境有按键和语音端到端真机验证记录，但不能作为 v0.3.0 的完整验收。新默认 OK → ACT12 仍需目标宿主真机验收，最近 BLE 音频连接问题也未解决。兼容性验证应记录具体环境并在宿主更新后重新执行。

## 目录结构

```text
assets/                              App 图标源文件
bin/                                 Node CLI 入口
config/                              按键映射示例
examples/                            JSONL 模拟输入
native/xiaomi-codex-remote-gui/      SwiftUI macOS 应用
native/XiaomiCodexRemoteAudio/       实验性虚拟音频驱动脚本
native/CodexMicroVirtualHID/          可选原生虚拟 HID helper
shim/                                node-hid shim、兼容副本脚本与开发启动脚本
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
