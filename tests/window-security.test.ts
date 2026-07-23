/**
 * @fileoverview 验证 Electron Renderer 导航白名单的 URL 判定风险。
 *
 * 测试只调用纯函数并构造开发/生产样式 URL，保护跨源与相邻文件导航被拒绝；未启动 Electron，
 * 因此不证明实际 `will-navigate`、重定向、新窗口、WebView 或权限事件已正确接线。
 */
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
