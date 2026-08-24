/**
 * 聊天图片工具：IndexedDB 存储 + 前端压缩
 *
 * 存储策略：图片本体只存双方各自的浏览器 IndexedDB（key 全局唯一，双端同 key），
 * 消息里只携带 `idb://<key>` 引用；传输时通过 socket 附带 dataURI 本体，
 * 接收方落自己的 IndexedDB。服务器仅内存中转，不落盘。
 */

const DB_NAME = "chattt-images";
const STORE = "images";

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE)) {
        req.result.createObjectStore(STORE);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

/** 生成全局唯一图片 key（发送方生成，接收方沿用） */
export function makeImageKey(): string {
  return `img-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export async function putImage(key: string, blob: Blob): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put(blob, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

export async function getImage(key: string): Promise<Blob | undefined> {
  const db = await openDb();
  const blob = await new Promise<Blob | undefined>((resolve, reject) => {
    const tx = db.transaction(STORE, "readonly");
    const req = tx.objectStore(STORE).get(key);
    req.onsuccess = () => resolve(req.result as Blob | undefined);
    req.onerror = () => reject(req.error);
  });
  db.close();
  return blob;
}

/** 删除单条媒体记录（key 不存在时静默成功） */
export async function deleteImage(key: string): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

/** 批量删除媒体记录：逐条删除，任何一条失败不影响其余 */
export async function deleteImages(keys: string[]): Promise<void> {
  await Promise.all(
    keys.map((k) => deleteImage(k).catch(() => undefined)),
  );
}

/** 是否为本端 IndexedDB 引用 */
export const isIdbRef = (v: string) => v.startsWith("idb://");

export const idbKeyOf = (ref: string) => ref.slice("idb://".length);

// objectURL 会话级缓存：同一张图多处引用只创建一次
const objUrlCache = new Map<string, string>();
// objectURL → idb:// 引用的反查表（localStorage 持久化时还原用）
const urlToRef = new Map<string, string>();

/** 把任意图片引用解析成 <img src> 可用的 URL；找不到时抛错 */
export async function resolveImageUrl(ref: string): Promise<string> {
  if (!isIdbRef(ref)) return ref;
  const key = idbKeyOf(ref);
  const cached = objUrlCache.get(key);
  if (cached) return cached;
  const blob = await getImage(key);
  if (!blob) throw new Error(`IndexedDB 中没有图片 ${key}`);
  const url = URL.createObjectURL(blob);
  objUrlCache.set(key, url);
  urlToRef.set(url, ref);
  return url;
}

/**
 * 把文本中的 idb:// 引用批量展开为可直接渲染的 blob URL。
 * 用于从 localStorage 加载消息后、交给 runtime 渲染之前。
 */
export async function expandIdbRefs(text: string): Promise<string> {
  const matches = [...text.matchAll(/idb:\/\/[a-z0-9-]+/g)].map((m) => m[0]);
  if (!matches.length) return text;
  await Promise.all(
    [...new Set(matches)].map((ref) =>
      resolveImageUrl(ref).catch(() => undefined),
    ),
  );
  // 注意方向：把文本里的 idb:// 引用替换成刚生成的 blob URL
  let out = text;
  for (const [url, ref] of urlToRef) {
    if (out.includes(ref)) out = out.split(ref).join(url);
  }
  return out;
}

/** 把文本中的 objectURL 还原为 idb:// 引用（写入 localStorage 前，避免存储膨胀与失效链接） */
export function shrinkObjectUrls(text: string): string {
  let out = text;
  for (const [url, ref] of urlToRef) {
    out = out.split(url).join(ref);
  }
  return out;
}

/** 同步版：把文本中已缓存解析过的 idb:// 引用替换为 blob URL */
export function expandIdbRefsSync(text: string): string {
  let out = text;
  for (const [url, ref] of urlToRef) {
    if (out.includes(ref)) out = out.split(ref).join(url);
  }
  return out;
}

export function blobToDataUri(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result as string);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });
}

export function dataUriToBlob(dataUri: string): Blob {
  const commaIndex = dataUri.indexOf(",");
  const meta = dataUri.slice(0, commaIndex);
  const data = dataUri.slice(commaIndex + 1);
  const mime =
    meta.match(/data:([^;]+)/i)?.[1]?.toLowerCase() ?? "application/octet-stream";
  const bytes = atob(data);
  const arr = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
  return new Blob([arr], { type: mime });
}

/**
 * 前端压缩：最长边限 1600px，WebP 质量 0.85 起逐级降到 0.35，
 * 目标不超过 maxBytes（默认 ~280KB）；压不到就返回最后一次结果。
 */
export async function compressImage(
  file: Blob,
  maxBytes = 280 * 1024,
  maxEdge = 1600,
): Promise<Blob> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    return file; // 无法解码时原样返回
  }

  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
  const w = Math.max(1, Math.round(bitmap.width * scale));
  const h = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    bitmap.close();
    return file;
  }
  ctx.drawImage(bitmap, 0, 0, w, h);
  bitmap.close();

  let best: Blob | null = null;
  for (let q = 0.85; q >= 0.35; q -= 0.125) {
    const blob = await new Promise<Blob | null>((r) =>
      canvas.toBlob(r, "image/webp", q),
    );
    if (!blob) continue;
    best = blob;
    if (blob.size <= maxBytes) return blob;
  }
  return best ?? file;
}
