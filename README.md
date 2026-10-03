# Xiaomi Codex Remote

Xiaomi Codex Remote 是一个面向 macOS 的开源实验项目，用于把小米 RC003 蓝牙遥控器的按键事件转换为 Codex Micro 兼容协议，并通过本地 shim 连接支持该设备协议的桌面宿主应用。

项目同时提供：

- 原生 macOS SwiftUI 控制应用；
- RC003 按键映射与按下/释放状态管理；
- Codex Micro JSON-RPC、64 字节 HID framing 与本地 socket 传输；
- 不依赖真实硬件的 JSONL 输入与协议测试；
- 基于捕获数据实现的 ATVV 音频解析和虚拟音频路由。

> [!IMPORTANT]
> v0.3.1 新增 Power 自动打开 ChatGPT 遥控版，并优化按键设置界面。自动化测试覆盖模拟输入、协议封包和本地链路，不能替代真机验收。v0.3.1 发布附件未内置 `MiCodexRemote2ch.driver`，使用遥控器语音前需授予所需系统权限、准备兼容的双声道虚拟音频设备，并确认 BLE 音频连接就绪。

## 当前状态

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| JSONL 模拟按键 | 可用 | 无需遥控器，适合开发和协议回归测试 |
| Codex Micro 协议与 shim | 已实现 | 使用受管理的 ChatGPT 兼容副本；宿主升级后需要更新副本 |
| macOS 原生 GUI | 已实现 | 包含按键设置、权限与日志、Dock 图标偏好、遥控版管理和真实连接状态 |
| RC003 按键输入 | 已有真机验证记录 | OK 默认 ACT12；Power 自动启动和具体宿主行为仍需目标环境真机验收 |
| RC003 语音与虚拟音频 | 已实现，已有真机验证记录 | 使用前需授予所需系统权限，并准备兼容的双声道虚拟音频设备；其他环境需分别验收 |

## v0.3.1 更新

- GUI 的 Power 键固定用于打开 ChatGPT 遥控版：首次确认后自动设置或更新副本并启动，正常退出失败时停止；已连接时切到前台，连续按键不重复执行。
- 遥控版文件名改为 `ChatGPT-for-XiaomiRemote.app`，界面统一使用「ChatGPT 遥控版」和「遥控连接服务」。
- 页面改为「按键设置」，遥控器卡片分层展示状态、固定按键和说明；编辑弹窗提供底部「清除绑定」与右上角关闭按钮，按内容确定高度。
- Micro 图片保持 240 × 240 pt，支持旋钮、摇杆子事件高亮；修复首次打开编辑器时缺少绑定选中态。
- 缩小遥控器圆形按钮描边，保持中心点、方向键 SVG、1 pt 线宽及 3/3 pt 虚线不变。
- OK 默认绑定 ACT12；GUI 语音固定 ACT10 并协调麦克风启停。实际宿主行为由 ChatGPT 配置，CLI 仍允许覆盖语音或 Power。
- GUI 忽略旧 Power 绑定，其他保存的设置保持不变。从旧副本路径升级需重新设置遥控支持并更新 Dock 入口；不会自动删除旧副本。

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

GUI 直接读取真实遥控器输入并使用内置原生桥接，不依赖 Node CLI，也不会自动向 CLI 的 IPC socket 转发事件。CLI 的 `stdin` 接收模拟 JSONL；`ipc`（别名 `miremote`、`sayall`）监听外部进程发送的标准化 JSONL 事件。Node 的 `ble` 输入源仍为占位实现，不能用于直接连接真实遥控器；GUI 的 BLE 语音链路是独立实现。

## 环境要求

- macOS 14 Sonoma 或更高版本；
- Swift 包声明的工具版本为 5.9，需要兼容的 Swift 工具链和 macOS SDK；
- 打包完整 GUI：还需支持当前 Icon Composer `.icon` 资源的 Xcode `actool`，不能仅凭 Swift 版本判断能否打包；
- 使用 CLI 或运行 JavaScript 测试：Node.js 18+；
- 真实遥控器路径：已在 macOS 蓝牙设置中配对的 RC003；
- 遥控器语音路径：项目虚拟音频驱动或其他可用的双声道回环设备；v0.3.1 发布包未内置驱动。

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

`npm run build:gui` 只构建可执行文件；`bundle-app.sh` 会再次构建并打包图片、图标和 shim，生成 ad-hoc 签名、未公证的应用包。正式签名与公证是公开分发的建议步骤，不是当前发布包已有的能力。

如需生成 arm64 / x86_64 通用应用包：

```bash
RELEASE_UNIVERSAL=1 bash native/xiaomi-codex-remote-gui/bundle-app.sh
```

v0.3.1 发布附件不含音频驱动；源码打包时，如果 `native/XiaomiCodexRemoteAudio/MiCodexRemote2ch.driver` 已存在，脚本会将其复制到应用资源中。因此，源码构建的内容可能与发布附件不同。

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
| `voice` | `ACT10` | 按下/释放；GUI 固定绑定，并按住开启遥控器麦克风、松开关闭 |
| `ok` | `ACT12` | Micro ACT12 键位，按下/释放 |
| `volume_up` | `ENC_CC` | 旋转事件，`act: 2` |
| `volume_down` | `ENC_CW` | 旋转事件，`act: 2` |
| `home` | `AG00` | 按下/释放 |
| `menu` | `AG01` | 按下/释放 |
| `back` | `ACT08` | 按下/释放，可禁用 |
| `up/down/left/right` | `v.oai.rad` | 摇杆方向 |
| `power` | GUI 固定启动操作；CLI 默认未绑定 | GUI 自动设置并打开 ChatGPT 遥控版，不发送 Micro 输入 |
| `tv` | 未绑定 | GUI 可配置；真实 RC003 的 TV 输入 usage 尚未捕获，不能保证真机触发 |

CLI 可通过 `--xiaomi-config` 加载 [config/xiaomi.example.json](config/xiaomi.example.json) 格式的覆盖配置。不要为未捕获、未验证的设备字段自行填写 VID/PID、usage、GATT UUID、opcode、采样率或编解码器。

本项目只把遥控器输入绑定到 Micro 键位或旋钮、摇杆输入，不绑定具体的 ChatGPT 事件，也不读取 ChatGPT 的 Micro 行为配置。实际行为由 ChatGPT 的 Codex Micro 控制面板决定，不能将 ACT12、ACT08 固定解释为「提交」「拒绝」。图片图标仅用于定位键位。语音键是本地特殊处理：GUI 固定发送 ACT10，并协调遥控器麦克风启停；ACT10 在宿主中的行为仍由宿主配置决定。

GUI 与 CLI 的默认四个方向键均绑定摇杆事件，但示例配置将 `up`、`down`、`left`、`right` 显式设为 `null`；加载该示例会禁用方向键，而不是保留默认方向行为。CLI 也允许覆盖语音键或将其设为 `null`，不受 GUI 固定 ACT10 的限制。

## 与桌面宿主应用连接

官方 ChatGPT 的 Electron fuse 默认不接受 `NODE_OPTIONS`。GUI 通过明确的用户操作，在 `~/Applications/ChatGPT-for-XiaomiRemote.app` 创建受管理的兼容副本；官方 `/Applications/ChatGPT.app` 保持只读。

首次使用流程：

1. 正常退出 ChatGPT；
2. 在 GUI 中点击“设置遥控支持”；
3. GUI 原生完成复制、NodeOptions fuse 修改、内置 shim、启动环境、本地签名和验证，不需要 Node.js 或终端；
4. 点击“打开 ChatGPT 遥控版”。若需要退出当前 ChatGPT，会先请求确认；只有本地 socket 实际连接后，界面才显示“已连接”；
5. 使用“在 Finder 中显示”可将显示名为「ChatGPT 遥控版」 的兼容副本拖入 Dock。以后从 Dock 启动也会加载 shim，但 Xiaomi Codex Remote 需要保持运行。

也可以按遥控器 Power 键：首次确认后自动完成正常退出、设置或更新、启动连接服务和打开遥控版。已连接时切到前台；退出失败停止，不强制退出。此功能只在 GUI 中提供，不向 Micro 发送 Power 事件。

GUI 会比较官方应用与兼容副本的 `CFBundleVersion`：

- 没有兼容副本：显示“需要设置”；
- 官方版本变化：显示“需要更新遥控支持”；
- fuse、内置 shim、启动环境、签名或签名权限不符合要求：显示“需要修复”。

兼容副本使用本地 ad-hoc 签名。OpenAI 团队专属的 application groups、推送和 keychain 权限不能保留，否则 macOS AMFI 会拒绝启动；因此首次打开兼容副本时可能需要重新登录或重新授予系统权限。

开发者可使用以下回退方式（需要 Node.js）：

```bash
bash shim/patch-app.sh
CHATGPT_APP="$HOME/Applications/ChatGPT-for-XiaomiRemote.app" bash shim/launch-chatgpt.sh
```

这些脚本的检查能力不等同于原生 GUI：准备脚本不会执行 GUI 的完整兼容性检查，启动脚本会尝试退出正在运行的 ChatGPT，再直接启动指定副本。运行前请保存工作并先启动桥接服务；不要将脚本默认的官方应用路径视为无需准备即可注入的保证。

可选环境变量：

- `CHATGPT_APP`：源应用或启动目标路径；
- `CHATGPT_SHIM_APP`：兼容副本路径，默认 `~/Applications/ChatGPT-for-XiaomiRemote.app`；
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

历史开发环境有按键和语音端到端真机验证记录，但不能作为 v0.3.1 的完整验收。新默认 OK → ACT12 仍需目标宿主真机验收。兼容性验证应记录具体环境并在宿主更新后重新执行。

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

第三方组件适用各自的许可证。音频驱动构建脚本下载并修改 BlackHole v0.7.1，其源码使用独立的 [GPLv3 许可](https://github.com/ExistentialAudio/BlackHole/blob/v0.7.1/LICENSE)。该第三方源码及由其构建的驱动不能被概括为本项目的 MIT 代码；分发时需核对并遵循其许可要求。

Xiaomi、OpenAI、ChatGPT、Codex、Work Louder 和 Elgato 是其各自所有者的商标。本项目是独立社区项目，与这些公司没有隶属、授权、赞助或背书关系。
