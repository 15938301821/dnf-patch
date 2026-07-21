import { describe, expect, it } from "vitest";
import { isAllowedRendererNavigation } from "../electron/utils/window-security.js";

describe("desktop renderer navigation", () => {
  it("allows hash routes on the configured renderer entry", () => {
    expect(
      isAllowedRendererNavigation(
        "http://127.0.0.1:5173/#/professions",
        "http://127.0.0.1:5173/",
      ),
    ).toBe(true);
  });

  it("rejects external origins and sibling files", () => {
    expect(
      isAllowedRendererNavigation(
        "https://example.invalid/",
        "http://127.0.0.1:5173/",
      ),
    ).toBe(false);
    expect(
      isAllowedRendererNavigation(
        "file:///C:/temp/other.html",
        "file:///C:/app/renderer/index.html",
      ),
    ).toBe(false);
  });
});
