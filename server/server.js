import http from "node:http";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import express from "express";
import { Server as SocketServer } from "socket.io";
import multer from "multer";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = process.env.PORT || 3001;
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "seegud123"; // 管理端口令，部署时用环境变量覆盖
const MAX_PENDING = parseInt(process.env.MAX_PENDING || "20", 10); // 同时接待上限（等待回复的会话数）
const UPLOAD_DIR = path.join(__dirname, "uploads");
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// ---------- 图片上传 ----------
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || "") || ".png";
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    if (/^image\//.test(file.mimetype)) cb(null, true);
    else cb(new Error("只允许上传图片"));
  },
});

// ---------- HTTP ----------
const app = express();
const httpServer = http.createServer(app);
const io = new SocketServer(httpServer, {
  cors: { origin: true, credentials: true },
  maxHttpBufferSize: 10 * 1024 * 1024, // 图片经前端压缩后以 dataURI 直传，放宽上限
});

app.use("/uploads", express.static(UPLOAD_DIR));

// 管理端鉴权（简单令牌，玩乐项目够用）
function requireAdmin(req, res, next) {
  const token = req.headers["x-admin-token"] ?? req.query.token;
  if (token === ADMIN_TOKEN) return next();
  res.status(401).json({ error: "unauthorized" });
}

// 图片上传：用户端与管理端共用
app.post("/upload", (req, res, next) => {
  const token = req.headers["x-admin-token"];
  // 用户无需令牌；管理端带令牌即可（都允许）
  void token;
  next();
}, upload.single("file"), (req, res) => {
  if (!req.file) return res.status(400).json({ error: "no file" });
  res.json({ url: `/uploads/${req.file.filename}` });
});

// 生产环境托管前端构建产物
// extensions: 无后缀访问 /chat 自动命中 chat.html
const distDir = path.join(__dirname, "..", "web", "dist");
if (fs.existsSync(distDir)) {
  app.use(express.static(distDir, { extensions: ["html"] }));
}

// ---------- Socket.io ----------
/**
 * 会话模型（内存）：
 * sessions: Map<sessionId, {
 *   visitorSocketId | null,   // 访客当前连接
 *   messages: [{ from, type, text?, imageUrl?, at }],
 *   title,                    // 最新用户文本消息（>10 字符截断加 ...）
 * }>
 */
const sessions = new Map();

function makeTitle(text) {
  const t = (text ?? "").trim();
  // 超过 10 个字符截断加 ...，否则显示完整内容
  if (!t) return "新对话";
  return t.length > 10 ? `${t.slice(0, 10)}...` : t;
}

function sessionSummary(s) {
  return {
    id: s.id,
    title: s.title,
    lastAt: s.messages.length ? s.messages[s.messages.length - 1].at : s.createdAt,
    online: !!s.visitorSocketId,
  };
}

let nextSessionSeq = 1;

/** 生成消息 id（用于管理端本地与服务器历史去重） */
function makeMsgId() {
  return `m${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

/**
 * 并发接待统计：「占用中」= 访客在线、且最后一条消息还没等到管理端回复的会话。
 * 管理端回复某会话后，该会话自动释放名额。
 */
function countPendingSessions() {
  let n = 0;
  for (const s of sessions.values()) {
    if (
      s.visitorSocketId &&
      s.messages.length > 0 &&
      s.messages[s.messages.length - 1].from === "user"
    ) {
      n++;
    }
  }
  return n;
}

function broadcastStats() {
  io.to("admins").emit("admin:stats", {
    pending: countPendingSessions(),
    limit: MAX_PENDING,
  });
}

io.on("connection", (socket) => {
  let role = null; // 'visitor' | 'admin'
  let sessionId = null;

  // ----- 访客接入 -----
  socket.on("visitor:join", ({ sessionId: sid }) => {
    role = "visitor";
    sessionId = sid || `s${nextSessionSeq++}-${Date.now().toString(36)}`;

    if (!sessions.has(sessionId)) {
      sessions.set(sessionId, {
        id: sessionId,
        title: "新对话",
        visitorSocketId: null,
        messages: [],
        createdAt: Date.now(),
      });
    }
    const session = sessions.get(sessionId);
    session.visitorSocketId = socket.id;
    socket.join(sessionId);

    socket.emit("visitor:joined", {
      sessionId,
      messages: session.messages,
    });
    io.to("admins").emit("admin:session-updated", sessionSummary(session));
  });

  // ----- 管理端接入 -----
  socket.on("admin:join", ({ token }) => {
    if (token !== ADMIN_TOKEN) {
      socket.emit("admin:denied");
      return;
    }
    role = "admin";
    socket.join("admins");

    const list = [...sessions.values()].sort(
      (a, b) =>
        (b.messages.at(-1)?.at ?? b.createdAt) -
        (a.messages.at(-1)?.at ?? a.createdAt),
    );
    // 附带每个会话的完整消息（管理端本地合并去重用）
    socket.emit("admin:joined", {
      sessions: list.map((s) => ({
        ...sessionSummary(s),
        messages: s.messages,
      })),
    });
  });

  // ----- 管理端拉取单个会话历史 -----
  socket.on("admin:history", ({ sessionId: sid }) => {
    if (role !== "admin") return;
    const session = sessions.get(sid);
    if (!session) return;
    socket.emit("admin:history-result", {
      sessionId: sid,
      messages: session.messages,
    });
  });

  // ----- 管理端删除会话 -----
  socket.on("admin:delete-session", ({ sessionId: sid }) => {
    if (role !== "admin") return;
    if (!sessions.has(sid)) return;
    sessions.delete(sid);
    // 通知所有管理窗口从列表移除
    io.to("admins").emit("admin:session-deleted", { sessionId: sid });
  });

  // ----- 访客发消息 -----
  // 图片策略：前端压缩后以 dataURI 直传（imageData），服务器仅内存中转、不落盘；
  // 消息里的 imageUrl 是 `idb://<key>` 引用，双方各自把本体存进自己的 IndexedDB
  socket.on("visitor:message", ({ type, text, imageUrl, imageKey, imageData, audioKey, audioData, duration }) => {
    if (role !== "visitor" || !sessionId) return;
    const session = sessions.get(sessionId);
    if (!session) return;

    const msg = {
      id: makeMsgId(),
      from: "user",
      type: type === "image" ? "image" : type === "audio" ? "audio" : "text",
      ...(type === "image"
        ? { imageUrl: imageKey ? `idb://${imageKey}` : imageUrl, imageKey, imageData }
        : type === "audio"
          ? { imageUrl: audioKey ? `idb://${audioKey}` : undefined, audioKey, audioData, duration }
          : { text }),
      at: Date.now(),
    };
    session.messages.push(msg);

    // 标题跟随最新的用户文本消息（>10 字符截断加 ...，≤10 显示全文）
    if (msg.type === "text") {
      session.title = makeTitle(msg.text);
    }

    io.to("admins").emit("admin:new-message", { sessionId, message: msg });
    io.to("admins").emit("admin:session-updated", sessionSummary(session));

    // 后台无人在线时告知访客当前无法收到回复
    const adminCount = io.of("/").adapter.rooms.get("admins")?.size ?? 0;
    if (adminCount === 0) {
      socket.emit("visitor:error", { code: "admin-offline" });
    }
  });

  // ----- 访客打字状态 -----
  socket.on("visitor:typing", () => {
    if (role !== "visitor" || !sessionId) return;
    io.to("admins").emit("admin:visitor-typing", { sessionId });
  });

  // ----- 管理端回复 -----
  // 图片同访客：dataURI 直传内存中转，不落盘
  socket.on("admin:message", ({ sessionId: sid, type, text, imageUrl, imageKey, imageData, audioKey, audioData, duration }) => {
    if (role !== "admin") return;
    const session = sessions.get(sid);
    if (!session) return;

    const msg = {
      id: makeMsgId(),
      from: "assistant",
      type: type === "image" ? "image" : type === "audio" ? "audio" : "text",
      ...(type === "image"
        ? { imageUrl: imageKey ? `idb://${imageKey}` : imageUrl, imageKey, imageData }
        : type === "audio"
          ? { imageUrl: audioKey ? `idb://${audioKey}` : undefined, audioKey, audioData, duration }
          : { text }),
      at: Date.now(),
    };
    session.messages.push(msg);

    // 推给访客
    if (session.visitorSocketId) {
      io.to(session.visitorSocketId).emit("visitor:new-message", {
        sessionId: sid,
        message: msg,
      });
    }
    // 回显给其他管理窗口（socket.to 不含发送者自身，避免重复）
    socket.to("admins").emit("admin:new-message", { sessionId: sid, message: msg });
  });

  // ----- 管理端正在输入（用户端显示"正在输入…"气泡）-----
  socket.on("admin:typing", ({ sessionId: sid }) => {
    if (role !== "admin") return;
    const session = sessions.get(sid);
    if (session?.visitorSocketId) {
      io.to(session.visitorSocketId).emit("visitor:typing");
    }
  });

  // ----- 断线 -----
  socket.on("disconnect", () => {
    if (role === "visitor" && sessionId) {
      const session = sessions.get(sessionId);
      if (session && session.visitorSocketId === socket.id) {
        session.visitorSocketId = null;
        io.to("admins").emit("admin:session-updated", sessionSummary(session));
      }
    }
  });
});

httpServer.listen(PORT, () => {
  console.log(`[ChatTtt] server listening on http://localhost:${PORT}`);
});
