import { expect, test } from "@playwright/test";

test("logs in and renders the profession workspace responsively", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page).toHaveTitle("DNF Patch Studio");

  await page.getByRole("textbox", { name: "账号" }).fill("frontend-test");
  await page.getByRole("textbox", { name: "密码" }).fill("test-password");
  await page.getByRole("button", { name: "进入工作台" }).click();

  await expect(page).toHaveURL(/#\/professions$/u);
  await expect(page.getByRole("heading", { name: "职业与风格" })).toBeVisible();
  await expect(page.getByText("剑魂", { exact: true }).first()).toBeVisible();

  const hasHorizontalOverflow = (): Promise<boolean> =>
    page.evaluate(() => {
      const browser = globalThis as unknown as {
        document: {
          documentElement: { clientWidth: number; scrollWidth: number };
        };
      };
      return (
        browser.document.documentElement.scrollWidth >
        browser.document.documentElement.clientWidth
      );
    });

  await expect.poll(hasHorizontalOverflow).toBe(false);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect.poll(hasHorizontalOverflow).toBe(false);
});
