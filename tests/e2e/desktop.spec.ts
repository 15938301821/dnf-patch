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
  const launchedApplication = application;
  application = undefined;
  await launchedApplication?.close().catch(() => undefined);
});

test("loads the frontend in an isolated desktop shell", async () => {
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
