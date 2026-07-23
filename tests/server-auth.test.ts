import { describe, expect, it } from "vitest";
import { shouldRefreshAccessToken } from "../renderer/src/server/server.js";

describe("API session refresh boundary", () => {
  it("does not turn an invalid login into a refresh request", () => {
    expect(shouldRefreshAccessToken(401, "/auth/login", undefined)).toBe(false);
  });

  it("allows startup session recovery through the refresh cookie", () => {
    expect(shouldRefreshAccessToken(401, "/auth/me", undefined)).toBe(true);
  });

  it("does not retry a request more than once", () => {
    expect(shouldRefreshAccessToken(401, "/jobs", true)).toBe(false);
    expect(shouldRefreshAccessToken(500, "/jobs", undefined)).toBe(false);
  });
});
