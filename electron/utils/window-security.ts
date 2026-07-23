/**
 * @fileoverview 纯函数判断 Electron Renderer 导航是否仍指向配置的唯一入口。
 *
 * 主进程的主动导航与重定向拦截器调用本模块；输入是目标 URL 和启动入口，输出只做白名单
 * 判定，不打开外部链接。Hash 路由可共享同一入口，协议、主机或规范化路径变化均失败关闭，
 * URL 解析失败也必须拒绝。
 */

/** 去除非根路径末尾斜线，使等价入口路径可稳定比较。 */
function normalizedPathname(pathname: string): string {
  return pathname.length > 1 ? pathname.replace(/\/+$/u, "") : pathname;
}

/**
 * 判断目标地址是否与受信任 Renderer 入口具有相同协议、主机和路径。
 *
 * @param targetUrl Electron 事件提供的待导航或重定向绝对 URL。
 * @param rendererEntryUrl 主进程创建窗口时选定的开发或生产入口 URL。
 * @returns 只在同一入口文件内（可含不同 Hash）返回 `true`；解析失败返回 `false`。
 */
export function isAllowedRendererNavigation(
  targetUrl: string,
  rendererEntryUrl: string,
): boolean {
  try {
    const target = new URL(targetUrl);
    const entry = new URL(rendererEntryUrl);
    return (
      target.protocol === entry.protocol &&
      target.host === entry.host &&
      normalizedPathname(target.pathname) === normalizedPathname(entry.pathname)
    );
  } catch {
    return false;
  }
}
