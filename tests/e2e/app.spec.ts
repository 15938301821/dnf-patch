/**
 * @fileoverview 在真实浏览器中验证登录、响应式职业流程、风格删除和结构化风格门禁。
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

test("selects one of six reasoning efforts while the image role stays inapplicable", async ({
  page,
}) => {
  await login(page);
  await page.getByRole("menuitem", { name: "模型设置" }).click();
  await expect(page.getByRole("heading", { name: "模型设置" })).toBeVisible();

  const orchestrator = page.locator('[data-role="orchestrator"]');
  const reasoningSelect = orchestrator.getByRole("combobox", {
    name: "推理强度",
  });
  await reasoningSelect.click();
  await expect(page.getByRole("option")).toHaveText([
    "低 · low",
    "中 · medium",
    "高 · high",
    "超高 · xhigh",
    "最大 · max",
    "极致 · ultra",
  ]);
  await expect(page.getByRole("option", { name: /默认/u })).toHaveCount(0);
  await page.getByRole("option", { name: "极致 · ultra" }).click();
  await expect(orchestrator.getByTitle("极致 · ultra")).toBeVisible();

  const referenceGenerator = page.locator('[data-role="referenceGenerator"]');
  await expect(
    referenceGenerator.getByRole("combobox", { name: "推理强度" }),
  ).toBeDisabled();
  await expect(referenceGenerator.getByText("图片接口不适用")).toBeVisible();

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

test("deletes a newly created empty profession and selects its neighbor", async ({
  page,
}) => {
  // Mock 只证明确认交互与列表选择更新；真实所有权、行锁和外键保护由 Server 负责。
  await login(page);
  await page.getByRole("button", { name: "新建职业" }).click();
  await page.getByRole("textbox", { name: "职业名称" }).fill("待删除职业");
  await page.getByRole("textbox", { name: "唯一标识" }).fill("delete-me");
  await page.getByRole("button", { name: /^确\s*定$/u }).click();

  const professionRow = page.getByRole("listitem").filter({
    has: page.getByRole("button", { name: "选择职业待删除职业" }),
  });
  await expect(professionRow).toBeVisible();
  await professionRow
    .getByRole("button", { name: "删除职业待删除职业" })
    .click();
  await expect(page.getByText("删除职业“待删除职业”？")).toBeVisible();
  await page.getByRole("button", { name: /^删\s*除$/u }).click();

  await expect(professionRow).toBeHidden();
  await expect(page.getByText("职业已删除")).toBeVisible();
  await expect(page.getByRole("heading", { name: "剑魂" })).toBeVisible();
  await expectNoHorizontalOverflow(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
});

test("deletes a private style draft after explicit confirmation", async ({
  page,
}) => {
  // Mock 只证明浏览器确认、DELETE 契约与列表同步；真实所有权、事务和限制性外键由 Server 验证。
  await login(page);
  await page.getByRole("listitem").filter({ hasText: "狂战士" }).click();
  await page.getByRole("button", { name: "新建风格" }).click();
  await page.getByRole("textbox", { name: "风格名称" }).fill("待删除草稿");
  await page.getByRole("button", { name: "创建草稿" }).click();

  const styleCard = page.getByRole("article").filter({ hasText: "待删除草稿" });
  await styleCard
    .getByRole("button", { name: "删除职业风格待删除草稿" })
    .click();
  await expect(page.getByText("删除“待删除草稿”？")).toBeVisible();
  await page.getByRole("button", { name: /^删\s*除$/u }).click();

  await expect(styleCard).toBeHidden();
  await expect(page.getByText("职业风格已删除")).toBeVisible();
  await expect(
    page.getByRole("listitem").filter({ hasText: "狂战士0 个风格" }),
  ).toBeVisible();
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
  const skillSearch = page.getByRole("textbox", { name: "搜索职业技能" });
  await skillSearch.fill("里·鬼剑术");
  await expect(
    page.getByText("显示 1 项", { exact: true }).first(),
  ).toBeVisible();
  await expect(page.getByRole("checkbox")).toHaveCount(1);
  const skillCheckbox = page.getByRole("checkbox", {
    name: /^里·鬼剑术/u,
  });
  await skillCheckbox.click();
  await expect(skillCheckbox).toBeChecked();
  await skillSearch.clear();
  await expect(page.getByText("显示 16 项", { exact: true })).toBeVisible();

  const promptSearch = page.getByRole("textbox", { name: "搜索已选技能" });
  await promptSearch.fill("里·鬼剑术");
  await expect(page.getByRole("tab", { name: /里·鬼剑术/u })).toBeVisible();
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

  const promptFilter = page.getByRole("radiogroup", {
    name: "筛选技能 Prompt 完成度",
  });
  await promptFilter.getByText("完整", { exact: true }).click();
  await expect(page.getByRole("tab", { name: /里·鬼剑术/u })).toBeVisible();
  await promptFilter.getByText("待补充", { exact: true }).click();
  await expect(page.getByText("没有符合条件的技能")).toBeVisible();
  await promptFilter.getByText("全部", { exact: true }).click();

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

test("opens a running task from its row and observes the next polling cycle", async ({
  page,
}) => {
  // Axios Mock 替代真实详情 API；本流程验证路由、DOM 和 3 秒轮询可见状态，不证明 Provider 正在调用。
  await login(page);
  await page.getByRole("menuitem", { name: "制作任务" }).click();
  await expect(page.getByRole("heading", { name: "制作任务" })).toBeVisible();
  await page.getByRole("link", { name: "查看剑魂暗蓝幻影任务详情" }).click();

  await expect(page).toHaveURL(/#\/jobs\/job-demo-running$/u);
  await expect(
    page.getByRole("heading", { name: "剑魂 · 暗蓝幻影" }),
  ).toBeVisible();
  await expect(page.getByRole("heading", { name: "任务工作流" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "逐技能进度" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "大模型吞吐" })).toBeVisible();
  await expect(
    page.getByRole("img", { name: "模型输出吞吐趋势" }),
  ).toBeVisible();
  await expect(page.getByText("未计量", { exact: true }).first()).toBeVisible();

  // 运行态 Hook 在首个响应完成 3 秒后启动下一轮；Mock 每次响应推进审计时间，避免依赖短暂加载标记。
  const updatedAt = page
    .getByText("最近更新", { exact: true })
    .locator("..")
    .locator("dd");
  const firstUpdatedAt = await updatedAt.textContent();
  await expect(updatedAt).not.toHaveText(firstUpdatedAt ?? "", {
    timeout: 5_000,
  });
  await expectNoHorizontalOverflow(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
});

test("polls the task list and archives only a terminal task", async ({
  page,
}) => {
  // Axios Mock 替代真实列表与归档 API；本流程验证浏览器定时器、确认交互和行可见性，
  // 不证明真实 Server 的用户所有权、MySQL 行锁、migration 或证据保留。
  await login(page);
  await page.getByRole("menuitem", { name: "制作任务" }).click();
  await expect(page.getByRole("heading", { name: "制作任务" })).toBeVisible();

  const runningRow = page.getByRole("link", {
    name: "查看剑魂暗蓝幻影任务详情",
  });
  const runningProgress = runningRow.getByRole("progressbar");
  const firstProgress = await runningProgress.getAttribute("aria-valuenow");
  await expect(runningProgress).not.toHaveAttribute(
    "aria-valuenow",
    firstProgress ?? "",
    { timeout: 5_000 },
  );
  await expect(
    runningRow.getByRole("button", {
      name: "从列表移除剑魂暗蓝幻影任务",
    }),
  ).toBeDisabled();

  const completedRow = page.getByRole("link", {
    name: "查看气功师（女）樱花念气任务详情",
  });
  await completedRow
    .getByRole("button", { name: "从列表移除气功师（女）樱花念气任务" })
    .click();
  await expect(page.getByText("从任务列表移除？")).toBeVisible();
  await page.getByRole("button", { name: /^移\s*除$/u }).click();

  await expect(completedRow).toBeHidden();
  await expect(page.getByText("任务已从列表移除")).toBeVisible();
  await expect(page).toHaveURL(/#\/jobs$/u);
  await expectNoHorizontalOverflow(page);
});

test("compares source, model reference, and Aseprite result evidence", async ({
  page,
}) => {
  // 三个静态 PNG 替代真实对象存储对象；pageerror 覆盖历史 V2 字段误读导致整页白屏的风险。
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await login(page);
  await page.getByRole("menuitem", { name: "制作任务" }).click();
  await page
    .getByRole("link", { name: "查看气功师（女）樱花念气任务详情" })
    .click();

  await expect(page).toHaveURL(/#\/jobs\/job-demo-complete$/u);
  await expect(
    page.getByRole("heading", { name: "气功师（女） · 樱花念气" }),
  ).toBeVisible();
  await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "查看念气罩三图证据对比" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.getByText("3 / 3 项证据")).toBeVisible();
  await expect(page.getByText("风格与构图参考", { exact: true })).toBeVisible();
  await expect(page.getByText("受控重建", { exact: true })).toBeVisible();
  const qualityGate = page.getByRole("region", {
    name: "当前稳定帧质量门禁",
  });
  await expect(qualityGate).toContainText("孤立噪点");
  await expect(qualityGate).toContainText("连续能量带");
  await expect(qualityGate).toContainText("亮核占比");
  await expect(qualityGate).toContainText("锐边对比");
  await expect(qualityGate).toContainText("强边缘占比");
  await expect(qualityGate).toContainText("周期栅栏");
  await expect(qualityGate).toContainText("近白长线占比");
  await expect(qualityGate).toContainText("DXT1 边界跳变");
  await expect(qualityGate).toContainText("官方能量拓扑相关性");
  await expect(qualityGate).toContainText("0.5%");
  await expect(qualityGate).toContainText("78%");
  await expect(qualityGate).toContainText("72.00");
  await expect(qualityGate).toContainText("12%");
  await expect(qualityGate).toContainText("34%");
  await expect(qualityGate).toContainText("1%");
  await expect(qualityGate).toContainText("90%");
  const comparisonImages = [
    page.getByRole("img", { name: "念气罩技能源帧" }),
    page.getByRole("img", { name: "念气罩模型参考图" }),
    page.getByRole("img", { name: "念气罩模型 + Aseprite 结果" }),
  ];
  for (const image of comparisonImages) {
    await expect(image).toBeVisible();
    await expect
      .poll(() =>
        image.evaluate(
          (element) =>
            (element as unknown as { naturalWidth?: number }).naturalWidth ?? 0,
        ),
      )
      .toBeGreaterThan(0);
  }
  await page
    .getByRole("button", { name: "念气罩模型参考图", exact: true })
    .click();
  const imagePreview = page.getByRole("dialog").last();
  await expect(imagePreview.getByText("2 / 3", { exact: true })).toBeVisible();
  const nextImage = imagePreview.getByRole("button", {
    name: "right",
    exact: true,
  });
  await expect(nextImage).toHaveCSS("z-index", "2");
  await nextImage.click();
  await expect(imagePreview.getByText("3 / 3", { exact: true })).toBeVisible();
  await imagePreview
    .getByRole("button", { name: "close", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "zoomIn", exact: true }),
  ).toBeHidden();
  await expectNoHorizontalOverflow(page);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByText("Aseprite 结果", { exact: true }).click();
  await expect(
    page.getByRole("img", { name: "念气罩模型 + Aseprite 结果" }),
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);

  await page.getByRole("button", { name: "Close" }).click();
  await expect(page.getByRole("dialog")).toBeHidden();
  expect(pageErrors).toEqual([]);
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
