import { promises as fs } from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

/**
 * 照片存储 (MVP: 本地文件系统)
 * 后期替换为 MinIO / S3 兼容存储
 */

const UPLOAD_DIR = path.join(process.cwd(), "public", "uploads");
const PUBLIC_URL_PREFIX = "/uploads";

export interface SavePhotoResult {
  filename: string;
  url: string;
  size: number;
}

/**
 * 保存 base64 图片到本地
 * @param base64Data data:image/jpeg;base64,/9j/4AAQ... 或纯 base64
 * @param mimeType image/jpeg | image/png | image/webp
 */
export async function savePhotoFromBase64(
  base64Data: string,
  mimeType?: string
): Promise<SavePhotoResult> {
  let effectiveMime = mimeType ?? "image/jpeg";
  // 解析 data URL
  let rawBase64 = base64Data;
  if (base64Data.startsWith("data:")) {
    const match = base64Data.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) {
      throw new Error("无效的 data URL");
    }
    effectiveMime = match[1];
    rawBase64 = match[2];
  }

  // 解码
  const buffer = Buffer.from(rawBase64, "base64");

  // 限制大小 (5MB)
  if (buffer.length > 5 * 1024 * 1024) {
    throw new Error("图片大小超过 5MB");
  }

  // 允许的 mime types
  const allowed = ["image/jpeg", "image/png", "image/webp"];
  if (!allowed.includes(effectiveMime)) {
    throw new Error(`不支持的图片格式: ${effectiveMime}`);
  }

  // 文件名: 时间戳 + 随机
  const ext = effectiveMime.split("/")[1] ?? "jpg";
  const hash = crypto.randomBytes(8).toString("hex");
  const filename = `${Date.now()}-${hash}.${ext}`;

  // 确保目录存在
  await fs.mkdir(UPLOAD_DIR, { recursive: true });

  // 写文件
  const filepath = path.join(UPLOAD_DIR, filename);
  await fs.writeFile(filepath, buffer);

  return {
    filename,
    url: `${PUBLIC_URL_PREFIX}/${filename}`,
    size: buffer.length,
  };
}

/**
 * 删除照片
 */
export async function deletePhoto(url: string): Promise<void> {
  if (!url.startsWith(PUBLIC_URL_PREFIX)) return;
  const filename = url.replace(`${PUBLIC_URL_PREFIX}/`, "");
  const filepath = path.join(UPLOAD_DIR, filename);
  try {
    await fs.unlink(filepath);
  } catch (error) {
    // 文件可能不存在, 忽略
    console.warn(`[storage] 删除照片失败: ${filename}`, error);
  }
}