/**
 * @fileoverview 定义浏览器、Electron、测试和根配置共享的 ESLint 静态边界。
 *
 * ESLint CLI 消费本扁平配置，忽略生成物，并对 TypeScript 启用项目类型信息；规则限制文件
 * 规模、前端 Node/模型依赖和绕过类型化 API 的网络传输。配置只报告源码问题，不修改运行
 * 逻辑；生成目录与凭据文件不得加入检查输入。
 */
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

/** 仓库手写客户端代码的 ESLint 扁平配置数组。 */
export default tseslint.config(
  {
    ignores: [
      "dist-web/**",
      "out/**",
      "node_modules/**",
      "test-results/**",
      "playwright-report/**",
    ],
  },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked.map((config) => ({
    ...config,
    files: ["**/*.ts", "**/*.tsx"],
  })),
  {
    files: ["**/*.ts", "**/*.tsx"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // 物理行直接反映文件维护成本；注释和空行同样计入职责规模。
      "max-lines": [
        "error",
        { max: 500, skipBlankLines: false, skipComments: false },
      ],
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-confusing-void-expression": "off",
      "@typescript-eslint/no-misused-promises": [
        "error",
        { checksVoidReturn: false },
      ],
    },
  },
  {
    files: ["**/*.js"],
    rules: {
      "max-lines": [
        "error",
        { max: 500, skipBlankLines: false, skipComments: false },
      ],
    },
  },
  {
    files: ["renderer/src/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["node:*", "electron", "openai", "socket.io-client"],
              message:
                "The browser frontend must use its typed HTTP API instead of Node or backend implementations.",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["renderer/src/**/*.{ts,tsx}"],
    ignores: ["renderer/src/api/**"],
    rules: {
      "no-restricted-globals": [
        "error",
        {
          name: "fetch",
          message: "Use the typed modules in renderer/src/api instead.",
        },
        {
          name: "XMLHttpRequest",
          message: "Use the typed modules in renderer/src/api instead.",
        },
        {
          name: "WebSocket",
          message: "Network transports belong in renderer/src/api.",
        },
        {
          name: "EventSource",
          message: "Network transports belong in renderer/src/api.",
        },
      ],
    },
  },
);
