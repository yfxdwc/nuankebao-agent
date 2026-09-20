// ============================================
// 会话有效期 (唯一真相) —— ADR-0013
// ============================================
// 主人 2026-09-20: 「同一个设备需要能够长期记住登录状态，不限时长」
//
// 为什么放单独文件: Auth.js 配置 (Edge 安全) 与 dev 登录端点 (Node) 都要用同一个数,
// 分开写迟早漂移 (以前就是两边各写 30 天, 改一处忘一处)。

/**
 * 会话上限 = 10 年 (实际上的"永久")
 *   - Auth.js: cookie maxAge + JWT exp
 *   - dev 登录端点 (flutter-login): body 返回的 token 同寿命
 */
export const SESSION_MAX_AGE_SECONDS = 10 * 365 * 24 * 60 * 60;

/**
 * 滚动续期间隔 = 7 天
 *   只要用户 7 天内用过一次, JWT 重新签发 → 到期时间往后推
 *   → 常用设备实际上永不掉线; 一年没开的设备才会真过期
 */
export const SESSION_UPDATE_AGE_SECONDS = 7 * 24 * 60 * 60;

/** 运维手闸: 想缩短/延长整体会话上限, 设 SESSION_MAX_AGE_DAYS 即可 (1-3650) */
export function resolveSessionMaxAgeSeconds(env: NodeJS.ProcessEnv = process.env): number {
  const raw = Number.parseInt(env.SESSION_MAX_AGE_DAYS ?? "", 10);
  if (Number.isFinite(raw) && raw >= 1 && raw <= 3650) {
    return raw * 24 * 60 * 60;
  }
  return SESSION_MAX_AGE_SECONDS;
}
