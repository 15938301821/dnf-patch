import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

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
