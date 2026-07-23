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
- 保持改动聚焦，不覆盖用户未提交的无关修改，不提交凭据或生成输出。

## 中文备注与维护

本仓库的代码必须让首次接触目标模块的前端工程师仅结合相邻公开契约和测试即可维护。
生成代码时不得把页面历史、数据来源、异步时序、认证边界或 Electron 行为留给维护者猜测。

- 新增或实质性重写的 TypeScript、TSX、JavaScript 和 Electron 文件必须在 import 前提供
  中文文件头，说明职责与非职责、上游调用者、下游依赖、输入输出、外部副作用和安全边界。
- 所有导出的组件、Hook、Store API、HTTP API、类、函数、接口和业务类型必须有中文 JSDoc。
  简单类型可用一句话；涉及网络、状态、认证、定时器、浏览器存储或 Electron 的 API 必须
  说明参数来源、返回语义、错误处理、清理方式及“不代表什么”。
- 一个函数或 Hook 包含三个以上业务阶段，或多个副作用存在固定顺序时，必须在阶段前添加
  中文步骤备注，解释先后原因以及当前阶段失败后不得执行的后续动作。
- 首次出现的项目术语、后端状态、DTO 字段和安全约束必须提供局部解释，不能只要求维护者去
  阅读 Server 或旧对话。
- 备注不能只复述变量赋值、条件判断、JSX 标签或 CSS 属性；应解释数据所有权、调用关系、
  竞态保护、边界条件和设计原因。
- 行为、参数、错误码、请求顺序、响应状态或安全边界变化时必须同步更新备注。失真、过期或
  与测试矛盾的备注按代码缺陷处理。
- CSS/SCSS 不逐属性注释；复杂布局、稳定尺寸、响应式断点、层叠覆盖和可访问性处理必须用
  中文区块备注说明约束原因。
- 测试名称应表达“场景 + 预期结果”；安全、竞态和回归测试必须说明保护的真实风险，以及
  Mock 没有证明的浏览器、Electron 或后端集成范围。
- 不使用“显然”“简单”“不用管”“永远不会失败”等措辞，也不写“完全兼容”“已经部署”
  “全技能覆盖”或“生产可用”等未经验证的结论。

具体文件头、JSDoc、组件、Hook、Store、API、Electron、样式和测试备注模板遵守
`client.instructions.md`。

## 验证

- 行为变化增加与风险相称的 Vitest 或 Playwright 测试。
- 至少运行类型检查、Lint 和相关单测；路由、样式、桌面壳或用户流程变化再运行生产
  构建与浏览器/桌面 E2E。
- Prettier 是受管前端、桌面壳、测试、配置和文档的格式事实源。
