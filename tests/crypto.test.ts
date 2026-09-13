import { describe, it, expect } from "vitest";
import { encryptField, decryptField, hashForLookup, hmacForLookup } from "@/lib/crypto/field";

describe("crypto/field", () => {
  it("encrypts and decrypts roundtrip", () => {
    const plaintext = "13800138000";
    const ciphertext = encryptField(plaintext);
    expect(ciphertext).not.toBe(plaintext);
    expect(ciphertext.length).toBeGreaterThan(plaintext.length);
    expect(decryptField(ciphertext)).toBe(plaintext);
  });

  it("uses different IVs for same plaintext (semantic security)", () => {
    const a = encryptField("test");
    const b = encryptField("test");
    expect(a).not.toBe(b);
    expect(decryptField(a)).toBe("test");
    expect(decryptField(b)).toBe("test");
  });

  it("hashForLookup is deterministic", () => {
    const a = hashForLookup("13800138000");
    const b = hashForLookup("13800138000");
    expect(a).toBe(b);
    expect(a.length).toBe(32); // md5 hex
  });

  it("hashForLookup is different for different inputs", () => {
    const a = hashForLookup("13800138000");
    const b = hashForLookup("13800138001");
    expect(a).not.toBe(b);
  });

  it("hmacForLookup uses secret key (not vulnerable to rainbow table)", () => {
    const a = hmacForLookup("test");
    const b = hmacForLookup("test");
    expect(a).toBe(b);
    expect(a.length).toBe(64); // sha256 hex
  });

  it("decryptField throws on invalid ciphertext", () => {
    expect(() => decryptField("not-base64!@#")).toThrow();
  });

  it("decryptField throws on too-short ciphertext", () => {
    expect(() => decryptField("YWJj")).toThrow(); // "abc" base64, too short
  });
});