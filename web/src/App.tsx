import { useEffect, useRef } from "react";
import { io, type Socket } from "socket.io-client";
import {
  AssistantRuntimeProvider,
  useAui,
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
  expandIdbRefs,
  getImage,
  idbKeyOf,
  isIdbRef,
  putImage,
  resolveImageUrl,
  shrinkObjectUrls,
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
  audioKey?: string; // 语音在本端 IndexedDB 的 key
  audioData?: string; // 传输用 dataURI 本体
  duration?: number; // 语音时长（秒）
  at: number;
};

/** 把服务器消息转成本地线程存储的 content parts */
function serverMsgToContent(m: ServerMsg): Array<Record<string, unknown>> {
  if (m.type === "image") {
    return [{ type: "image", image: m.imageUrl ?? `idb://${m.audioKey}` }];
  }
  if (m.type === "audio") {
    return [
      {
        type: "data",
        name: "voice-message",
        data: { ref: m.imageUrl ?? `idb://${m.audioKey}`, duration: m.duration ?? 0 },
      },
    ];
  }
  return [{ type: "text", text: m.text ?? "" }];
}

/** 把漏掉的后台回复合并进本地会话存储；返回目标会话 remoteId（失败返回 null） */
function mergeMissedReplies(missed: ServerMsg[]): string | null {
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
    // 按生成 id 去重：同一条服务器消息只落一次
    const existingIds = new Set(list.map((x) => String(x.message.id)));
    let added = false;
    for (const m of missed) {
      const id = `srv-${m.id ?? m.at}`;
      if (existingIds.has(id)) continue;
      list.push({
        parentId: list.length ? (list[list.length - 1].message.id as string) : null,
        message: {
          id,
          createdAt: new Date(m.at).toISOString(),
          role: "assistant",
          content: serverMsgToContent(m),
          // assistant 消息必须带 status 才会被存储适配器解析
          status: { type: "complete", reason: "stop" },
          attachments: [],
          metadata: { custom: {} },
        },
      });
      existingIds.add(id);
      added = true;
    }
    if (!added) return null;
    repo.messages = list;
    repo.headId = list.length ? list[list.length - 1].message.id : undefined;
    localStorage.setItem(key, JSON.stringify(repo));
    return targetId;
  } catch {
    return null;
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

    // 图片提取：assistant-ui 把附件放在 message.attachments（其 content 含 image part），
    // 老版本/部分路径也可能直接放进 content，两处都取
    const attachmentParts = (
      (last as { attachments?: ReadonlyArray<{ content?: ReadonlyArray<{ type: string; image?: string }> }> })
        ?.attachments ?? []
    ).flatMap((a) => a.content ?? []);
    const images = [
      ...(last?.content ?? []).filter((p) => p.type === "image"),
      ...attachmentParts.filter((p) => p.type === "image"),
    ].map((p) => String((p as { image?: string }).image));

    if (!socket) {
      yield { content: [{ type: "text", text: "（服务未连接，请稍后重试）" }] };
      return;
    }

    // 语音消息（录音按钮产生）：从本端 IndexedDB 取出本体发送。
    // 与文字/图片一致：发完后同样挂起等待真人回复（思考动画 + 回复直接渲染，不整页刷新）
    const voicePart = (last?.content ?? []).find(
      (p) => (p as { type?: string; name?: string }).type === "data" &&
             (p as { name?: string }).name === "voice-message",
    ) as { data?: { ref?: string; duration?: number } } | undefined;
    if (voicePart?.data) {
      const { ref, duration } = voicePart.data;
      let imageKey: string | undefined;
      let imageData: string | undefined;
      if (ref && isIdbRef(ref)) {
        imageKey = idbKeyOf(ref);
        const blob = await getImage(imageKey);
        imageData = blob ? await blobToDataUri(blob) : undefined;
      }
      socket.emit("visitor:message", {
        type: "audio",
        imageUrl: ref,
        audioKey: imageKey,
        audioData: imageData,
        duration,
      });
      // 不 return：继续走下面的等待回复流程
    }

    // 发送给后台：每张图片单独一条消息
    for (const raw of images) {
      // 图片本体存本端 IndexedDB（引用 idb://key）；
      // 发送时从 IndexedDB 取出转 dataURI 附带，接收方落自己的 IndexedDB
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
    // 语音也算已发送的消息（否则纯语音会被提前 return，无法进入等待回复）
    if (!textPart?.text?.trim() && !images.length && !voicePart?.data) return;

    // 等待真人回复（流式：这里按整条接收；后台逐条发时前端自然分段）
    const reply = await new Promise<
      {
        from: string;
        type: string;
        text?: string;
        imageUrl?: string;
        imageKey?: string;
        imageData?: string;
        audioKey?: string;
        audioData?: string;
        duration?: number;
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
        // 后台无人在线：服务器立即回 visitor:error
        const onError = () => {
          cleanup();
          resolve({ from: "system", type: "error" });
        };
        const cleanup = () => {
          socket.off("visitor:new-message", onMessage);
          socket.off("visitor:error", onError);
          abortSignal?.removeEventListener("abort", onAbort);
        };
        socket.on("visitor:new-message", onMessage);
        socket.on("visitor:error", onError);
        abortSignal?.addEventListener("abort", onAbort);
      },
    );

    if (reply && (reply as { from?: string }).from === "system") {
      // 后台离线：抛错走 assistant-ui 预设的网络错误提示（与真实网络断连同款样式与文案）
      throw new TypeError("Failed to fetch");
    }

    if (!reply || abortSignal?.aborted) return;

    // 打字机效果输出真人回复
    if (reply.type === "image") {
      // 图片本体落本端 IndexedDB；显示用 blob URL（可通过 assistant-ui 校验）
      let ref = reply.imageUrl ?? "";
      if (reply.imageKey && reply.imageData) {
        await putImage(reply.imageKey, dataUriToBlob(reply.imageData));
        ref = `idb://${reply.imageKey}`;
      }
      const displayUrl = await resolveImageUrl(ref);
      yield {
        content: [
          { type: "text", text: "" },
          { type: "image", image: displayUrl },
        ],
      };
      return;
    }
    if (reply.type === "audio") {
      // 语音回复：本体落本端 IndexedDB，渲染为语音气泡
      let ref = reply.imageUrl ?? "";
      if (reply.audioKey && reply.audioData) {
        await putImage(reply.audioKey, dataUriToBlob(reply.audioData));
        ref = `idb://${reply.audioKey}`;
      }
      yield {
        content: [
          {
            type: "data",
            name: "voice-message",
            data: { ref, duration: reply.duration ?? 0 },
          },
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
    // 读取时把 idb:// 引用展开成 blob URL；写入时把 blob URL 还原为 idb:// 引用
    getItem: async (key) => {
      const raw = localStorage.getItem(key);
      if (!raw || key.startsWith("chattt:messages:")) {
        return raw ? await expandIdbRefs(raw) : raw;
      }
      return raw;
    },
    setItem: async (key, value) => {
      localStorage.setItem(key, shrinkObjectUrls(value));
    },
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
        // 图片/语音本体先落 IndexedDB（消息里只有 idb:// 引用）
        void Promise.all(
          missed
            .map((m) => {
              if (m.imageKey && m.imageData)
                return putImage(m.imageKey, dataUriToBlob(m.imageData));
              if (m.audioKey && m.audioData)
                return putImage(m.audioKey, dataUriToBlob(m.audioData));
              return undefined;
            })
            .filter(Boolean),
        ).then(() => {
          const targetId = mergeMissedReplies(missed);
          if (targetId) {
            localStorage.setItem(
              LAST_ASSISTANT_AT_KEY,
              String(Math.max(...missed.map((m) => m.at))),
            );
            // reload 后自动恢复到收到消息的会话
            sessionStorage.setItem("chattt:reopen-thread", targetId);
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
        // 图片/语音本体先落 IndexedDB
        if (m.imageKey && m.imageData) {
          await putImage(m.imageKey, dataUriToBlob(m.imageData));
        }
        if (m.audioKey && m.audioData) {
          await putImage(m.audioKey, dataUriToBlob(m.audioData));
        }
        const targetId = mergeMissedReplies([m]);
        if (targetId) {
          localStorage.setItem(LAST_ASSISTANT_AT_KEY, String(m.at));
          // reload 后自动恢复到该会话
          sessionStorage.setItem("chattt:reopen-thread", targetId);
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
          attachments: new UploadImageAttachmentAdapter(),
        },
      });
    },
  });
}

/** 刷新后自动恢复到收到消息的会话（配合 sessionStorage 标记） */
function ReopenThread() {
  const aui = useAui();
  useEffect(() => {
    const id = sessionStorage.getItem("chattt:reopen-thread");
    if (!id) return;
    sessionStorage.removeItem("chattt:reopen-thread");
    let cancelled = false;
    const trySwitch = async () => {
      // 等线程列表加载完成后再切换，最多重试若干次
      for (let i = 0; i < 20 && !cancelled; i++) {
        try {
          await aui.threads.getLoadThreadsPromise();
          await aui.threads.switchToThread(id, { unarchive: true });
          return;
        } catch {
          await new Promise((r) => setTimeout(r, 300));
        }
      }
    };
    void trySwitch();
    return () => {
      cancelled = true;
    };
  }, [aui]);
  return null;
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
            <img src={logo} alt="ChatTtt AI" className="size-6 rounded-md bg-white p-0.5 ring-1 ring-border" />
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
      <ReopenThread />
      <ChatShell />
    </AssistantRuntimeProvider>
  );
}
