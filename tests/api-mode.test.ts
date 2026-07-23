/**
 * @fileoverview 验证 API 模式解析在未知或缺失环境值时失败关闭到远程模式。
 *
 * 测试直接调用纯解析函数，不启动 Vite、Mock 拦截器或远程 API；它保护部署拼写错误不会静默
 * 启用前端替身，但不证明具体构建产物的环境注入正确。
 */
import { describe, expect, it } from "vitest";
import { resolveApiMode } from "../renderer/src/api/mode.js";

describe("API mode", () => {
  it("uses the remote API unless mock mode is explicit", () => {
    expect(resolveApiMode(undefined)).toBe("remote");
    expect(resolveApiMode("remote")).toBe("remote");
    expect(resolveApiMode("mock")).toBe("mock");
    expect(resolveApiMode("unexpected")).toBe("remote");
  });
});
