import type { AttachmentAdapter } from "@assistant-ui/react";
import {
  compressImage,
  makeImageKey,
  putImage,
} from "@/lib/image-store";

/**
 * 图片附件适配器：发送前前端压缩到几百 KB，
 * 图片本体存本端浏览器 IndexedDB，消息里只携带 `idb://<key>` 引用。
 * 数据本体在 socket 发送时由各端自行取出附带，服务器不落盘。
 */
export class UploadImageAttachmentAdapter implements AttachmentAdapter {
  accept = "image/*";

  async add(state: { file: File }) {
    return {
      id: `img-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
      type: "image" as const,
      name: state.file.name,
      contentType: state.file.type,
      file: state.file,
      status: {
        type: "requires-action" as const,
        reason: "composer-send" as const,
      },
    };
  }

  async send(attachment: { file: File; name: string }) {
    // 前端压缩（WebP，目标 ~280KB 以内）
    const compressed = await compressImage(attachment.file);

    // 存本端 IndexedDB，消息里只带引用
    const key = makeImageKey();
    await putImage(key, compressed);
    const ref = `idb://${key}`;

    return {
      id: attachment.name + Date.now(),
      type: "image" as const,
      name: attachment.name,
      content: [{ type: "image" as const, image: ref }],
      status: { type: "complete" as const },
    };
  }

  async remove() {}
}
