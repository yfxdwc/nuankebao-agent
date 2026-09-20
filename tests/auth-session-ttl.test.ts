// 会话有效期测试 (ADR-0013: 同设备长期记住登录, 主人 2026-09-20)
//
// 这条以前踩过坑: Auth.js 侧与 dev 登录端点**各写 30 天** → 改一处忘一处, 用户到期被踢。
// 现在两边共用 src/lib/auth/session.ts, 这组测试锁住"唯一真相 + 运维手闸"。
import { describe, it, expect } from "vitest";
import {
  SESSION_MAX_AGE_SECONDS,
  SESSION_UPDATE_AGE_SECONDS,
  resolveSessionMaxAgeSeconds,
} from "@/lib/auth/session";
import { authConfig } from "@/lib/auth/config";

describe("会话有效期 (ADR-0013)", () => {
  it("默认 10 年 (≈ 永久), 不是 30 天", () => {
    expect(SESSION_MAX_AGE_SECONDS).toBe(10 * 365 * 24 * 60 * 60);
    expect(SESSION_MAX_AGE_SECONDS / 86400).toBe(3650); // 正好 10 年 (含 2 个闰年日在内仍是 3650 天口径)
  });

  it("滚动续期 7 天 (常用设备永不掉线)", () => {
    expect(SESSION_UPDATE_AGE_SECONDS).toBe(7 * 24 * 60 * 60);
  });

  it("Auth.js 配置真的用上了这两个值 (不是写了常量没接线)", () => {
    expect(authConfig.session?.strategy).toBe("jwt");
    expect(authConfig.session?.maxAge).toBe(SESSION_MAX_AGE_SECONDS);
    expect(authConfig.session?.updateAge).toBe(SESSION_UPDATE_AGE_SECONDS);
  });

  it("运维手闸 SESSION_MAX_AGE_DAYS: 在 1-3650 天内生效", () => {
    expect(resolveSessionMaxAgeSeconds({ SESSION_MAX_AGE_DAYS: "7" } as NodeJS.ProcessEnv)).toBe(
      7 * 24 * 60 * 60
    );
    expect(resolveSessionMaxAgeSeconds({ SESSION_MAX_AGE_DAYS: "3650" } as NodeJS.ProcessEnv)).toBe(
      3650 * 24 * 60 * 60
    );
  });

  it("手闸非法值一律回退默认 (0 / 负数 / 超范围 / 乱填 / 空)", () => {
    for (const bad of ["0", "-1", "9999", "abc", "", " "]) {
      expect(
        resolveSessionMaxAgeSeconds({ SESSION_MAX_AGE_DAYS: bad } as NodeJS.ProcessEnv)
      ).toBe(SESSION_MAX_AGE_SECONDS);
    }
    expect(resolveSessionMaxAgeSeconds({} as NodeJS.ProcessEnv)).toBe(SESSION_MAX_AGE_SECONDS);
  });
});
