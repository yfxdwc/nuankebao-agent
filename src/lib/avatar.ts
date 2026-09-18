// ============================================
// 头像取值白名单 (「我的」页自定义头像)
// ============================================
// 数据库存的是**一个字符串** (user.avatar_url), 只有三种合法形态:
//   null                 → 默认 (前端画姓名首字)
//   'preset:<id>'        → 内置候选头像 (前端本地画, 不占服务器存储, 不用网络)
//   '/uploads/<file>'    → 自己上传的照片 (POST /api/photos 的产物)
//
// 为什么不用外链 (http://...):
//   1. 客户端要拿它当图片 URL 去加载 → 外链 = 帮别人跑统计 / 泄露用户 ID
//   2. 外链会烂 (对方删图 / 换域名) → 头像变白框, 用户以为 App 坏了
//   3. 本项目数据自托管 (CHARTER §3.2), 头像也不该挂第三方
//
// 为什么白名单放服务端:
//   客户端可以被改 (APK 反编译), 落库的值必须服务端说了算 —— 顺带把脏数据挡在库外
//
// 用在: GET /api/me (读) + PATCH /api/me (写) + tests/profile-avatar.test.ts

/** 候选头像 id (顺序 = 前端展示顺序; 改动要前后端同步: 见 flutter_app/lib/core/widgets/user_avatar.dart) */
export const AVATAR_PRESETS = [
  "leaf",
  "blossom",
  "tea",
  "zen",
  "heart",
  "sun",
  "sprout",
  "water",
] as const;

export type AvatarPreset = (typeof AVATAR_PRESETS)[number];

/** 上传头像的 URL 前缀 (public/uploads, 见 src/lib/storage/photos.ts) */
export const UPLOAD_URL_PREFIX = "/uploads/";

/** 存库前裁剪长度上限 (text 列, 防超长垃圾) */
export const MAX_AVATAR_VALUE_LENGTH = 300;

export type AvatarValue = string | null;

export type AvatarParseResult =
  | { ok: true; value: AvatarValue }
  | { ok: false; reason: string };

/**
 * 校验 + 归一化客户端传来的头像值
 *
 * 容忍: undefined (当 null 处理 —— 前端"恢复默认"最省事的写法)
 * 拒绝: 外链 / 奇怪协议 / 目录穿越 / 未知 preset / 超长
 */
export function parseAvatarValue(raw: unknown): AvatarParseResult {
  if (raw === null || raw === undefined) return { ok: true, value: null };
  if (typeof raw !== "string") return { ok: false, reason: "头像值必须是字符串或 null" };

  const value = raw.trim();
  if (value.length === 0) return { ok: true, value: null }; // 空串 = 恢复默认
  if (value.length > MAX_AVATAR_VALUE_LENGTH) {
    return { ok: false, reason: `头像值太长 (最多 ${MAX_AVATAR_VALUE_LENGTH} 字符)` };
  }

  if (value.startsWith("preset:")) {
    const id = value.slice("preset:".length);
    if (!(AVATAR_PRESETS as readonly string[]).includes(id)) {
      return { ok: false, reason: `未知候选头像: ${id}` };
    }
    return { ok: true, value: `preset:${id}` };
  }

  if (value.startsWith(UPLOAD_URL_PREFIX)) {
    const filename = value.slice(UPLOAD_URL_PREFIX.length);
    if (filename !== value.split("/").pop()) {
      // '/uploads/a/b.jpg' 这种带子路径的一律拒 (不给自己挖目录穿越的坑)
      return { ok: false, reason: "头像路径不合法" };
    }
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*\.(jpg|jpeg|png|webp)$/i.test(filename)) {
      return { ok: false, reason: "头像文件必须是 jpg/png/webp" };
    }
    if (filename.includes("..")) return { ok: false, reason: "头像路径不合法" };
    return { ok: true, value: `${UPLOAD_URL_PREFIX}${filename}` };
  }

  return { ok: false, reason: "只支持内置候选头像或本站上传的图片" };
}

/** 只读场景用: 库里万一有脏数据, 读出来也要能安全兜底 (当成 null) */
export function readAvatarValue(stored: string | null | undefined): AvatarValue {
  const parsed = parseAvatarValue(stored ?? null);
  return parsed.ok ? parsed.value : null;
}

/** 是不是内置候选 (前端用来决定"本地画"还是"下载图片") */
export function isPresetAvatar(value: string | null | undefined): boolean {
  return typeof value === "string" && value.startsWith("preset:");
}

/** 取 preset id (非 preset 返回 null) */
export function presetIdOf(value: string | null | undefined): AvatarPreset | null {
  if (!isPresetAvatar(value)) return null;
  const id = (value as string).slice("preset:".length);
  return (AVATAR_PRESETS as readonly string[]).includes(id) ? (id as AvatarPreset) : null;
}
