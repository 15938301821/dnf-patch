# VS Code 调试配置

浏览器调试先在终端运行 `npm run dev:web`，再选择“Web 前端”并按 F5。VS Code 会用 Chrome
打开 `http://127.0.0.1:5173` 并映射 `renderer/` 下的 TypeScript/TSX 源码。

桌面调试直接选择“Electron 桌面端”并按 F5；该入口启动 Electron Vite，主进程和
Renderer 使用同一套源码与 source map。

该配置不启动后端，也不包含模型密钥、服务令牌或部署能力。默认 Mock 模式不需要
后端；远程模式按 README 配置 `VITE_API_BASE_URL`。
