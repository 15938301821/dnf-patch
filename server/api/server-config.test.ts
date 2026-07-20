import { describe, expect, it } from "vitest";
import {
  resolveServerConfiguration,
  resolveServerEndpoint,
} from "./server-config.js";

describe("server endpoint configuration", () => {
  it("allows the default loopback API", () => {
    expect(resolveServerEndpoint("http://127.0.0.1:56789/v1/")).toEqual({
      baseUrl: "http://127.0.0.1:56789/v1",
      socketUrl: "http://127.0.0.1:56789/runs",
      identity: "127.0.0.1:56789/v1",
    });
  });

  it.each([
    "http://example.com/v1",
    "https://user:secret@example.com/v1",
    "https://example.com/api",
    "https://example.com/v1?token=secret",
  ])("rejects unsafe server endpoint %s", (value) => {
    expect(() => resolveServerEndpoint(value)).toThrow();
  });

  it("rejects a short client token", () => {
    expect(() =>
      resolveServerConfiguration({ DNF_PATCH_SERVER_CLIENT_TOKEN: "short" }),
    ).toThrow(/32/u);
  });
});
