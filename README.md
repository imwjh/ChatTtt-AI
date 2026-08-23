# ChatTtt AI 💬

一个用来**整蛊朋友的「假 AI」聊天网页**：界面做得跟正经 AI 助手一模一样——模型选择器、打字机动画、思考中转圈……朋友以为在和一个顶级大模型对话，实际上每一句都是**你本人在后台偷偷扮演的** 😈

> 纯玩乐/整活项目，追求「快速跑起来」，不依赖任何数据库和云服务。请适度使用，友情翻车概不负责。

## 😈 整蛊原理

```
朋友的视角：打开网页 → 选个模型（都是假的）→ 发消息 → "AI" 认真回复
你的视角：  打开后台   → 看到朋友发来的消息 → 你说什么"AI"就说什么
```

- 前台有「模型选择器」（Little Sunbee 5.3 / Super Sunbee 5.5 / Fuck-Image 2.1），全是演的
- 你回复后，前台会以打字机效果逐字输出，还带"正在思考"动画，仪式感拉满
- 支持发图片、语音输入，越真越好骗

## ✨ 功能特性

**前台（给朋友看的）**
- 💬 实时收发消息（Socket.io），回复带打字机动画 + "AI 正在思考"指示点
- 🤖 以假乱真的模型选择器与聊天界面
- 🖼️ 发送图片：前端自动压缩到几百 KB，图片只存双方浏览器 IndexedDB，服务器不落盘
- 🎤 语音输入（Web Speech API）
- 🌗 深色 / 浅色主题
- 📝 会话本地持久化：新建、重命名、删除会话，刷新不丢

**后台（给你用的）**
- 👥 受害者列表：以其首条消息自动命名，绿点标记在线状态
- 🔔 未读提醒：侧边栏折叠时新消息触发红点闪烁
- 📂 侧边栏可折叠收起（状态持久化）
- 💾 你的聊天记录保存在你浏览器 localStorage，不上传云端
- 🔑 口令登录（默认 `seegud123`，可用环境变量覆盖）

## 🛠️ 技术栈

| 端 | 技术 |
|---|---|
| 前端 | React 19 · Vite · TypeScript · Tailwind CSS 4 · [@assistant-ui/react](https://www.assistant-ui.com/) |
| 后端 | Node.js · Express 5 · Socket.io |
| 图片存储 | 双方浏览器 IndexedDB（canvas 压缩至 ~280KB WebP） |
| 文字记录 | 各自浏览器 localStorage |

> ⚠️ 注意：服务器只在内存中转消息，**重启后未送达的离线消息会丢失**；各端的聊天记录都存在各自的浏览器里。这是刻意为之的设计——不建数据库，零云端依赖。

## 📁 项目结构

```
ChatTtt/
├── web/                # 前端（前台 + 后台双入口）
│   ├── index.html      # 前台入口（给朋友的）
│   ├── admin.html      # 后台入口（给你的）
│   └── src/
│       ├── App.tsx     # 前台主逻辑（Socket 接入、断线补收）
│       ├── admin.tsx   # 后台主逻辑（多受害者切换、未读红点）
│       ├── lib/image-store.ts        # IndexedDB 存储 + 图片压缩
│       └── components/assistant-ui/  # 聊天 UI 组件（气泡、输入框等）
└── server/
    └── server.js       # Express + Socket.io 服务（内存中转）
```

## 🚀 本地快速启动

### 环境要求

- Node.js ≥ 20（建议 22+）

### 1. 安装依赖

```bash
# 终端 1 —— 后端
cd server
npm install

# 终端 2 —— 前端
cd web
npm install
```

### 2. 启动服务

```bash
# 终端 1 —— 启动后端（默认端口 3001）
cd server
npm start

# 终端 2 —— 启动前端开发服务器（默认端口 5173）
cd web
npm run dev
```

### 3. 打开页面

| 页面 | 地址 | 说明 |
|---|---|---|
| 落地页 | http://localhost:5173 | 产品介绍页，「立即体验」进入聊天 |
| 前台 | http://localhost:5173/chat | 发给朋友 |
| 后台 | http://localhost:5173/admin.html | 口令：`seegud123`，留给自己 |

两个页面各开一个浏览器窗口（或一个开无痕窗口），先自己和自己对一遍戏。

### 方式 B：生产模式（单端口）

```bash
cd web
npm run build        # 构建产物输出到 web/dist/

cd ../server
npm start            # 后端自动托管 dist，监听 3001
```

此时所有页面统一从 **http://localhost:3001** 访问（`/` 落地页、`/chat` 前台、`/admin.html` 后台），无需 Vite。

## 📶 局域网整蛊（同一 WiFi 下开整）

开发模式已开启 `host: true`，同一 WiFi 下朋友的手机可以直接访问你电脑上的服务：

1. 查看你电脑的局域网 IP
   - Windows：`ipconfig` 看「IPv4 地址」（如 `192.168.1.100`）
   - macOS / Linux：`ifconfig` 或 `ip addr`

2. 把这个链接发给朋友（或让他扫码连你的热点后访问）：

   ```
   http://192.168.1.100:5173/chat
   ```

3. 他一发消息，你的后台就会弹出新会话——**开始你的表演**：
   - 别回太快，AI 也有"思考时间"
   - 偶尔打错字再撤回重发更真实（功能没有，自己把握节奏）
   - 图片都支持，他说"你看这张图"你也能看到

4. 等他惊呼"这 AI 也太聪明了吧"，恭喜整蛊成功 🎉

> 💡 **防火墙提示**：如果朋友打不开，大概率是系统防火墙拦了端口。
> - Windows：设置 → 防火墙 → 允许应用通过防火墙 → 勾选 Node.js（专用网络）
> - 或者临时关闭防火墙测试

## ⚙️ 配置项（环境变量）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `3001` | 后端监听端口 |
| `ADMIN_TOKEN` | `seegud123` | 后台登录口令 |

示例（自定义口令启动）：

```bash
# Linux / macOS
PORT=4000 ADMIN_TOKEN=my-secret node server.js

# Windows PowerShell
$env:PORT=4000; $env:ADMIN_TOKEN="my-secret"; node server.js
```

## 🖼️ 图片存储方案

本项目对图片做了「去服务器化」处理：

```
发送方选图 → canvas 压缩（最长边 1600px，WebP ≤280KB）
         → 存入本端浏览器 IndexedDB
         → socket 直传数据给对方（消息里只携带 idb://key 引用）
接收方收到 → 存入自己的 IndexedDB → 渲染时解析为 blob URL
服务器    → 仅内存中转，不写磁盘
```

好处：localStorage 不膨胀、服务器无存储压力、换设备图片自然消失（聊天记录随浏览器走，不留把柄 🙂）。
代价：清了浏览器数据图就没了——毕竟是玩乐项目。

## 🗺️ Roadmap

- [ ] 部署上线（公网也能整，不止局域网）
- [ ] 预设"AI 人格"快捷回复脚本
- [ ] 消息撤回与已读回执

## 🙏 致谢

本项目的部分能力站在开源社区的肩膀上：

- 聊天页面基于 [assistant-ui](https://github.com/assistant-ui/assistant-ui) 修改
- 落地页基于 [astro-emdash-sqlite-r2-starter](https://github.com/milzamsz/astro-emdash-sqlite-r2-starter) 修改

感谢这些优秀的开源项目。

## 📄 License

MIT
