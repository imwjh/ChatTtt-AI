import { useEffect, useRef, useState } from "react";
import { io, type Socket } from "socket.io-client";
import {
  AssistantRuntimeProvider,
  useExternalStoreRuntime,
  type AppendMessage,
  type ThreadMessageLike,
} from "@assistant-ui/react";
import { PanelLeftIcon } from "lucide-react";
import logo from "@/assets/logo.svg";
import { Thread } from "@/components/assistant-ui/thread";
import { UploadImageAttachmentAdapter } from "@/components/assistant-ui/upload-image-adapter";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  SidebarInset,
  SidebarProvider,
} from "@/components/ui/sidebar";
import { cn } from "@/lib/utils";
import {
  blobToDataUri,
  dataUriToBlob,
  expandIdbRefsSync,
  getImage,
  idbKeyOf,
  isIdbRef,
  putImage,
  resolveImageUrl,
} from "@/lib/image-store";

type Msg = {
  id?: string; // 服务器生成的唯一 id，用于本地与服务器历史去重
  from: "user" | "assistant";
  type: "text" | "image" | "audio";
  text?: string;
  imageUrl?: string; // 图片为 `idb://<key>` 引用或外部 URL（不含 dataURI）
  imageKey?: string; // 图片在本端 IndexedDB 的 key
  imageData?: string; // 仅传输时携带的 dataURI 本体，落库前剥除
  audioKey?: string; // 语音在本端 IndexedDB 的 key
  audioData?: string; // 传输用 dataURI 本体
  duration?: number; // 语音时长（秒）
  at: number;
};

function msgToContentParts(m: Pick<Msg, "type" | "text" | "imageUrl" | "audioKey" | "duration">) {
  if (m.type === "image" && m.imageUrl) {
    return [{ type: "image" as const, image: m.imageUrl }];
  }
  if (m.type === "audio") {
    const ref = m.audioKey ? `idb://${m.audioKey}` : (m.imageUrl ?? "");
    return [
      {
        type: "data" as const,
        name: "voice-message",
        data: { ref, duration: m.duration ?? 0 },
      },
    ];
  }
  return [{ type: "text" as const, text: m.text ?? "" }];
}

/** 同上，并把已缓存的 idb:// 引用替换为 blob URL（渲染可用） */
function msgToContent(m: Pick<Msg, "type" | "text" | "imageUrl" | "audioKey" | "duration">) {
  return JSON.parse(expandIdbRefsSync(JSON.stringify(msgToContentParts(m))));
}

type SessionSummary = {
  id: string;
  title: string;
  lastAt: number;
  online: boolean;
  messages?: Msg[]; // admin:joined 时附带的服务器历史
};

const ADMIN_TOKEN_KEY = "chattt-admin-token";

/** 管理端本地存储：每个会话的聊天记录存浏览器 localStorage */
function loadLocalMessages(sessionId: string): Msg[] {
  try {
    return JSON.parse(localStorage.getItem(`chattt-admin:msg:${sessionId}`) ?? "[]");
  } catch {
    return [];
  }
}
function saveLocalMessages(sessionId: string, messages: Msg[]) {
  localStorage.setItem(
    `chattt-admin:msg:${sessionId}`,
    JSON.stringify(messages.slice(-200)),
  );
}
/** 合并本地与服务器历史（按 id / at 去重），按时间排序 */
function mergeMessages(local: Msg[], remote: Msg[]): Msg[] {
  const byKey = new Map<string, Msg>();
  const contentKeyOf = (m: Msg) =>
    `${m.from}:${m.type}:${m.text ?? m.imageUrl ?? m.audioKey ?? ""}`;
  // 服务器回显可能与本地自发记录内容一致（本地 id 是 local-xxx）：
  // 用「内容键 + 时间」识别这类重复，仅去掉紧跟其后的同内容本地占位条目，
  // 避免误删访客真正连发的重复消息
  const remoteKeys = new Map(
    remote.map((m) => [contentKeyOf(m) + "|" + Math.round(m.at / 5000), m]),
  );
  for (const m of [...local, ...remote]) {
    const key = m.id ?? `${m.at}:${m.from}:${m.text ?? m.imageUrl ?? ""}`;
    const ck = contentKeyOf(m) + "|" + Math.round(m.at / 5000);
    if (
      m.id?.startsWith("local-") &&
      remoteKeys.has(ck) &&
      Math.abs(remoteKeys.get(ck)!.at - m.at) < 5000
    ) {
      continue; // 本地占位条目，服务器版本已存在，跳过
    }
    byKey.set(key, m.id ? m : { ...m, id: key });
  }
  return [...byKey.values()].sort((a, b) => a.at - b.at);
}
function loadSessionSummaries(): SessionSummary[] {
  try {
    return JSON.parse(localStorage.getItem("chattt-admin:sessions") ?? "[]");
  } catch {
    return [];
  }
}

export default function AdminApp() {
  const socketRef = useRef<Socket | null>(null);
  const [authed, setAuthed] = useState(false);
  const [tokenInput, setTokenInput] = useState("");
  const [sessions, setSessions] = useState<SessionSummary[]>(loadSessionSummaries);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ThreadMessageLike[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [visitorTyping, setVisitorTyping] = useState(false);
  // 侧边栏折叠（持久化）+ 未读会话集合 + 红点闪烁计数
  const [collapsed, setCollapsed] = useState(
    () => localStorage.getItem("chattt-admin:sidebar-collapsed") === "1",
  );
  const [unread, setUnread] = useState<Set<string>>(new Set());
  const [flash, setFlash] = useState(0);
  const activeRef = useRef<string | null>(null);
  const typingTimerRef = useRef<number | undefined>(undefined);

  activeRef.current = activeId;

  const toggleCollapsed = () => {
    setCollapsed((c) => {
      localStorage.setItem("chattt-admin:sidebar-collapsed", c ? "0" : "1");
      return !c;
    });
  };

  // ---------- Socket 连接 ----------
  useEffect(() => {
    const saved = localStorage.getItem(ADMIN_TOKEN_KEY);
    if (!saved) return;
    connect(saved);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function connect(token: string) {
    const socket = io("/");
    socketRef.current = socket;

    socket.on("connect", () => {
      socket.emit("admin:join", { token });
    });

    socket.on("admin:joined", ({ sessions: list }: { sessions: SessionSummary[] }) => {
      setAuthed(true);
      localStorage.setItem(ADMIN_TOKEN_KEY, token);
      // 合并服务器列表与本地记录（保留历史离线会话），并把服务器历史消息并入本地
      setSessions((prev) => {
        const map = new Map(prev.map((s) => [s.id, s]));
        for (const s of list) {
          if (s.messages?.length) {
            // 图片/语音本体落 IndexedDB，剥除传输用 dataURI 后再合并
            for (const m of s.messages) {
              if (m.imageKey && m.imageData) {
                void putImage(m.imageKey, dataUriToBlob(m.imageData)).then(() =>
                  resolveImageUrl(`idb://${m.imageKey}`).catch(() => undefined),
                );
                m.imageUrl = `idb://${m.imageKey}`;
              }
              if (m.audioKey && m.audioData) {
                void putImage(m.audioKey, dataUriToBlob(m.audioData)).then(() =>
                  resolveImageUrl(`idb://${m.audioKey}`).catch(() => undefined),
                );
                m.imageUrl = `idb://${m.audioKey}`;
              }
            }
            const stripped = s.messages.map(({ imageData: _d, audioData: _a, ...m }) => {
              void _d;
              void _a;
              return m;
            });
            const mergedMsgs = mergeMessages(loadLocalMessages(s.id), stripped);
            saveLocalMessages(s.id, mergedMsgs);
          }
          const { messages: _drop, ...summary } = s;
          void _drop;
          map.set(s.id, { ...map.get(s.id), ...summary });
        }
        const merged = [...map.values()].sort((a, b) => b.lastAt - a.lastAt);
        localStorage.setItem("chattt-admin:sessions", JSON.stringify(merged));
        return merged;
      });
    });

    socket.on("admin:denied", () => {
      localStorage.removeItem(ADMIN_TOKEN_KEY);
      alert("口令错误");
    });

    // 新会话出现在列表
    socket.on("admin:session-updated", (summary: SessionSummary) => {
      setSessions((prev) => {
        const idx = prev.findIndex((s) => s.id === summary.id);
        let next: SessionSummary[];
        if (idx >= 0) {
          next = [...prev];
          next[idx] = { ...next[idx], ...summary };
        } else {
          next = [{ ...summary, title: "新对话" }, ...prev];
        }
        next.sort((a, b) => b.lastAt - a.lastAt);
        localStorage.setItem("chattt-admin:sessions", JSON.stringify(next));
        return next;
      });
    });

    // 收到新消息（访客或自己回显）
    socket.on("admin:new-message", async ({ sessionId, message }: { sessionId: string; message: Msg }) => {
      // 图片/语音本体落本端 IndexedDB，消息里只留 idb:// 引用
      if (message.imageKey && message.imageData) {
        await putImage(message.imageKey, dataUriToBlob(message.imageData));
        message.imageUrl = `idb://${message.imageKey}`;
        await resolveImageUrl(message.imageUrl);
      }
      if (message.audioKey && message.audioData) {
        await putImage(message.audioKey, dataUriToBlob(message.audioData));
        message.imageUrl = `idb://${message.audioKey}`;
        await resolveImageUrl(message.imageUrl);
      }

      // 更新该会话标题（首条用户消息：>10 字符截断加 ...，≤10 显示全文）
      if (message.from === "user" && message.type === "text") {
        setSessions((prev) => {
          const idx = prev.findIndex((s) => s.id === sessionId);
          if (idx < 0 || prev[idx].title !== "新对话") return prev;
          const t = (message.text ?? "").trim();
          const title = t.length > 10 ? `${t.slice(0, 10)}...` : (t || "新对话");
          const next = [...prev];
          next[idx] = { ...next[idx], title };
          localStorage.setItem("chattt-admin:sessions", JSON.stringify(next));
          return next;
        });
      }

      // 只有当前打开的会话才追加显示
      if (activeRef.current === sessionId) {
        setMessages((prev) => {
          const nextMsg: ThreadMessageLike = {
            role: message.from === "user" ? "user" : "assistant",
            content: msgToContent(message),
          };
          const merged = [...prev, nextMsg];
          setIsRunning(false);
          return merged;
        });
        setVisitorTyping(false);
      } else if (message.from === "user") {
        // 非当前会话的访客消息 → 记未读，红点闪一下
        setUnread((prev) => {
          if (prev.has(sessionId)) return prev;
          const next = new Set(prev);
          next.add(sessionId);
          return next;
        });
        setFlash((f) => f + 1);
      }

      // 所有会话都落本地（剥除 dataURI 本体，只留引用）
      const { imageData: _drop, ...localMsg } = message;
      void _drop;
      const local = loadLocalMessages(sessionId);
      local.push(localMsg);
      saveLocalMessages(sessionId, local);
    });

    // 服务器返回的会话历史（打开会话时拉取）
    socket.on("admin:history-result", async ({ sessionId, messages: history }: { sessionId: string; messages: Msg[] }) => {
      // 图片/语音本体先落 IndexedDB，并剥除传输用 dataURI
      await Promise.all(
        history.map(async (m) => {
          if (m.imageKey && m.imageData) {
            await putImage(m.imageKey, dataUriToBlob(m.imageData));
            m.imageUrl = `idb://${m.imageKey}`;
            await resolveImageUrl(m.imageUrl).catch(() => undefined);
          }
          if (m.audioKey && m.audioData) {
            await putImage(m.audioKey, dataUriToBlob(m.audioData));
            m.imageUrl = `idb://${m.audioKey}`;
            await resolveImageUrl(m.imageUrl).catch(() => undefined);
          }
        }),
      );
      const stripped = history.map(({ imageData: _d, audioData: _a, ...m }) => {
        void _d;
        void _a;
        return m;
      });
      const merged = mergeMessages(loadLocalMessages(sessionId), stripped);
      saveLocalMessages(sessionId, merged);
      if (activeRef.current === sessionId) {
        setMessages(
          merged.map((m) => ({
            role: m.from === "user" ? ("user" as const) : ("assistant" as const),
            content: msgToContent(m),
          })),
        );
      }
    });

    socket.on("admin:visitor-typing", ({ sessionId }: { sessionId: string }) => {
      if (activeRef.current !== sessionId) return;
      setVisitorTyping(true);
      window.clearTimeout(typingTimerRef.current);
      typingTimerRef.current = window.setTimeout(() => setVisitorTyping(false), 2500);
    });

    // 服务器确认删除（任意管理窗口触发）：列表移除 + 本地记录清理
    socket.on("admin:session-deleted", ({ sessionId }: { sessionId: string }) => {
      removeSessionLocal(sessionId);
    });
  }

  /** 删除会话：通知服务器 + 本地列表/记录/未读清理（本地立即生效，不等服务器回包） */
  function deleteSession(id: string) {
    // 防误删：确认一次
    if (!window.confirm("确定删除这个会话吗？聊天记录将一并清除。")) return;
    socketRef.current?.emit("admin:delete-session", { sessionId: id });
    removeSessionLocal(id);
  }

  function removeSessionLocal(id: string) {
    // 正在查看该会话 → 清空对话区并取消选中
    if (activeRef.current === id) {
      setActiveId(null);
      activeRef.current = null;
      setMessages([]);
      setVisitorTyping(false);
    }
    setSessions((prev) => {
      const next = prev.filter((s) => s.id !== id);
      localStorage.setItem("chattt-admin:sessions", JSON.stringify(next));
      return next;
    });
    setUnread((prev) => {
      if (!prev.has(id)) return prev;
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
    // 清理该会话的本地聊天记录
    localStorage.removeItem(`chattt-admin:msg:${id}`);
  }

  // ---------- 切换会话 ----------
  function openSession(id: string) {
    setActiveId(id);
    activeRef.current = id;
    setVisitorTyping(false);
    // 打开会话即清除未读
    setUnread((prev) => {
      if (!prev.has(id)) return prev;
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
    // 本地记录优先展示：先预热图片缓存（idb:// → blob URL），再交给渲染层
    const local = loadLocalMessages(id);
    void Promise.all(
      local.map((m) =>
        m.imageUrl && isIdbRef(m.imageUrl)
          ? resolveImageUrl(m.imageUrl).catch(() => undefined)
          : undefined,
      ),
    ).then(() => {
      // 仅在用户仍停留在该会话时更新（切换快时避免串台）
      if (activeRef.current !== id) return;
      setMessages(
        local.map((m) => ({
          role: m.from === "user" ? ("user" as const) : ("assistant" as const),
          content: msgToContent(m),
        })),
      );
    });
    // 先用文本消息占位渲染，避免空白
    setMessages(
      local
        .filter((m) => m.type === "text")
        .map((m) => ({
          role: m.from === "user" ? ("user" as const) : ("assistant" as const),
          content: msgToContent(m),
        })),
    );
    // 再向服务器拉全量历史合并（覆盖管理端离线期间漏掉的消息）
    socketRef.current?.emit("admin:history", { sessionId: id });
  }

  // ---------- 回复 ----------
  const onSend = async (message: AppendMessage) => {
    const sessionId = activeRef.current;
    const socket = socketRef.current;
    if (!sessionId || !socket) return;

    const textPart = message.content.find((p) => p.type === "text");

    // 图片提取：附件在 message.attachments（content 含 image part），content 里也可能有
    type ImagePartLike = { type: string; image?: string };
    type AttachmentLike = { content?: ReadonlyArray<ImagePartLike> };
    const attachmentParts = (
      (message as unknown as { attachments?: ReadonlyArray<AttachmentLike> })
        .attachments ?? []
    ).flatMap((a) => a.content ?? []);
    const images = [
      ...message.content.filter((p) => p.type === "image"),
      ...attachmentParts.filter((p) => p.type === "image"),
    ].map((p) => String((p as ImagePartLike).image));

    // 文本消息
    if (textPart && textPart.text.trim()) {
      socket.emit("admin:message", {
        sessionId,
        type: "text",
        text: textPart.text,
      });
      const localText: Msg = {
        id: `local-${Date.now().toString(36)}-t`,
        from: "assistant",
        type: "text",
        text: textPart.text,
        at: Date.now(),
      };
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: [{ type: "text", text: textPart.text }] },
      ]);
      const local = loadLocalMessages(sessionId);
      local.push(localText);
      saveLocalMessages(sessionId, local);
    }

    // 图片消息：逐张发送（压缩与存储已由适配器在本端 IndexedDB 完成）
    for (const [i, raw] of images.entries()) {
      let imageKey: string | undefined;
      let imageData: string | undefined;
      let imageUrl: string | undefined;
      if (isIdbRef(raw)) {
        imageKey = idbKeyOf(raw);
        const blob = await getImage(imageKey);
        imageData = blob ? await blobToDataUri(blob) : undefined;
        imageUrl = raw;
      } else {
        imageUrl = raw;
      }

      if (imageUrl && isIdbRef(imageUrl)) {
        await resolveImageUrl(imageUrl).catch(() => undefined);
      }

      const msg: Msg = {
        id: `local-${Date.now().toString(36)}-${i}`,
        from: "assistant",
        type: "image",
        imageUrl,
        imageKey,
        at: Date.now(),
      };

      socket.emit("admin:message", {
        sessionId,
        type: "image",
        ...(isIdbRef(raw) ? { imageKey, imageData } : { imageUrl }),
      });

      // 立即显示：必须用展开后的 blob URL（idb:// 会被 assistant-ui 丢弃）
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: msgToContent(msg),
        },
      ]);
      const local = loadLocalMessages(sessionId);
      local.push(msg);
      saveLocalMessages(sessionId, local);
    }

    // 语音消息（录音按钮产生）：从本端 IndexedDB 取出本体发送，无需等待回复
    const voicePart = message.content.find(
      (p) =>
        (p as { type?: string; name?: string }).type === "data" &&
        (p as { name?: string }).name === "voice-message",
    ) as { data?: { ref?: string; duration?: number } } | undefined;
    if (voicePart?.data) {
      const { ref, duration } = voicePart.data;
      let audioKey: string | undefined;
      let audioData: string | undefined;
      if (ref && isIdbRef(ref)) {
        audioKey = idbKeyOf(ref);
        const blob = await getImage(audioKey);
        audioData = blob ? await blobToDataUri(blob) : undefined;
      }
      socket.emit("admin:message", {
        sessionId,
        type: "audio",
        imageUrl: ref,
        audioKey,
        audioData,
        duration,
      });
      const localVoice: Msg = {
        id: `local-${Date.now().toString(36)}-v`,
        from: "assistant",
        type: "audio",
        imageUrl: ref,
        audioKey,
        duration,
        at: Date.now(),
      };
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant" as const,
          content: msgToContent(localVoice),
        },
      ]);
      const localV = loadLocalMessages(sessionId);
      localV.push(localVoice);
      saveLocalMessages(sessionId, localV);
      return;
    }

    // 纯空消息保护
    if (!images.length && !textPart?.text?.trim()) return;
  };

  const runtime = useExternalStoreRuntime({
    messages,
    isRunning,
    convertMessage: (m) => m,
    onNew: onSend,
    onCancel: async () => {},
    adapters: {
      attachments: new UploadImageAttachmentAdapter(),
    },
  });

  // 主题预应用
  useEffect(() => {
    const saved = localStorage.getItem("chattt-theme");
    if (
      saved === "dark" ||
      (saved !== "light" &&
        window.matchMedia("(prefers-color-scheme: dark)").matches)
    ) {
      document.documentElement.classList.add("dark");
    }
  }, []);

  // ---------- 登录界面 ----------
  if (!authed) {
    return (
      <div className="bg-background flex h-dvh items-center justify-center">
        <form
          className="border-border flex w-80 flex-col gap-3 rounded-2xl border p-6 shadow-sm"
          onSubmit={(e) => {
            e.preventDefault();
            connect(tokenInput);
          }}
        >
          <div className="flex items-center justify-center gap-2 pb-1">
            <img src={logo} alt="" className="size-8 rounded-lg bg-white p-0.5 ring-1 ring-border" />
            <span className="font-semibold">ChatTtt AI · 管理后台</span>
          </div>
          <Input
            type="password"
            placeholder="管理口令"
            value={tokenInput}
            onChange={(e) => setTokenInput(e.target.value)}
            autoFocus
          />
          <Button type="submit">进入</Button>
        </form>
      </div>
    );
  }

  // ---------- 主界面 ----------
  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <SidebarProvider>
        <div className="flex h-dvh w-full pr-0.5">
          {/* 左侧：访客列表（可折叠） */}
          <aside
            className={cn(
              "border-border/60 bg-sidebar text-sidebar-foreground flex shrink-0 flex-col border-e transition-[width] duration-200",
              collapsed ? "w-14" : "w-64",
            )}
          >
            <div
              className={cn(
                "border-b p-2",
                collapsed ? "flex flex-col items-center gap-1" : "flex items-center justify-between",
              )}
            >
              {!collapsed && (
                <span className="px-1 text-sm font-semibold">访客会话</span>
              )}
              <div className={cn("flex items-center", collapsed && "flex-col gap-1")}>
                {/* 折叠开关；折叠且有未读时图标右上角红点 */}
                <button
                  onClick={toggleCollapsed}
                  aria-label={collapsed ? "展开侧边栏" : "收起侧边栏"}
                  className="hover:bg-sidebar-accent text-muted-foreground hover:text-foreground relative rounded-md p-2 transition-colors"
                >
                  <PanelLeftIcon className="size-4" />
                  {collapsed && unread.size > 0 && (
                    <span
                      key={flash}
                      className="animate-unread-flash absolute top-1 right-1 size-2 rounded-full bg-red-500"
                    />
                  )}
                </button>
                {!collapsed && <ThemeToggle />}
              </div>
            </div>

            <div className="flex-1 overflow-y-auto p-2">
              {sessions.length === 0 && !collapsed && (
                <p className="text-muted-foreground px-2 py-4 text-sm">
                  暂无访客，等有人来聊吧
                </p>
              )}
              {sessions.map((s) => {
                const hasUnread = unread.has(s.id);
                return (
                  <div
                    key={s.id}
                    className="group/session relative mb-0.5 flex items-center"
                  >
                    <button
                      onClick={() => openSession(s.id)}
                      title={collapsed ? s.title : undefined}
                      className={cn(
                        "hover:bg-sidebar-accent flex min-w-0 flex-1 items-center gap-2 rounded-md px-2.5 py-2 text-start text-sm transition-colors",
                        activeId === s.id && "bg-sidebar-accent",
                        collapsed && "justify-center px-0",
                      )}
                    >
                      <span
                        className={cn(
                          "size-2 shrink-0 rounded-full",
                          s.online ? "bg-green-500" : "bg-zinc-400",
                        )}
                        aria-label={s.online ? "在线" : "离线"}
                      />
                      {!collapsed && (
                        <>
                          <span className="min-w-0 flex-1 truncate">{s.title}</span>
                          {hasUnread && (
                            <span
                              key={flash}
                              className="animate-unread-flash size-1.5 shrink-0 rounded-full bg-red-500"
                            />
                          )}
                        </>
                      )}
                      {collapsed && hasUnread && (
                        <span
                          key={flash}
                          className="animate-unread-flash absolute -top-0.5 right-1 size-2 rounded-full bg-red-500"
                        />
                      )}
                    </button>
                    {/* 悬停显示的删除按钮 */}
                    <button
                      onClick={() => deleteSession(s.id)}
                      aria-label="删除会话"
                      title="删除会话"
                      className={cn(
                        "text-muted-foreground hover:text-destructive hover:bg-sidebar-accent absolute end-1 z-10 hidden rounded-md p-1.5 group-hover/session:block",
                        activeId === s.id && "end-9 bg-sidebar-accent",
                      )}
                    >
                      <svg
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.8"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        className="size-4"
                      >
                        <path d="M3 6h18" />
                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
                        <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                        <path d="M10 11v6" />
                        <path d="M14 11v6" />
                      </svg>
                    </button>
                  </div>
                );
              })}
            </div>

            {!collapsed && (
              <div className="text-muted-foreground border-t p-3 text-xs">
                口令保存在本机浏览器，不会上传
              </div>
            )}
          </aside>

          {/* 右侧：对话区（与用户端同一套 Thread 组件） */}
          <SidebarInset>
            <header className="border-border/60 flex h-14 shrink-0 items-center gap-2 border-b px-3">
              <img src={logo} alt="ChatTtt AI" className="size-6" />
              <span className="font-semibold">ChatTtt AI 后台</span>
              {activeId && (
                <span className="text-muted-foreground ms-2 truncate text-sm">
                  {visitorTyping ? "对方正在输入…" : sessions.find((s) => s.id === activeId)?.title}
                </span>
              )}
            </header>
            <div className="relative flex-1 overflow-hidden">
              {activeId ? (
                <Thread welcomeOverride="回复这位访客…" bubbleLayout="flipped" hideAssistantActions />
              ) : (
                <div className="text-muted-foreground flex h-full items-center justify-center text-sm">
                  ← 从左侧选择一个访客开始对话
                </div>
              )}
            </div>
          </SidebarInset>
        </div>
      </SidebarProvider>
    </AssistantRuntimeProvider>
  );
}

// 稳定引用 helper（避免每次渲染重建 onNew）
import { useCallback } from "react";
function useCallbackRef<T extends (...args: never[]) => unknown>(fn: T): T {
  const ref = useRef(fn);
  ref.current = fn;
  return useCallback(((...args: Parameters<T>) => ref.current(...args)) as T, []);
}
void useCallbackRef;

// ---------- 挂载入口 ----------
import { createRoot } from "react-dom/client";
import "./index.css";

createRoot(document.getElementById("root")!).render(<AdminApp />);
