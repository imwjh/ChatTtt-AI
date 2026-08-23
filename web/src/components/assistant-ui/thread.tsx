"use client";

import {
  ComposerAddAttachment,
  ComposerAttachments,
  UserMessageAttachments,
} from "@/components/assistant-ui/attachment";
import { Image } from "@/components/assistant-ui/image";
import { TooltipIconButton } from "@/components/assistant-ui/tooltip-icon-button";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import {
  isIdbRef,
  resolveImageUrl,
} from "@/lib/image-store";
import {
  ActionBarPrimitive,
  AuiIf,
  type AssistantState,
  ComposerPrimitive,
  ErrorPrimitive,
  MessagePrimitive,
  ThreadPrimitive,
  type ImageMessagePartComponent,
  useAuiState,
} from "@assistant-ui/react";
import {
  ArrowDownIcon,
  ArrowUpIcon,
  CheckIcon,
  CopyIcon,
  MicIcon,
  SquareIcon,
} from "lucide-react";
import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ComponentType,
  type FC,
} from "react";

export type ThreadComponents = {
  AssistantMessage?: ComponentType | undefined;
  Welcome?: ComponentType | undefined;
  welcomeOverride?: string | undefined;
  /**
   * 气泡布局：normal = 用户右/助手左（默认，用户端）；
   * flipped = 用户左/助手右（管理端，"用户"是访客、"助手"是你自己）
   */
  bubbleLayout?: "normal" | "flipped" | undefined;
};

export type ThreadProps = ThreadComponents;

const EMPTY_COMPONENTS: ThreadComponents = {};

const ThreadComponentsContext =
  createContext<ThreadComponents>(EMPTY_COMPONENTS);

// 空会话（新聊天）时居中显示欢迎语
const isNewChatView = (s: AssistantState) =>
  s.thread.messages.length === 0 &&
  (!s.thread.isLoading || s.threads.isLoading);

export const Thread: FC<ThreadProps> = ({
  Welcome,
  AssistantMessage,
  welcomeOverride,
  bubbleLayout = "normal",
}) => {
  const isEmpty = useAuiState(isNewChatView);

  return (
    <ThreadComponentsContext.Provider
      value={{ Welcome, AssistantMessage, welcomeOverride, bubbleLayout }}
    >
      <ThreadRoot isEmpty={isEmpty} />
    </ThreadComponentsContext.Provider>
  );
};

const ThreadRoot: FC<{ isEmpty: boolean }> = ({ isEmpty }) => {
  const { Welcome = ThreadWelcome } = useContext(ThreadComponentsContext);

  return (
    <ThreadPrimitive.Root
      className="aui-root aui-thread-root bg-background @container flex h-full flex-col"
      style={{
        ["--thread-max-width" as string]: "44rem",
        ["--composer-bg" as string]: "var(--color-card)",
        ["--composer-radius" as string]: "1.5rem",
        ["--composer-padding" as string]: "8px",
      }}
    >
      <ThreadPrimitive.Viewport
        turnAnchor="top"
        data-slot="aui_thread-viewport"
        className="relative flex flex-1 flex-col overflow-x-auto overflow-y-scroll scroll-smooth"
      >
        <div
          className={cn(
            "mx-auto flex w-full max-w-(--thread-max-width) flex-1 flex-col px-4 pt-4",
            isEmpty && "justify-center",
          )}
        >
          <AuiIf condition={isNewChatView}>
            <Welcome />
          </AuiIf>

          <div
            data-slot="aui_message-group"
            className="mb-14 flex flex-col gap-y-6 empty:hidden"
          >
            <ThreadPrimitive.Messages>
              {() => <ThreadMessage />}
            </ThreadPrimitive.Messages>
          </div>

          <ThreadPrimitive.ViewportFooter
            className={cn(
              "aui-thread-viewport-footer bg-background flex flex-col gap-4 overflow-visible pb-4 md:pb-6",
              !isEmpty &&
                "sticky bottom-0 mt-auto rounded-t-(--composer-radius)",
            )}
          >
            <ThreadScrollToBottom />
            <Composer />
          </ThreadPrimitive.ViewportFooter>
        </div>
      </ThreadPrimitive.Viewport>
    </ThreadPrimitive.Root>
  );
};

const ThreadMessage: FC = () => {
  const {
    AssistantMessage: AssistantMessageComponent = DefaultAssistantMessage,
  } = useContext(ThreadComponentsContext);
  const role = useAuiState((s) => s.message.role);

  if (role === "user") return <UserMessage />;
  return <AssistantMessageComponent />;
};

/** 从上下文取气泡布局 */
const useBubbleLayout = () =>
  useContext(ThreadComponentsContext).bubbleLayout ?? "normal";

const ThreadScrollToBottom: FC = () => {
  return (
    <ThreadPrimitive.ScrollToBottom asChild>
      <TooltipIconButton
        tooltip="回到底部"
        variant="outline"
        className="aui-thread-scroll-to-bottom dark:border-border dark:bg-background dark:hover:bg-accent absolute -top-12 z-10 self-center rounded-full p-4 disabled:invisible"
      >
        <ArrowDownIcon />
      </TooltipIconButton>
    </ThreadPrimitive.ScrollToBottom>
  );
};

const ThreadWelcome: FC = () => {
  const { welcomeOverride } = useContext(ThreadComponentsContext);
  return (
    <div className="aui-thread-welcome-root mb-6 flex flex-col items-center px-4 text-center">
      <h1 className="aui-thread-welcome-message-inner fade-in slide-in-from-bottom-1 animate-in fill-mode-both text-2xl font-medium tracking-tight duration-200">
        {welcomeOverride ?? "有什么可以帮你？"}
      </h1>
    </div>
  );
};

const Composer: FC = () => {
  return (
    <ComposerPrimitive.Root className="aui-composer-root relative flex w-full flex-col">
      <ComposerPrimitive.AttachmentDropzone asChild>
        <div
          data-slot="aui_composer-shell"
          className="border-border/60 data-[dragging=true]:border-ring focus-within:border-border dark:border-muted-foreground/15 dark:focus-within:border-muted-foreground/30 flex w-full cursor-text flex-col gap-2 rounded-(--composer-radius) border bg-(--composer-bg) p-(--composer-padding) transition-[border-color] data-[dragging=true]:border-dashed data-[dragging=true]:bg-[color-mix(in_oklab,var(--color-accent)_50%,var(--color-background))]"
        >
          <ComposerAttachments />
          <ComposerPrimitive.Input
            placeholder="输入消息…"
            className="aui-composer-input caret-primary placeholder:text-muted-foreground/60 max-h-48 min-h-10 w-full resize-none bg-transparent px-2.5 py-1 text-base leading-6 outline-none"
            rows={1}
            autoFocus
            enterKeyHint="send"
            aria-label="消息输入框"
          />
          <ComposerAction />
        </div>
      </ComposerPrimitive.AttachmentDropzone>
    </ComposerPrimitive.Root>
  );
};

const ComposerAction: FC = () => {
  return (
    <div className="aui-composer-action-wrapper relative flex items-center justify-between">
      <ComposerAddAttachment />
      <div className="flex items-center gap-1.5">
        <AuiIf condition={(s) => s.thread.capabilities.dictation}>
          <AuiIf condition={(s) => s.composer.dictation == null}>
            <ComposerPrimitive.Dictate asChild>
              <TooltipIconButton
                tooltip="语音输入"
                side="bottom"
                type="button"
                variant="ghost"
                size="icon"
                className="aui-composer-dictate text-muted-foreground hover:text-foreground size-7 rounded-full"
                aria-label="开始语音输入"
              >
                <MicIcon className="aui-composer-dictate-icon size-4" />
              </TooltipIconButton>
            </ComposerPrimitive.Dictate>
          </AuiIf>
          <AuiIf condition={(s) => s.composer.dictation != null}>
            <ComposerPrimitive.StopDictation asChild>
              <TooltipIconButton
                tooltip="停止语音输入"
                side="bottom"
                type="button"
                variant="ghost"
                size="icon"
                className="aui-composer-stop-dictation text-destructive size-7 rounded-full"
                aria-label="停止语音输入"
              >
                <SquareIcon className="aui-composer-stop-dictation-icon size-3.5 animate-pulse fill-current" />
              </TooltipIconButton>
            </ComposerPrimitive.StopDictation>
          </AuiIf>
        </AuiIf>
        <AuiIf condition={(s) => !s.thread.isRunning}>
          <ComposerPrimitive.Send asChild>
            <TooltipIconButton
              tooltip="发送"
              side="bottom"
              type="button"
              variant="default"
              size="icon"
              className="aui-composer-send size-7 rounded-full"
              aria-label="发送消息"
            >
              <ArrowUpIcon className="aui-composer-send-icon size-4" />
            </TooltipIconButton>
          </ComposerPrimitive.Send>
        </AuiIf>
        <AuiIf condition={(s) => s.thread.isRunning}>
          <ComposerPrimitive.Cancel asChild>
            <Button
              type="button"
              variant="default"
              size="icon"
              className="aui-composer-cancel size-7 rounded-full"
              aria-label="停止生成"
            >
              <SquareIcon className="aui-composer-cancel-icon size-3.5 fill-current" />
            </Button>
          </ComposerPrimitive.Cancel>
        </AuiIf>
      </div>
    </div>
  );
};

const MessageError: FC = () => {
  return (
    <MessagePrimitive.Error>
      <ErrorPrimitive.Root className="aui-message-error-root border-destructive bg-destructive/10 text-destructive dark:bg-destructive/5 mt-2 rounded-md border p-3 text-sm dark:text-red-200">
        <ErrorPrimitive.Message className="aui-message-error-message line-clamp-2" />
      </ErrorPrimitive.Root>
    </MessagePrimitive.Error>
  );
};

/** 纯文本渲染（替代 MarkdownText，砍掉 Markdown/代码高亮） */
const PlainText: FC<{ text?: string }> = ({ text }) => (
  <span className="whitespace-pre-wrap">{text}</span>
);

/** 助手正在输出时的跳动指示点 */
const ThinkingDots: FC = () => (
  <span className="inline-flex items-center gap-1 py-2" aria-label="AI 正在思考">
    {[0, 1, 2].map((i) => (
      <span
        key={i}
        className="bg-muted-foreground size-1.5 animate-bounce rounded-full"
        style={{ animationDelay: `${i * 150}ms`, animationDuration: "900ms" }}
      />
    ))}
  </span>
);

/** 支持 `idb://` 引用的图片：从 IndexedDB 异步解析成 objectURL 再渲染 */
const IdbAwareImage: ImageMessagePartComponent = (part) => {
  const isIdb = isIdbRef(part.image);
  const [src, setSrc] = useState<string | undefined>(
    isIdb ? undefined : part.image,
  );
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!isIdbRef(part.image)) {
      setSrc(part.image);
      return;
    }
    let alive = true;
    resolveImageUrl(part.image)
      .then((u) => {
        if (alive) setSrc(u);
      })
      .catch(() => {
        if (alive) setFailed(true);
      });
    return () => {
      alive = false;
    };
  }, [part.image]);

  if (failed) {
    return (
      <div className="bg-muted/50 text-muted-foreground flex min-h-24 items-center justify-center rounded-lg p-4 text-xs">
        图片不存在（可能已被清理）
      </div>
    );
  }
  if (!src) {
    return (
      <div className="bg-muted/50 flex min-h-32 items-center justify-center rounded-lg p-4">
        <span className="border-primary border-t-muted-foreground size-6 animate-spin rounded-full border-2" />
      </div>
    );
  }
  return <Image {...part} image={src} />;
};

const UserImagePart: ImageMessagePartComponent = (part) => (
  <div data-slot="aui_user-message-image" className="py-1">
    <IdbAwareImage {...part} />
  </div>
);

const AssistantImagePart: ImageMessagePartComponent = (part) => (
  <div data-slot="aui_assistant-message-image" className="py-1">
    <IdbAwareImage {...part} />
  </div>
);

const DefaultAssistantMessage: FC = () => {
  // 正在运行且还没有任何文本内容 → 显示思考动画
  const isWaiting = useAuiState((s) => {
    if (s.message.status == null) return false;
    const parts = s.message.parts ?? [];
    const hasContent = parts.some((p) => p.type === "text" && p.text.length > 0);
    return s.message.status.type === "running" && !hasContent;
  });
  const flipped = useBubbleLayout() === "flipped";

  return (
    <MessagePrimitive.Root
      data-slot="aui_assistant-message-root"
      data-role="assistant"
      className={cn(
        "fade-in slide-in-from-bottom-1 animate-in relative duration-150 [contain-intrinsic-size:auto_200px] [content-visibility:auto]",
        flipped && "flex flex-col items-end",
      )}
    >
      <div
        data-slot="aui_assistant-message-content"
        className={cn(
          "text-foreground px-2 leading-relaxed wrap-break-word",
          flipped && "bg-muted rounded-xl px-4 py-2",
        )}
      >
        {isWaiting ? (
          <ThinkingDots />
        ) : (
          <MessagePrimitive.Parts
            components={{ Text: PlainText, Image: AssistantImagePart }}
          />
        )}
        <MessageError />
      </div>

      <AssistantActionBar />
    </MessagePrimitive.Root>
  );
};

const AssistantActionBar: FC = () => {
  return (
    <ActionBarPrimitive.Root
      hideWhenRunning
      autohide="not-last"
      className="aui-assistant-action-bar-root text-muted-foreground animate-in fade-in ms-1 flex gap-1 duration-200"
    >
      <ActionBarPrimitive.Copy asChild>
        <TooltipIconButton tooltip="复制">
          <AuiIf condition={(s) => s.message.isCopied}>
            <CheckIcon className="animate-in zoom-in-50 fade-in duration-200 ease-out" />
          </AuiIf>
          <AuiIf condition={(s) => !s.message.isCopied}>
            <CopyIcon className="animate-in zoom-in-75 fade-in duration-150" />
          </AuiIf>
        </TooltipIconButton>
      </ActionBarPrimitive.Copy>
    </ActionBarPrimitive.Root>
  );
};

const UserMessage: FC = () => {
  const flipped = useBubbleLayout() === "flipped";
  return (
    <MessagePrimitive.Root
      data-slot="aui_user-message-root"
      className={cn(
        "fade-in slide-in-from-bottom-1 animate-in grid auto-rows-auto content-start gap-y-2 px-2 duration-150 [contain-intrinsic-size:auto_200px] [content-visibility:auto]",
        flipped
          ? // 管理端：访客消息靠左
            "grid-cols-[auto_minmax(72px,1fr)] [&:where(>*)]:col-start-1"
          : // 用户端：自己消息靠右
            "grid-cols-[minmax(72px,1fr)_auto] [&:where(>*)]:col-start-2",
      )}
      data-role="user"
    >
      <UserMessageAttachments />

      <div
        className={cn(
          "aui-user-message-content-wrapper relative min-w-0",
          flipped ? "col-start-1" : "col-start-2",
        )}
      >
        <div className="aui-user-message-content peer bg-muted text-foreground rounded-xl px-4 py-2 wrap-break-word empty:hidden">
          <MessagePrimitive.Parts components={{ Image: UserImagePart }} />
        </div>
      </div>
    </MessagePrimitive.Root>
  );
};
