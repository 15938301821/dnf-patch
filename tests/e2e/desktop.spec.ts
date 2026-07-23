/**
 * @fileoverview 在真实 Electron 进程中验证桌面壳隔离、窗口拒绝和共用 Renderer 登录流程。
 *
 * Playwright 启动已构建主进程并在每例后关闭，Renderer 使用 E2E Mock API；测试能观察 Node、
 * require、业务桥接和新窗口不可用，但不证明真实 Server、系统权限对话框、恶意页面攻防或
 * 不同操作系统打包产物。应用引用必须逐例清理，避免残留 Electron 进程污染后续用例。
 */
import { resolve } from "node:path";
import {
  _electron as electron,
  expect,
  test,
  type ElectronApplication,
} from "@playwright/test";

const repositoryRoot = resolve(import.meta.dirname, "../..");
let application: ElectronApplication | undefined;

test.afterEach(async () => {
  // 即使断言失败也关闭本例启动的真实 Electron 进程，避免跨用例共享高权限主进程。
  const launchedApplication = application;
  application = undefined;
  await launchedApplication?.close().catch(() => undefined);
});

test("loads the frontend in an isolated desktop shell", async () => {
  // 使用已构建入口验证实际 webPreferences 和 Preload 结果，不以纯函数 Mock 替代桌面壳。
  application = await electron.launch({
    args: [resolve(repositoryRoot, "out/main/index.js")],
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ELECTRON_DISABLE_SECURITY_WARNINGS: "true",
    },
  });

  const window = await application.firstWindow();
  await expect(window).toHaveTitle("DNF Patch Studio");
  await expect(window.getByRole("heading", { name: "登录" })).toBeVisible();

  expect(
    await window.evaluate(() => {
      const scope = globalThis as unknown as Record<string, unknown>;
      return {
        nodeProcessAvailable: typeof scope.process !== "undefined",
        requireAvailable: typeof scope.require !== "undefined",
        businessBridgeAvailable: typeof scope.dnfPatch !== "undefined",
      };
    }),
  ).toEqual({
    nodeProcessAvailable: false,
    requireAvailable: false,
    businessBridgeAvailable: false,
  });

  expect(
    await window.evaluate(() => {
      const browser = globalThis as unknown as {
        open(url: string, target: string): unknown;
      };
      return browser.open("https://example.invalid/", "_blank") === null;
    }),
  ).toBe(true);
  expect(application.windows()).toHaveLength(1);

  await window.getByRole("textbox", { name: "账号" }).fill("desktop-test");
  await window.getByRole("textbox", { name: "密码" }).fill("test-password");
  await window.getByRole("button", { name: "进入工作台" }).click();
  await expect(window).toHaveURL(/#\/professions$/u);
  await expect(
    window.getByRole("heading", { name: "职业与风格" }),
  ).toBeVisible();
});
