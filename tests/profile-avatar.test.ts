// 头像取值白名单单测 (PATCH /api/me 的守门人)
// 这类校验的失败模式是"放过了不该放的" —— 所以负例比正例更重要
import { describe, it, expect } from "vitest";
import {
  AVATAR_PRESETS,
  parseAvatarValue,
  readAvatarValue,
  isPresetAvatar,
  presetIdOf,
  MAX_AVATAR_VALUE_LENGTH,
} from "@/lib/avatar";

describe("parseAvatarValue — 合法值", () => {
  it("null / undefined / 空串 = 恢复默认, 都归一化成 null", () => {
    expect(parseAvatarValue(null)).toEqual({ ok: true, value: null });
    expect(parseAvatarValue(undefined)).toEqual({ ok: true, value: null });
    expect(parseAvatarValue("")).toEqual({ ok: true, value: null });
    expect(parseAvatarValue("   ")).toEqual({ ok: true, value: null });
  });

  it("每个内置候选 id 都收, 并且去掉首尾空格", () => {
    for (const id of AVATAR_PRESETS) {
      expect(parseAvatarValue(`preset:${id}`)).toEqual({
        ok: true,
        value: `preset:${id}`,
      });
    }
    expect(parseAvatarValue("  preset:leaf  ")).toEqual({
      ok: true,
      value: "preset:leaf",
    });
  });

  it("本站上传的文件名 (POST /api/photos 的产物) 都收", () => {
    for (const name of ["a.jpg", "abc_123-PNG.PNG", "x.webp", "y.jpeg"]) {
      expect(parseAvatarValue(`/uploads/${name}`)).toEqual({
        ok: true,
        value: `/uploads/${name}`,
      });
    }
  });
});

describe("parseAvatarValue — 必须拒绝", () => {
  it("外链 (http/https) 一律拒 —— 防泄露 / 防跑第三方统计 / 防烂链", () => {
    for (const bad of [
      "https://evil.example.com/a.png",
      "http://127.0.0.1:3003/uploads/a.jpg",
      "//evil.example.com/a.png",
    ]) {
      expect(parseAvatarValue(bad).ok).toBe(false);
    }
  });

  it("未知 preset / 空 preset id 拒", () => {
    expect(parseAvatarValue("preset:hacker").ok).toBe(false);
    expect(parseAvatarValue("preset:").ok).toBe(false);
    expect(parseAvatarValue("preset:LEAF").ok).toBe(false); // 大小写敏感, 不做模糊匹配
  });

  it("目录穿越 / 子路径 / 非图片扩展 拒", () => {
    for (const bad of [
      "/uploads/../../etc/passwd.jpg",
      "/uploads/sub/dir/a.jpg",
      "/uploads/a.sh",
      "/uploads/a.jpg.exe",
      "/uploads/中文.jpg",
      "/uploads/.jpg",
    ]) {
      expect(parseAvatarValue(bad).ok).toBe(false);
    }
  });

  it("非字符串 (数字/对象/布尔) 拒 —— 防止把 JSON 塞进 text 列", () => {
    for (const bad of [1, true, {}, [], { url: "/uploads/a.jpg" }]) {
      expect(parseAvatarValue(bad).ok).toBe(false);
    }
  });

  it("超长值拒", () => {
    expect(parseAvatarValue("preset:" + "a".repeat(MAX_AVATAR_VALUE_LENGTH)).ok).toBe(
      false
    );
    expect(parseAvatarValue("/uploads/" + "a".repeat(400) + ".jpg").ok).toBe(false);
  });

  it("随便一个不存在的前缀拒 (data: / javascript: / file:)", () => {
    for (const bad of [
      "data:image/png;base64,AAAA",
      "javascript:alert(1)",
      "file:///etc/passwd",
      "uploads/a.jpg",
    ]) {
      expect(parseAvatarValue(bad).ok).toBe(false);
    }
  });
});

describe("读侧兜底 (库里已有脏数据也不能把页面搞崩)", () => {
  it("readAvatarValue: 脏值当 null 读, 合法值原样读", () => {
    expect(readAvatarValue("https://evil/a.png")).toBe(null);
    expect(readAvatarValue("garbage")).toBe(null);
    expect(readAvatarValue(null)).toBe(null);
    expect(readAvatarValue(undefined)).toBe(null);
    expect(readAvatarValue("preset:tea")).toBe("preset:tea");
    expect(readAvatarValue("/uploads/x.jpg")).toBe("/uploads/x.jpg");
  });
});

describe("辅助判断", () => {
  it("isPresetAvatar / presetIdOf", () => {
    expect(isPresetAvatar("preset:leaf")).toBe(true);
    expect(isPresetAvatar("/uploads/a.jpg")).toBe(false);
    expect(isPresetAvatar(null)).toBe(false);

    expect(presetIdOf("preset:water")).toBe("water");
    expect(presetIdOf("preset:hacker")).toBe(null);
    expect(presetIdOf("/uploads/a.jpg")).toBe(null);
  });

  it("候选 id 数量与唯一性 (前端按顺序展示, 重复会出两个一样的头像)", () => {
    expect(AVATAR_PRESETS.length).toBeGreaterThanOrEqual(6);
    expect(new Set(AVATAR_PRESETS).size).toBe(AVATAR_PRESETS.length);
  });
});
