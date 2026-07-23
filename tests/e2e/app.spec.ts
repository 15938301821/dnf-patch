/**
 * @fileoverview 在真实浏览器中验证登录、响应式职业流程和结构化风格门禁。
 *
 * Playwright 连接本地生产预览，API 由 E2E Mock Adapter 替代；测试覆盖 DOM、路由和 390px
 * 溢出风险，但不证明真实 Server、数据库、Worker、模型、对象存储或下载链路。选择器以可访问
 * 角色和名称为边界，不依赖 CSS Modules 生成类名。
 */
import { expect, test, type Page } from "@playwright/test";

test("logs in and renders the profession workspace responsively", async ({
  page,
}) => {
  await login(page);
  await expect(page.getByRole("heading", { name: "职业与风格" })).toBeVisible();
  await expect(page.getByText("剑魂", { exact: true }).first()).toBeVisible();

  await expectNoHorizontalOverflow(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
});

test("creates an empty-skill draft and returns to its profession", async ({
  page,
}) => {
  await login(page);
  await page.getByRole("listitem").filter({ hasText: "狂战士" }).click();
  await expect(page.getByRole("heading", { name: "狂战士" })).toBeVisible();
  await page.getByRole("button", { name: "新建风格" }).click();

  await expect(page).toHaveURL(
    /#\/professions\/profession-berserker\/styles\/new$/u,
  );
  await expect(
    page.getByRole("heading", { name: "新建狂战士风格" }),
  ).toBeVisible();
  await page.getByRole("textbox", { name: "风格名称" }).fill("血月草稿");
  await page.getByRole("button", { name: "创建草稿" }).click();

  await expect(page).toHaveURL(
    /#\/professions\?professionId=profession-berserker$/u,
  );
  await expect(page.getByRole("heading", { name: "狂战士" })).toBeVisible();
  await expect(page.getByText("血月草稿", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("listitem").filter({ hasText: "狂战士1 个风格" }),
  ).toBeVisible();

  await expectNoHorizontalOverflow(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
});

test("submits complete structured content while resource gates stay closed", async ({
  page,
}) => {
  // 使用完整主题内容打开审核门禁，同时保留 Mock 资源未核验状态以验证任务按钮失败关闭。
  await login(page);
  await page.getByRole("button", { name: "新建风格" }).click();
  await expect(
    page.getByRole("heading", { name: "新建剑魂风格" }),
  ).toBeVisible();

  await page.getByRole("textbox", { name: "风格名称" }).fill("结构化冰蓝主题");
  await page
    .getByRole("textbox", { name: "主题目标" })
    .fill("保持职业动作语义并统一为冰蓝剑气视觉。");
  await page
    .getByRole("textbox", { name: "共同视觉基线" })
    .fill("冰蓝刃核、青色裂纹和克制粒子。");
  await page.getByRole("button", { name: "添加颜色" }).click();
  await page.getByPlaceholder("冰蓝主光").fill("冰蓝主光");
  await page.getByPlaceholder("#1A8FFF").fill("#1A8FFF");
  await page
    .getByRole("textbox", { name: "材质规则" })
    .fill("保留白色刃核和冰蓝外辉光。");
  await page
    .getByRole("textbox", { name: "粒子规则" })
    .fill("粒子稀疏并沿原运动方向分布。");
  await page
    .getByRole("textbox", { name: "视觉层次" })
    .fill("裂纹在后、剑气居中、辉光在前。");
  await page
    .getByRole("textbox", { name: "不可变约束" })
    .fill("保持源帧几何、锚点和动作阶段。");
  await page
    .getByRole("textbox", { name: "公共验收" })
    .fill("逐帧轮廓、方向和命中焦点保持可读。");
  await page
    .getByRole("textbox", { name: "公共排除" })
    .fill("排除暖色、文字、水印和无关角色元素。");

  await page.getByRole("tab", { name: "技能编排" }).click();
  const skillCheckbox = page.getByRole("checkbox", {
    name: /^里·鬼剑术/u,
  });
  await skillCheckbox.click();
  await expect(skillCheckbox).toBeChecked();
  await page
    .getByRole("textbox", { name: "主题增量 Prompt" })
    .fill("追加冰蓝月牙剑气和细窄空间裂纹。");
  await page
    .getByRole("textbox", { name: "具体变化" })
    .fill("仅替换剑气材质和粒子颜色。");
  await page
    .getByRole("textbox", { name: "主题验收" })
    .fill("动作时间轴和斩击方向与原技能一致。");
  await page
    .getByRole("textbox", { name: "主题排除" })
    .fill("不修改角色、武器、命中范围或动作节奏。");

  await expectNoHorizontalOverflow(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
  await page.getByRole("button", { name: "创建草稿" }).click();

  await expect(page).toHaveURL(
    /#\/professions\?professionId=profession-sword-soul$/u,
  );
  const styleCard = page
    .getByRole("article")
    .filter({ hasText: "结构化冰蓝主题" });
  await expect(styleCard).toBeVisible();
  await styleCard.getByRole("button", { name: "编辑与预览" }).click();

  const reviewButton = page.getByRole("button", { name: "送审" });
  const taskButton = page.getByRole("button", { name: "创建任务" });
  await expect(reviewButton).toBeEnabled();
  await expect(taskButton).toBeDisabled();
  await expect(page.getByText("当前仅可保存设计稿")).toBeVisible();

  await reviewButton.click();
  await page.getByRole("button", { name: /确\s*定/u }).click();
  await expect(page.getByText("已提交公共模板审核")).toBeVisible();
  await expect(reviewButton).toBeDisabled();
  await expect(taskButton).toBeDisabled();
});

/**
 * 通过浏览器可访问控件建立一段 Mock 会话。
 *
 * @param page 当前 Playwright 页面；预览服务器已由测试配置启动。
 * @returns 导航到职业页且 URL 稳定后结算。
 */
async function login(page: Page): Promise<void> {
  await page.goto("/");
  await expect(page).toHaveTitle("DNF Patch Studio");
  await page.getByRole("textbox", { name: "账号" }).fill("frontend-test");
  await page.getByRole("textbox", { name: "密码" }).fill("test-password");
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page).toHaveURL(/#\/professions$/u);
}

/**
 * 轮询根文档宽度，保护动态内容在当前视口不产生页面级横向滚动。
 *
 * @param page 已渲染目标流程的 Playwright 页面。
 * @returns 根节点滚动宽度不大于客户端宽度时结算。
 */
async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  await expect
    .poll(() =>
      page.evaluate(() => {
        const browser = globalThis as unknown as {
          document: {
            documentElement: { clientWidth: number; scrollWidth: number };
          };
        };
        return (
          browser.document.documentElement.scrollWidth <=
          browser.document.documentElement.clientWidth
        );
      }),
    )
    .toBe(true);
}
