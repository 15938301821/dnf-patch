---
name: "DNF Patch Frontend Engineering"
description: "Use when editing TypeScript, React, Electron shell, tests, configuration, styles, or documentation in the browser-and-desktop DNF Patch Studio repository."
applyTo: "**/*.{ts,tsx,js,mjs,cjs,json,css,scss,md,html}"
---

# 全局工程规范

本仓库维护浏览器前端和最小 Electron 桌面壳。后端 API 拥有职业、技能、模型、任务、
产物与下载事实；禁止引入本地 Server、Worker、CLI、补丁资源、游戏目录访问或
NPK/IMG 工具链。

## 规模与职责

- 单个 TypeScript、TSX、JavaScript、CSS 或 SCSS 文件最多 500 个物理行，达到
  400 行时先拆分职责。
- 组件超过 300 行或承担多个独立流程时，拆为组件、Hook、Store 或纯函数。
- 新目录和文件使用 kebab-case；组件和类型使用 PascalCase；函数、变量和 Hook 使用
  camelCase，Hook 以 `use` 开头。
- 把文件放入最窄的职责目录，不创建 `common`、`misc`、`helpers` 等兜底目录。

## 实现

- 复用现有 React、Ant Design、Axios、Zustand 和本地组件模式，不复制契约或制造无
  实际收益的抽象。
- 结构化数据使用类型化对象与标准 API，不使用脆弱字符串解析。
- Electron 只负责安全窗口加载同一 Renderer，不在主进程或 Preload 重建业务服务。
- 注释只解释不变量、安全边界和非显然原因，不复述代码。
- 保持改动聚焦，不覆盖用户未提交的无关修改，不提交凭据或生成输出。

## 验证

- 行为变化增加与风险相称的 Vitest 或 Playwright 测试。
- 至少运行类型检查、Lint 和相关单测；路由、样式、桌面壳或用户流程变化再运行生产
  构建与浏览器/桌面 E2E。
- Prettier 是受管前端、桌面壳、测试、配置和文档的格式事实源。
