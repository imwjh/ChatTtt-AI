import { useEffect, useRef } from "react";
import { io, type Socket } from "socket.io-client";
import {
  AssistantRuntimeProvider,
  WebSpeechDictationAdapter,
  useLocalRuntime,
  useRemoteThreadListRuntime,
  type ChatModelAdapter,
} from "@assistant-ui/react";
import { createLocalStorageAdapter } from "@assistant-ui/core/react";
import type { TitleGenerationAdapter } from "@assistant-ui/core/react";
import logo from "@/assets/logo.svg";
import { Thread } from "@/components/assistant-ui/thread";
import { ThreadListSidebar } from "@/components/assistant-ui/threadlist-sidebar";
import { UploadImageAttachmentAdapter } from "@/components/assistant-ui/upload-image-adapter";
import {
  blobToDataUri,
  dataUriToBlob,
  getImage,
  idbKeyOf,
  isIdbRef,
  putImage,
} from "@/lib/image-store";
import {
  ModelSelector,
  type ModelOption,
} from "@/components/assistant-ui/model-selector";
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";

/** 可选"模型"列表（演示用，实际都由后台真人回复） */
const MODELS: readonly ModelOption[] = [
  {
    id: "little-sunbee-5.3",
    name: "Little Sunbee 5.3",
    description: "轻量模型",
  },
  {
    id: "super-sunbee-5.5",
    name: "Super Sunbee 5.5",
    description: "顶级最强大脑",
  },
  {
    id: "fuck-image-2.1",
    name: "Fuck‑Image 2.1",
    description: "图像识别与生图模型",
  },
];

/** 访客的会话 ID：localStorage 持久化，同一浏览器始终是同一个访客 */
function getVisitorSessionId(): string {
  let sid = localStorage.getItem("chattt-session-id");
  if (!sid) {
    sid = `v-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    localStorage.setItem("chattt-session-id", sid);
  }
  return sid;
}

/** 最后收到的助手消息时间（用于识别断线期间漏掉的后台回复） */
const LAST_ASSISTANT_AT_KEY = "chattt:last-assistant-at";

type ServerMsg = {
  id?: string;
  from: string;
  type: string;
  text?: string;
  imageUrl?: string;
  imageKey?: string; // 图片在本端 IndexedDB 的 key（双端同 key）
  imageData?: string; // 传输用 dataURI 本体，接收后落 IndexedDB
  at: number;
};

/** 把漏掉的后台回复合并进本地会话存储（落到最近活跃的会话；无会话时新建） */
function mergeMissedReplies(missed: ServerMsg[]): boolean {
  try {
    const threads: {
      remoteId: string;
      status?: string;
      title?: string;
    }[] = JSON.parse(localStorage.getItem("chattt:threads") ?? "[]");

    // 访客还没发过消息（threads 为空）：新建一个会话承接后台主动发来的消息
    if (!threads.length) {
      const newId = `__LOCALID_${Math.random().toString(36).slice(2, 9)}`;
      threads.push({
        remoteId: newId,
        status: "regular",
        title: "来自后台的消息…",
      });
      localStorage.setItem("chattt:threads", JSON.stringify(threads));
    }

    // 目标：消息最新的会话
    let targetId = threads[0].remoteId;
    let targetAt = 0;
    for (const t of threads) {
      try {
        const repo = JSON.parse(localStorage.getItem(`chattt:messages:${t.remoteId}`) ?? "{}");
        const last = repo.messages?.at(-1);
        const at = last ? Date.parse(last.message.createdAt) : 0;
        if (at > targetAt) {
          targetAt = at;
          targetId = t.remoteId;
        }
      } catch {
        /* 忽略损坏的会话存储 */
      }
    }

    const key = `chattt:messages:${targetId}`;
    const repo = JSON.parse(localStorage.getItem(key) ?? "{}");
    const list: { parentId: string | null; message: Record<string, unknown> }[] =
      repo.messages ?? [];
    for (const m of missed) {
      list.push({
        parentId: list.length ? (list[list.length - 1].message.id as string) : null,
        message: {
          id: `srv-${m.id ?? m.at}`,
          createdAt: new Date(m.at).toISOString(),
          role: "assistant",
          content:
            m.type === "image"
              ? [{ type: "image", image: m.imageUrl }]
              : [{ type: "text", text: m.text ?? "" }],
          // assistant 消息必须带 status 才会被存储适配器解析
          status: { type: "complete", reason: "stop" },
          attachments: [],
          metadata: { custom: {} },
        },
      });
    }
    repo.messages = list;
    repo.headId = list.length ? list[list.length - 1].message.id : undefined;
    localStorage.setItem(key, JSON.stringify(repo));
    return true;
  } catch {
    return false;
  }
}

/**
 * 模型适配器：把用户发出的消息经 Socket.io 转给后台真人；
 * 真人的回复通过 socket 事件回流，以流式形式追加到当前运行。
 */
const createSocketAdapter = (getSocket: () => Socket | null): ChatModelAdapter => ({
  async *run({ messages, abortSignal }) {
    const socket = getSocket();
    const last = messages[messages.length - 1];
    const textPart = last?.content.find((p) => p.type === "text");
    const imagePart = last?.content.find((p) => p.type === "image");

    if (!socket) {
      yield { content: [{ type: "text", text: "（服务未连接，请稍后重试）" }] };
      return;
    }

    // 发送给后台
    if (imagePart) {
      // 图片本体存本端 IndexedDB（引用 idb://key）；
      // 发送时从 IndexedDB 取出转 dataURI 附带，接收方落自己的 IndexedDB
      const raw = String(imagePart.image);
      let imageKey: string | undefined;
      let imageData: string | undefined;
      let imageUrl: string | undefined;
      if (isIdbRef(raw)) {
        imageKey = idbKeyOf(raw);
        const blob = await getImage(imageKey);
        imageData = blob ? await blobToDataUri(blob) : undefined;
      } else {
        imageUrl = raw;
      }
      socket.emit("visitor:message", {
        type: "image",
        imageUrl,
        imageKey,
        imageData,
      });
    }
    if (textPart && textPart.text.trim()) {
      socket.emit("visitor:message", { type: "text", text: textPart.text });
    }
    if (!textPart?.text?.trim() && !imagePart) return;

    // 等待真人回复（流式：这里按整条接收；后台逐条发时前端自然分段）
    const reply = await new Promise<
      {
        from: string;
        type: string;
        text?: string;
        imageUrl?: string;
        imageKey?: string;
        imageData?: string;
      } | null
    >((resolve) => {
        const onMessage = (payload: { message: ServerMsg & { at?: number } }) => {
          if (payload.message.from !== "assistant") return;
          if (payload.message.at) {
            localStorage.setItem(LAST_ASSISTANT_AT_KEY, String(payload.message.at));
          }
          cleanup();
          resolve(payload.message);
        };
        const onAbort = () => {
          cleanup();
          resolve(null);
        };
        const cleanup = () => {
          socket.off("visitor:new-message", onMessage);
          abortSignal?.removeEventListener("abort", onAbort);
        };
        socket.on("visitor:new-message", onMessage);
        abortSignal?.addEventListener("abort", onAbort);
      },
    );

    if (!reply || abortSignal?.aborted) return;

    // 打字机效果输出真人回复
    if (reply.type === "image") {
      // 图片本体落本端 IndexedDB，消息里存 idb:// 引用
      let ref = reply.imageUrl ?? "";
      if (reply.imageKey && reply.imageData) {
        await putImage(reply.imageKey, dataUriToBlob(reply.imageData));
        ref = `idb://${reply.imageKey}`;
      }
      yield {
        content: [
          { type: "text", text: "" },
          { type: "image", image: ref },
        ],
      };
      return;
    }
    const full = reply.text ?? "";
    let acc = "";
    for (const char of full) {
      if (abortSignal?.aborted) return;
      acc += char;
      yield { content: [{ type: "text", text: acc }] };
      await new Promise((r) => setTimeout(r, 12 + Math.random() * 20));
    }
    void imagePart;
  },
});

/** 会话命名规则：用户第一句话的前 5 个字符加 … */
const TITLE_GENERATOR: TitleGenerationAdapter = {
  async generateTitle(messages) {
    const firstUser = messages.find((m) => m.role === "user");
    const text =
      firstUser?.content.find((p) => p.type === "text")?.text ?? "";
    const trimmed = text.trim();
    return trimmed ? `${trimmed.slice(0, 5)}…` : "新对话";
  },
};

/** 浏览器本地存储适配器：会话与消息持久化，刷新不丢 */
const storageAdapter = createLocalStorageAdapter({
  storage: {
    getItem: async (key) => localStorage.getItem(key),
    setItem: async (key, value) => localStorage.setItem(key, value),
    removeItem: async (key) => localStorage.removeItem(key),
  },
  prefix: "chattt:",
  titleGenerator: TITLE_GENERATOR,
});

function useAppRuntime() {
  const socketRef = useRef<Socket | null>(null);

  // 建立 Socket 连接（Vite dev 走 proxy，生产同域）
  if (!socketRef.current) {
    socketRef.current = io("/", { autoConnect: true });
  }
  const adapterRef = useRef<ChatModelAdapter>(
    createSocketAdapter(() => socketRef.current),
  );

  useEffect(() => {
    const socket = socketRef.current;
    if (!socket) return;
    socket.emit("visitor:join", { sessionId: getVisitorSessionId() });

    // 断线重连后：用服务器返回的历史补齐漏掉的后台回复
    const onJoined = ({ messages: history }: { messages: ServerMsg[] }) => {
      const lastAt = Number(localStorage.getItem(LAST_ASSISTANT_AT_KEY) ?? 0);
      const missed = history.filter(
        (m) => m.from === "assistant" && m.at > lastAt,
      );
      if (missed.length) {
        // 图片本体先落 IndexedDB（消息里只有 idb:// 引用）
        void Promise.all(
          missed
            .filter((m) => m.imageKey && m.imageData)
            .map((m) => putImage(m.imageKey!, dataUriToBlob(m.imageData!))),
        ).then(() => {
          if (mergeMissedReplies(missed)) {
            localStorage.setItem(
              LAST_ASSISTANT_AT_KEY,
              String(Math.max(...missed.map((m) => m.at))),
            );
            // 数据已直写 localStorage，刷新页面即可看到；这里直接 reload 保证展示一致
            window.location.reload();
          } else {
            const latestAssistant = history
              .filter((m) => m.from === "assistant")
              .at(-1);
            if (latestAssistant && latestAssistant.at > lastAt) {
              localStorage.setItem(
                LAST_ASSISTANT_AT_KEY,
                String(latestAssistant.at),
              );
            }
          }
        });
      } else {
        const latestAssistant = history.filter((m) => m.from === "assistant").at(-1);
        if (latestAssistant && latestAssistant.at > lastAt) {
          localStorage.setItem(LAST_ASSISTANT_AT_KEY, String(latestAssistant.at));
        }
      }
    };
    socket.on("visitor:joined", onJoined);

    // 全局兜底：后台主动推送的消息（当前没有会话运行在等待回复）
    // 延迟 300ms 检查：若已被正在运行的对话消费（水位线更新）则跳过，否则落库并刷新
    const onPushed = (payload: { message: ServerMsg }) => {
      const m = payload.message;
      if (m.from !== "assistant") return;
      if (!m.at || m.at <= Number(localStorage.getItem(LAST_ASSISTANT_AT_KEY) ?? 0))
        return;
      window.setTimeout(async () => {
        if (m.at <= Number(localStorage.getItem(LAST_ASSISTANT_AT_KEY) ?? 0)) return;
        // 图片本体先落 IndexedDB
        if (m.imageKey && m.imageData) {
          await putImage(m.imageKey, dataUriToBlob(m.imageData));
        }
        if (mergeMissedReplies([m])) {
          localStorage.setItem(LAST_ASSISTANT_AT_KEY, String(m.at));
          window.location.reload();
        }
      }, 300);
    };
    socket.on("visitor:new-message", onPushed);

    // 发消息时通知后台"正在输入"
    const onConnect = () => {
      socket.emit("visitor:join", { sessionId: getVisitorSessionId() });
    };
    socket.on("connect", onConnect);
    return () => {
      socket.off("connect", onConnect);
      socket.off("visitor:joined", onJoined);
      socket.off("visitor:new-message", onPushed);
    };
  }, []);

  // 外层：本地持久化会话列表（新建/重命名/删除/切换，刷新不丢）
  // 内层：本地运行时（Socket 回复 + 语音 + 图片附件），自动继承外层的历史存储
  return useRemoteThreadListRuntime({
    adapter: storageAdapter,
    allowNesting: true,
    runtimeHook: function RuntimeHook() {
      return useLocalRuntime(adapterRef.current, {
        adapters: {
          dictation: new WebSpeechDictationAdapter({ language: "zh-CN" }),
          attachments: new UploadImageAttachmentAdapter(),
        },
      });
    },
  });
}

function ChatShell() {
  const [modelId] = [MODELS[0].id];

  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full pr-0.5">
        <ThreadListSidebar />
        <SidebarInset>
          <header className="flex h-14 shrink-0 items-center gap-2 border-b px-3">
            <SidebarTrigger />
            <img src={logo} alt="ChatTtt AI" className="size-6" />
            <ModelSelector models={MODELS} defaultValue={modelId} variant="ghost" size="sm" searchable />
          </header>
          <div className="flex-1 overflow-hidden">
            <Thread />
          </div>
        </SidebarInset>
      </div>
    </SidebarProvider>
  );
}

export default function App() {
  const runtime = useAppRuntime();

  // 刷新后先应用持久化的主题，避免闪白
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

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <ChatShell />
    </AssistantRuntimeProvider>
  );
}
