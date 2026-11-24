# ChatTtt 移动端（Android）

ChatTtt 的手机客户端，**基于开源项目 [Kelivo](https://github.com/Chevey339/kelivo) 修改**：
保留 Kelivo 的聊天引擎、UI 组件、主题与本地数据库，替换掉它的模型供应商层，
接上 ChatTtt 自己的 Socket.io 后端，并按需求移除了一批与聊天无关的功能。

- **包名**：`com.imwjh.chatttt`（由线上域名 `chatttt.imwjh.com` 反向而来）
- **应用名**：ChatTtt
- **协议**：AGPL-3.0（继承 Kelivo）
- **上游基线**：Kelivo master（`flutter_tools` 模板：Flutter 3.50 / AGP 9.3.1 / Gradle 9.5）
- **平台范围**：仅保留 Android。`ios/`、`linux/`、`macos/`、`windows/`、`web/` 平台壳已移除；需要时可在本目录执行 `flutter create . --platforms=ios,web` 重新生成。

## 🔧 改了什么

### 1. 换掉模型供应商层（核心改动）

Kelivo 原本对接各家 LLM 的 HTTP API。ChatTtt 的后端是 Socket.io 中转真人回复，
所以在 Kelivo 的供应商体系里加了一个内置供应商 `chatttt`：

| 位置 | 改动 |
|---|---|
| `lib/core/chatttt/chatttt_config.dart` | 服务器地址、演示模型、访客身份 |
| `lib/core/chatttt/chatttt_service.dart` | Socket.io 通道、消息队列、媒体落盘、图片压缩 |
| `lib/core/services/api/providers/chatttt/chatttt_provider.dart` | 把后台回复转成 Kelivo 的 `StreamChunk` |
| `lib/core/services/api/chat_api_service.dart` | 内置供应商走 ChatTtt 分支，不进 LLM 协议栈 |
| `lib/core/providers/settings_provider.dart` | 内置供应商配置、动态配色关闭 |
| `lib/features/home/utils/model_display_helper.dart` | 模型解析固定到内置供应商 |

Kelivo 原生的模型选择器、消息流式渲染、图片/语音渲染、错误提示全部照常工作。

### 2. 移除的功能（入口全部关掉）

设置页重写为「账户与用量 / 外观 / 支持与安全 / 数据与隐私 / 关于」五组，以下入口**已从界面移除**：

模型供应商、语言服务(TTS/ASR)、搜索服务、助手、MCP、工作区与环境、定时任务、
技能、世界书、记忆、手机控制、指令注入、网络代理、统计、使用文档、日志、
工具描述、快速短语、备份、浏览器、扫码、开发者选项、智能 UI。

对话页同步移除：

- 消息气泡下方的操作栏（复制 / 重新回答 / 编辑 / 三点更多 / TTS / 翻译）
- 「深度思考」思考链展示
- 右侧「快捷跳转气泡」迷你地图
- 输入栏的工作区 / 技能 / 工具 / 快捷短语 / 更多 入口
- 侧边栏的翻译按钮

设置层同时关掉了「用户消息操作栏」「思考链卡片」「动态配色」三个开关，
即使残留代码被触发也不会显示。

> 说明：这些功能的**底层模块代码仍在仓库里**（Kelivo 的聊天引擎与它们耦合很深，
> 物理删除需要重写约 900KB 的核心链路）。目前它们**不可达、不执行、不可见**。

### 3. 服务器地址不写死

三级来源，优先级从高到低：

1. **应用内填写**（推荐）
   首次启动会弹窗引导填写；之后在「设置 → 关于 → 服务地址」随时可改，改完立即重连。
2. **打包时预置**
   ```bash
   flutter build apk --release --dart-define=CHATTTT_SERVER_URL=https://chatttt.imwjh.com
   ```
3. **都没配置** → 启动时弹窗等待填写。

地址只填域名即可（自动补 `https://`）。**别人从 GitHub 拉源码后不用重新打包**：
装好 App，填自己的域名就能用。

## 🔌 与网页端如何互通

App 直接连 ChatTtt 的 Socket.io 服务，事件名与负载结构**完全沿用网页端**
（`web/src/App.tsx` + `server/server.js`），所以手机与网页可以同时在线、互发消息。

| 方向 | 事件 | 负载 |
|---|---|---|
| → 服务端 | `visitor:join` | `{ sessionId }` |
| → 服务端 | `visitor:message` | `{ type, text?, imageKey?, imageData?, audioKey?, audioData?, duration? }` |
| → 服务端 | `visitor:typing` | — |
| ← 服务端 | `visitor:joined` | `{ sessionId, messages[] }`（重连时补收历史） |
| ← 服务端 | `visitor:new-message` | `{ sessionId, message }` |
| ← 服务端 | `visitor:error` | `{ code: 'admin-offline' }` |
| ← 服务端 | `visitor:typing` | — |

媒体处理与网页端一致：**服务端只在内存中转**，图片 / 语音本体以 dataURI 随消息附带，
双方各自把本体存本地（网页端存 IndexedDB，移动端存应用沙盒），消息里只带双方一致的 key。

## 🛠️ 构建

### 环境要求

- **Flutter 3.50.x**（Dart 3.14）
- Android SDK 36 / JDK 17
- AGP 9.3.1 / Gradle 9.5.0 / Kotlin 2.4.20（本仓库已按这套组合验证通过）

### 构建

```bash
cd android-app
flutter pub get
flutter build apk --release --dart-define=CHATTTT_SERVER_URL=https://chatttt.imwjh.com
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。

> **Windows 路径含中文时**：Flutter 的 AOT 快照工具与 Gradle 都读不了非 ASCII 路径
> （`Unable to read file: ...app.dill`、`Included build ... does not exist`）。
> 用一个纯 ASCII 的目录联接绕开：
> ```powershell
> New-Item -ItemType Junction -Path E:\ChatTttBuild\android-app `
>   -Target "<项目绝对路径>\android-app"
> cd E:\ChatTttBuild\android-app
> flutter build apk --release
> ```
> 同时把 `android/local.properties` 里的 `flutter.sdk` 指向纯 ASCII 路径的 Flutter SDK。

### 签名

仓库不含签名密钥，`android/key.properties` 与 `*.jks` 已 gitignore。
没有 key.properties 时构建出的 release 包未签名，装不上。生成自己的：

```bash
keytool -genkeypair -v -keystore android/app/chatttt-release.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10950 \
  -alias chatttt -storepass <口令> -keypass <口令> \
  -dname "CN=ChatTtt, O=ChatTtt, C=CN"
```

然后在 `android/key.properties` 写入 `storePassword / keyPassword / keyAlias / storeFile`。

## 🎨 图标

图标由项目 SVG logo 生成（纯白底）：

```bash
cd tool
python gen_icons.py          # 生成 assets/app_icon*.png（需要 Chrome）
python gen_android_icons.py  # 生成各密度 mipmap 与自适应图标
```

## 📄 开源协议

沿用 Kelivo 的 **AGPL-3.0**（本目录包含 Kelivo 源代码的修改版）。
