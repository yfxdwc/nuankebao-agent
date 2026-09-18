import { promises as fs } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";

/**
 * 暖客宝 APK 元数据共享模块 (下载页 + /api/apk-download + /api/apk-qr 共用)
 *
 * 核心规则:
 *   - resolveApkPath: 显式 NUANKEBAO_APK_PATH 优先, 否则在候选里挑 mtime 最新的,
 *     —— 防止 /tmp 里的旧拷贝盖过 flutter_app/build 里的新 build。
 *   - getApkMeta: 大小 / 本地构建时间 / md5, 按 (path, mtimeMs) 缓存, 文件一变自动失效。
 */

export interface ApkMeta {
  path: string;
  sizeBytes: number;
  /** 服务器本地时区 YYYY-MM-DD HH:mm:ss */
  mtimeLocal: string;
  md5: string;
}

/** 与 apk-download 历史语义一致的候选列表 (flutter build 输出在最前面, 因为是"最新 build"真源) */
export function apkCandidates(): string[] {
  const cwd = process.cwd();
  return [
    process.env.NUANKEBAO_APK_PATH, // 0. 生产/部署时显式指定, 恒最高优先
    // Flutter 最新 build 输出 (owner 本地 rebuild 后不拷 /tmp 也能生效)
    path.join(cwd, "flutter_app", "build", "app", "outputs", "flutter-apk", "app-release.apk"),
    path.join(cwd, "flutter_app", "build", "app", "outputs", "apk", "release", "app-release.apk"),
    "/tmp/NUANKEBAO-release.apk",
    path.join(cwd, "..", "tmp", "NUANKEBAO-release.apk"),
    path.join(cwd, "..", "public", "downloads", "NUANKEBAO-release.apk"),
    path.join(cwd, "public", "downloads", "NUANKEBAO-release.apk"),
  ].filter((p): p is string => Boolean(p));
}

/** 解析当前应该提供下载的 APK 路径: env 显式 > 所有存在候选里 mtime 最新 */
export async function resolveApkPath(): Promise<string | null> {
  const found: { p: string; mtimeMs: number }[] = [];
  for (const p of apkCandidates()) {
    try {
      const st = await fs.stat(p);
      if (st.isFile()) found.push({ p, mtimeMs: st.mtimeMs });
    } catch {
      // 不存在 / 不可读 → 跳过
    }
  }
  if (found.length === 0) return null;

  const explicit = process.env.NUANKEBAO_APK_PATH;
  if (explicit && found.some((f) => f.p === explicit)) return explicit;

  found.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return found[0].p;
}

// md5 缓存: key = path, 失效条件 = mtimeMs 变化
const metaCache = new Map<string, { mtimeMs: number; meta: ApkMeta }>();

/** 拿 APK 完整元数据 (不存在返回 null) */
export async function getApkMeta(): Promise<ApkMeta | null> {
  const p = await resolveApkPath();
  if (!p) return null;
  try {
    const st = await fs.stat(p);
    const cached = metaCache.get(p);
    if (cached && cached.mtimeMs === st.mtimeMs) return cached.meta;

    const pad = (n: number) => String(n).padStart(2, "0");
    const d = st.mtime;
    const meta: ApkMeta = {
      path: p,
      sizeBytes: st.size,
      mtimeLocal: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`,
      md5: await md5File(p),
    };
    metaCache.set(p, { mtimeMs: st.mtimeMs, meta });
    return meta;
  } catch {
    return null;
  }
}

async function md5File(p: string): Promise<string> {
  const hash = createHash("md5");
  const buf = Buffer.alloc(1024 * 1024);
  const fh = await fs.open(p, "r");
  try {
    for (;;) {
      const { bytesRead } = await fh.read(buf, 0, buf.length, null);
      if (bytesRead === 0) break;
      hash.update(buf.subarray(0, bytesRead));
    }
  } finally {
    await fh.close();
  }
  return hash.digest("hex");
}

/**
 * Flutter 版本号真源 = flutter_app/pubspec.yaml 的 version: (如 0.1.0+1)。
 * APK 内 versionName 由它生成, 下载页显示也读它, 避免两处手抄漂移。
 */
export async function getAppVersion(): Promise<string> {
  try {
    const raw = await fs.readFile(
      path.join(process.cwd(), "flutter_app", "pubspec.yaml"),
      "utf8"
    );
    const m = raw.match(/^version:\s*(\S+)/m);
    if (m?.[1]) return m[1];
  } catch {
    // flutter 源码不在场 (如纯部署机) → 兜底
  }
  return "0.1.0";
}

/**
 * 拆 pubspec version spec ("0.2.2+3") → { version: "0.2.2", buildNumber: 3 }
 *
 * 边界 (老 APK / 手改坏): 缺 +build 时 buildNumber = 0; 非 semver 片段原样透传
 * (前端只做「字符串不等 = 可能更新」提示, 不做严格 semver 排序)。
 *
 * 用在: GET /api/app-version (Flutter 「检查更新」比对 package_info 里的版本)
 */
export function parseAppVersionSpec(spec: string): {
  version: string;
  buildNumber: number;
} {
  const [versionPart, buildPart] = (spec ?? "").split("+");
  const version = (versionPart ?? "").trim() || "0.0.0";
  const buildNumber = Number.parseInt((buildPart ?? "").trim(), 10);
  return {
    version,
    buildNumber: Number.isFinite(buildNumber) && buildNumber > 0 ? buildNumber : 0,
  };
}
