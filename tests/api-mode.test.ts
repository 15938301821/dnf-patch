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
