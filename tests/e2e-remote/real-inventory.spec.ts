/**
 * @fileoverview 在真实 Chromium 中验证 remote Renderer 的会话与官方 Inventory 概况读取。
 *
 * Server 隔离门禁先完成官方 NPK 导入并创建一次性用户，本用例随后经过页面登录、设置页读取、
 * 整页刷新和登出。输入凭据只来自短命进程环境；用例不打印、不截图、不跟踪，也不创建第二个
 * Inventory Job。成功只证明当前回环 Server/浏览器链，不证明公网、Electron 或最终包下载。
 */
import { expect, test, type Page, type Response } from "@playwright/test";

const username = requiredEnvironment("REAL_BROWSER_USERNAME");
const password = requiredEnvironment("REAL_BROWSER_PASSWORD");
const displayName = requiredEnvironment("REAL_BROWSER_DISPLAY_NAME");
const sourceSha256 = requiredEnvironment("REAL_BROWSER_SOURCE_SHA256");

test("uses a real session to read the frozen Inventory", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "登录" })).toBeVisible();
  await expect(page.getByText("使用服务端账号和密码登录。")).toBeVisible();

  await page.getByRole("textbox", { name: "账号" }).fill(username);
  await page.getByRole("textbox", { name: "密码" }).fill(password);
  const loginResponse = waitForApi(page, "/v1/auth/login", "POST");
  await page.getByRole("button", { name: "进入工作台" }).click();
  expect((await loginResponse).status()).toBe(201);
  await expect(page).toHaveURL(/#\/professions$/u);
  await expect(page.getByText("Remote API", { exact: true })).toBeVisible();
  await expect(page.getByText(displayName, { exact: true })).toBeVisible();

  const overviewResponse = waitForApi(
    page,
    "/v1/resource-imports/overview",
    "GET",
  );
  await page.getByRole("menuitem", { name: "模型设置" }).click();
  expect((await overviewResponse).status()).toBe(200);
  await expect(page.getByRole("heading", { name: "模型设置" })).toBeVisible();
  await expect(page.getByText(sourceSha256, { exact: true })).toBeVisible();
  await expect(page.getByText("空闲", { exact: true })).toBeVisible();
  expect(await browserCredentialStorage(page)).toEqual([]);

  // 整页刷新会清空 JS 内存 Access Token，随后只能用 HttpOnly Cookie 轮换会话并重放 `/auth/me`。
  const refreshResponse = waitForApi(page, "/v1/auth/refresh", "POST");
  await page.reload();
  expect((await refreshResponse).status()).toBe(201);
  await expect(page.getByRole("heading", { name: "模型设置" })).toBeVisible();
  await expect(page.getByText(sourceSha256, { exact: true })).toBeVisible();
  expect(await browserCredentialStorage(page)).toEqual([]);

  const logoutResponse = waitForApi(page, "/v1/auth/logout", "POST");
  await page.getByRole("button", { name: "退出登录" }).click();
  expect((await logoutResponse).status()).toBe(201);
  await expect(page.getByRole("heading", { name: "登录" })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("heading", { name: "登录" })).toBeVisible();
});

/** 等待当前页面发出的精确 API 方法与路径，避免同名 UI 文案被 Mock 响应误判。 */
function waitForApi(
  page: Page,
  path: string,
  method: string,
): Promise<Response> {
  return page.waitForResponse((response) => {
    const url = new URL(response.url());
    return url.pathname === path && response.request().method() === method;
  });
}

/** 返回浏览器持久存储中疑似凭据的键；Access/Refresh Token 均不得出现在这里。 */
async function browserCredentialStorage(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    [...Object.keys(localStorage), ...Object.keys(sessionStorage)].filter(
      (key) => /token|password|credential|session/iu.test(key),
    ),
  );
}

/** 读取总编排提供的一次性字段；错误只报告变量名，不回显变量值。 */
function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}
